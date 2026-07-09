#!/usr/bin/env python3
"""Promote the just-uploaded build to a TestFlight external tester group.

Run after an upload (see publish.sh --beta). Talks to the App Store Connect API:
finds the build by its build number, waits for it to finish processing, sets the
"What to Test" notes, adds it to the named external group, and submits it for
Beta App Review (external groups require review before testers get the build).

Self-contained: standard library only. The ES256 JWT is signed with `openssl`,
so there are no pip dependencies.

Config comes from the environment (publish.sh sets these):
  APP_STORE_CONNECT_API_KEY_ID, APP_STORE_CONNECT_API_ISSUER_ID, API_KEY_PATH
  ASC_BUNDLE_ID, ASC_BUILD_NUMBER, ASC_GROUP_NAME, ASC_WHATS_NEW
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
LOCALE = "en-US"
POLL_TIMEOUT_S = 30 * 60
POLL_INTERVAL_S = 30


def die(msg):
    print(f"\n[appstore_beta] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def env(name):
    value = os.environ.get(name)
    if not value:
        die(f"missing required env var {name}")
    return value


def b64url(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def _der_to_raw(der):
    # openssl emits an ECDSA signature as DER (SEQUENCE of two INTEGERs); JOSE
    # (ES256) wants raw r||s, 32 bytes each. P-256 sigs are short, so all the
    # ASN.1 lengths are single-byte (short form).
    if not der or der[0] != 0x30:
        die("unexpected signature encoding from openssl")
    i = 2  # skip SEQUENCE tag + length byte
    if der[i] != 0x02:
        die("bad signature (expected INTEGER for r)")
    rlen = der[i + 1]
    r = der[i + 2 : i + 2 + rlen]
    i = i + 2 + rlen
    if der[i] != 0x02:
        die("bad signature (expected INTEGER for s)")
    slen = der[i + 1]
    s = der[i + 2 : i + 2 + slen]
    r = r.lstrip(b"\x00").rjust(32, b"\x00")
    s = s.lstrip(b"\x00").rjust(32, b"\x00")
    return r + s


def make_token():
    key_id = env("APP_STORE_CONNECT_API_KEY_ID")
    issuer = env("APP_STORE_CONNECT_API_ISSUER_ID")
    key_path = env("API_KEY_PATH")
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    now = int(time.time())
    payload = {
        "iss": issuer,
        "iat": now,
        "exp": now + 1200,
        "aud": "appstoreconnect-v1",
    }
    signing_input = (
        b64url(json.dumps(header, separators=(",", ":")).encode())
        + "."
        + b64url(json.dumps(payload, separators=(",", ":")).encode())
    )
    proc = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input.encode(),
        capture_output=True,
    )
    if proc.returncode != 0:
        die("openssl signing failed: " + proc.stderr.decode(errors="replace"))
    return signing_input + "." + b64url(_der_to_raw(proc.stdout))


def api(token, method, path, body=None, params=None):
    url = API + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        try:
            parsed = json.loads(raw)
        except Exception:
            parsed = {"errors": [{"detail": raw.decode(errors="replace")}]}
        return exc.code, parsed


def err_detail(data):
    errors = data.get("errors", []) if isinstance(data, dict) else []
    joined = "; ".join(
        f"{e.get('title', '')}: {e.get('detail', '')}".strip(": ") for e in errors
    )
    return joined or json.dumps(data)[:500]


def main():
    bundle_id = env("ASC_BUNDLE_ID")
    build_number = env("ASC_BUILD_NUMBER")
    group_name = env("ASC_GROUP_NAME")
    whats_new = os.environ.get("ASC_WHATS_NEW", "").strip()
    if not whats_new:
        die("ASC_WHATS_NEW is empty — external testers require 'What to Test' notes")

    token = make_token()

    # 1. App.
    st, data = api(token, "GET", "/v1/apps", params={"filter[bundleId]": bundle_id})
    if st != 200 or not data.get("data"):
        die(f"could not find app {bundle_id}: {err_detail(data)}")
    app_id = data["data"][0]["id"]
    print(f"[appstore_beta] app {bundle_id} -> {app_id}")

    # 2. Find the build and wait for it to finish processing.
    print(f"[appstore_beta] waiting for build {build_number} to finish processing...")
    deadline = time.time() + POLL_TIMEOUT_S
    build_id = None
    while time.time() < deadline:
        st, data = api(
            token,
            "GET",
            "/v1/builds",
            params={
                "filter[app]": app_id,
                "filter[version]": build_number,
                "sort": "-uploadedDate",
                "limit": "1",
                "fields[builds]": "version,processingState",
            },
        )
        builds = data.get("data", []) if st == 200 else []
        if builds:
            state = builds[0]["attributes"]["processingState"]
            print(f"  build {build_number}: {state}")
            if state == "VALID":
                build_id = builds[0]["id"]
                break
            if state in ("INVALID", "FAILED"):
                die(f"build {build_number} failed processing ({state})")
        else:
            print("  not visible yet (App Store Connect is still ingesting it)...")
        time.sleep(POLL_INTERVAL_S)
    if not build_id:
        die("timed out waiting for the build to finish processing")
    print(f"[appstore_beta] build is VALID -> {build_id}")

    # 3. "What to Test" notes (betaBuildLocalizations, en-US).
    st, data = api(token, "GET", f"/v1/builds/{build_id}/betaBuildLocalizations")
    existing = (
        {loc["attributes"]["locale"]: loc["id"] for loc in data.get("data", [])}
        if st == 200
        else {}
    )
    if LOCALE in existing:
        st, data = api(
            token,
            "PATCH",
            f"/v1/betaBuildLocalizations/{existing[LOCALE]}",
            body={
                "data": {
                    "type": "betaBuildLocalizations",
                    "id": existing[LOCALE],
                    "attributes": {"whatsNew": whats_new},
                }
            },
        )
    else:
        st, data = api(
            token,
            "POST",
            "/v1/betaBuildLocalizations",
            body={
                "data": {
                    "type": "betaBuildLocalizations",
                    "attributes": {"locale": LOCALE, "whatsNew": whats_new},
                    "relationships": {
                        "build": {"data": {"type": "builds", "id": build_id}}
                    },
                }
            },
        )
    if st not in (200, 201):
        die(f"failed to set 'What to Test': {err_detail(data)}")
    print("[appstore_beta] set 'What to Test' notes")

    # 4. Find the external group.
    st, data = api(
        token,
        "GET",
        "/v1/betaGroups",
        params={"filter[app]": app_id, "filter[name]": group_name, "limit": "1"},
    )
    if st != 200 or not data.get("data"):
        die(f"external group {group_name!r} not found for this app: {err_detail(data)}")
    group_id = data["data"][0]["id"]
    print(f"[appstore_beta] group {group_name!r} -> {group_id}")

    # 5. Add the build to the group.
    st, data = api(
        token,
        "POST",
        f"/v1/betaGroups/{group_id}/relationships/builds",
        body={"data": [{"type": "builds", "id": build_id}]},
    )
    if st in (200, 204):
        print(f"[appstore_beta] added build to {group_name!r}")
    elif st in (409, 422) and "already" in err_detail(data).lower():
        print(f"[appstore_beta] build is already in {group_name!r}")
    else:
        die(f"failed to add build to {group_name!r}: {err_detail(data)}")

    # 6. Submit for Beta App Review (required for external testers).
    st, data = api(
        token,
        "POST",
        "/v1/betaAppReviewSubmissions",
        body={
            "data": {
                "type": "betaAppReviewSubmissions",
                "relationships": {
                    "build": {"data": {"type": "builds", "id": build_id}}
                },
            }
        },
    )
    if st == 201:
        print("[appstore_beta] submitted for Beta App Review")
    elif st == 409:
        print(f"[appstore_beta] already submitted / in review ({err_detail(data)})")
    else:
        die(f"failed to submit for Beta App Review: {err_detail(data)}")

    print(
        f"\n[appstore_beta] Done — build {build_number} is on its way to "
        f"'{group_name}' (pending Beta App Review)."
    )


if __name__ == "__main__":
    main()
