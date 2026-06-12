#!/usr/bin/env bash
# Wire up the public Cloudflare DNS + Pages custom domains for the
# auslandictionary.org info site, idempotently:
#
#   auslandictionary.org       → the `auslan-dictionary` Pages project.
#   www.auslandictionary.org   → the same project.
#
# For each host it clears any stale DNS record, points a proxied CNAME at
# the project's *.pages.dev target, and attaches the host as a Pages custom
# domain. Re-running is safe.
#
# Why a script and not just the Pages dashboard "add domain" button? The
# auslandictionary.org zone shipped with a dead `A → 2.31.150.138`
# placeholder; attaching a custom domain on top of it isn't enough, because
# the hostname keeps resolving to the stale record until it's deleted. This
# reconciles the record and the binding in one idempotent step. It mirrors
# dictionary_backend/scripts/attach-domains.sh, which does the same for the
# shared-lists api.* / share.* hosts — the split is deliberate: this repo
# owns the apex site, the private backend repo owns the lists backend.
#
# Requires CLOUDFLARE_ACCOUNT_ID and a CLOUDFLARE_API_TOKEN with:
#   Account → Cloudflare Pages: Edit   — read the project, attach the domains.
#   Zone    → DNS: Edit                — replace the stale records with the CNAMEs.
#   Zone    → Zone: Read               — resolve the zone id.
# Scope the zone permissions to auslandictionary.org. Also needs python3.
#
# Run it AFTER a `wrangler pages deploy` — the project must already exist so
# we can read its *.pages.dev target. Instead of passing the two vars
# inline, drop them into a gitignored secrets.env next to this script — it's
# sourced automatically if present.

set -euo pipefail

PAGES_PROJECT="auslan-dictionary"
ZONE="auslandictionary.org"
HOSTS="auslandictionary.org www.auslandictionary.org"

usage() {
  echo "Usage: ${0##*/}"
  echo
  echo "Reconciles DNS + Pages custom domains for: $HOSTS"
  echo "Reads CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID from the"
  echo "environment or from a sibling secrets.env."
}

case "${1:-}" in -h|--help) usage; exit 0 ;; esac

# Pull credentials from a sibling secrets.env if present (gitignored), so you
# don't have to pass CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID inline.
# `set -a` exports whatever it defines, so bare `KEY=value` lines work too.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ -f "$SCRIPT_DIR/secrets.env" ]; then
  set -a; . "$SCRIPT_DIR/secrets.env"; set +a
fi

: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN must be set (inline or in secrets.env)}"
: "${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID must be set (inline or in secrets.env)}"

CF="https://api.cloudflare.com/client/v4"

# cf METHOD PATH [JSON_BODY] — authenticated Cloudflare API call, body on stdout.
cf() {
  local method="$1" path="$2"
  if [ "$#" -ge 3 ]; then
    curl -sS -X "$method" \
      -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
      -H "Content-Type: application/json" -d "$3" "${CF}${path}"
  else
    curl -sS -X "$method" \
      -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
      -H "Content-Type: application/json" "${CF}${path}"
  fi
}

# Exit 0 iff the JSON on stdin has "success": true.
ok() {
  python3 -c 'import sys,json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
sys.exit(0 if isinstance(d, dict) and d.get("success") else 1)'
}

# NOTE: reconcile_dns is duplicated verbatim in the sibling copy of this
# script (dictionary_backend/scripts/attach-domains.sh and
# auslan_dictionary/site/scripts/attach-domains.sh). The split is deliberate,
# but any change here must be mirrored into the other copy or the two will
# drift.
#
# reconcile_dns ZONE_ID HOST TARGET — delete every A/AAAA/CNAME at HOST that
# isn't a proxied CNAME to TARGET. Sets the global RECONCILE_CORRECT to the id
# of a kept correct CNAME, or "".
RECONCILE_CORRECT=""
reconcile_dns() {
  local zid="$1" host="$2" target="$3"
  local recs analysis rid rtype rcontent del
  recs=$(cf GET "/zones/${zid}/dns_records?name=${host}&per_page=100")
  if ! printf '%s' "$recs" | ok; then
    echo "  ✗ DNS read failed (token needs DNS: Edit):"
    printf '%s\n' "$recs" | sed 's/^/    /'
    return 1
  fi
  analysis=$(printf '%s' "$recs" | python3 -c '
import sys, json
target = sys.argv[1].rstrip(".").lower()
recs = (json.load(sys.stdin).get("result") or [])
correct = ""
conflicts = []
for r in recs:
    t = r.get("type")
    content = str(r.get("content", "")).rstrip(".").lower()
    if target and t == "CNAME" and content == target and r.get("proxied"):
        correct = r["id"]
    elif t in ("A", "AAAA", "CNAME"):
        conflicts.append("%s\t%s\t%s" % (r["id"], t, r.get("content", "")))
print(correct)
for c in conflicts:
    print(c)
' "$target")
  RECONCILE_CORRECT=$(printf '%s\n' "$analysis" | sed -n '1p')
  while IFS=$'\t' read -r rid rtype rcontent; do
    [ -z "$rid" ] && continue
    echo "    removing conflicting $rtype record → $rcontent"
    del=$(cf DELETE "/zones/${zid}/dns_records/${rid}")
    if ! printf '%s' "$del" | ok; then
      echo "      ✗ delete failed:"; printf '%s\n' "$del" | sed 's/^/        /'; return 1
    fi
  done < <(printf '%s\n' "$analysis" | tail -n +2)
}

# Is HOST already a custom domain on the Pages project? (Cloudflare returns
# several different "already added" error codes on re-POST, so confirm by
# listing rather than matching codes.)
pages_domain_present() {
  local host="$1" resp
  resp=$(cf GET "/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${PAGES_PROJECT}/domains")
  printf '%s' "$resp" | ok || return 1
  printf '%s' "$resp" | python3 -c 'import sys,json
host = sys.argv[1].lower()
for d in (json.load(sys.stdin).get("result") or []):
    if str(d.get("name", "")).lower() == host:
        sys.exit(0)
sys.exit(1)' "$host"
}

# HOST → the Pages project, with a proxied CNAME at HOST.
configure_pages_domain() {
  local host="$1"
  echo "→ $host → Pages '$PAGES_PROJECT' ($PAGES_SUBDOMAIN)"
  reconcile_dns "$ZONE_ID" "$host" "$PAGES_SUBDOMAIN" || return 1
  if [ -n "$RECONCILE_CORRECT" ]; then
    echo "  ✓ DNS already a proxied CNAME → $PAGES_SUBDOMAIN"
  else
    local cre
    # A proxied CNAME at the zone apex is fine — Cloudflare flattens it.
    cre=$(cf POST "/zones/${ZONE_ID}/dns_records" \
      "{\"type\":\"CNAME\",\"name\":\"${host}\",\"content\":\"${PAGES_SUBDOMAIN}\",\"proxied\":true}")
    if printf '%s' "$cre" | ok; then
      echo "  ✓ created proxied CNAME → $PAGES_SUBDOMAIN"
    else
      echo "  ✗ CNAME create failed:"; printf '%s\n' "$cre" | sed 's/^/    /'; return 1
    fi
  fi

  local att
  att=$(cf POST "/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${PAGES_PROJECT}/domains" \
    "{\"name\":\"${host}\"}")
  if printf '%s' "$att" | ok; then
    echo "  ✓ attached to Pages project"
  elif pages_domain_present "$host"; then
    echo "  ✓ already attached to Pages project"
  else
    echo "  ✗ Pages domain attach failed:"; printf '%s\n' "$att" | sed 's/^/    /'; return 1
  fi
}

# The Pages project's *.pages.dev target (what the CNAMEs point at). Reading it
# also confirms the project exists — it won't until the first `pages deploy`.
proj=$(cf GET "/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${PAGES_PROJECT}")
PAGES_SUBDOMAIN=$(printf '%s' "$proj" | python3 -c \
  'import sys,json;d=json.load(sys.stdin);print((d.get("result") or {}).get("subdomain","") if isinstance(d,dict) and d.get("success") else "")')
if [ -z "$PAGES_SUBDOMAIN" ]; then
  echo "ERROR: could not read Pages project '$PAGES_PROJECT'."
  echo "Deploy it first (\`npx wrangler@latest pages deploy\` from site/), and"
  echo "confirm the token has Cloudflare Pages: Edit."
  printf '%s\n' "$proj"; exit 1
fi

# Resolve the zone id once — every host lives in the same zone.
zresp=$(cf GET "/zones?name=${ZONE}")
if ! printf '%s' "$zresp" | ok; then
  echo "ERROR: zone lookup failed for $ZONE (token needs Zone: Read):"
  printf '%s\n' "$zresp" | sed 's/^/  /'; exit 1
fi
ZONE_ID=$(printf '%s' "$zresp" | python3 -c \
  'import sys,json;r=(json.load(sys.stdin).get("result") or []);print(r[0]["id"] if r else "")')
if [ -z "$ZONE_ID" ]; then
  echo "ERROR: zone '$ZONE' is not on this Cloudflare account."; exit 1
fi

rc=0
for host in $HOSTS; do
  configure_pages_domain "$host" || { echo "  ✗ $host not configured"; rc=1; }
done

if [ "$rc" -eq 0 ]; then
  echo "Done. A freshly-attached custom domain can take a minute to start serving."
fi
exit "$rc"
