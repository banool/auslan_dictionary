"""
Upload the captured store screenshots to App Store Connect and the Google
Play Console — the publishing counterpart to take_screenshots.py.

No fastlane: both stores are driven directly through their REST APIs using
only the Python standard library plus the openssl CLI (for signing the
auth JWTs).

Run from anywhere:
    python3 screenshots/upload_screenshots.py               # both stores
    python3 screenshots/upload_screenshots.py --ios-only
    python3 screenshots/upload_screenshots.py --android-only
    python3 screenshots/upload_screenshots.py --dry-run     # plan only

Credentials:
  - App Store Connect: the same ios/publish.env that ios/publish.sh uses
    (APP_STORE_CONNECT_API_ISSUER_ID, API_KEY_PATH, and optionally
    APP_STORE_CONNECT_API_KEY_ID — the key ID is derived from the
    AuthKey_<ID>.p8 filename when the file keeps Apple's name). Real
    environment variables win over publish.env.
  - Google Play: a service account JSON key at
    android/play_service_account.json, or wherever
    PLAY_SERVICE_ACCOUNT_JSON_PATH points. Use the same service account CI
    publishes builds with (the ANDROID_SERVICE_ACCOUNT_JSON secret); it
    needs permission to edit the store listing in the Play Console.

The App Store attaches screenshots to an *editable* app version (e.g. one
in Prepare for Submission), so create the new version in App Store Connect
before running this. Google Play has no such requirement: all uploads
happen inside a single Play edit that is only committed once every image
is up, so a failed run changes nothing there.
"""

import argparse
import base64
import hashlib
import json
import logging
import os
import re
import struct
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SCREENSHOTS_DIR = PROJECT_ROOT / "screenshots"

IOS_BUNDLE_ID = "com.banool.auslanDictionary"
ANDROID_PACKAGE_NAME = "com.banool.auslan_dictionary"

IOS_PUBLISH_ENV = PROJECT_ROOT / "ios" / "publish.env"
PLAY_KEY_PATH = Path(
    os.environ.get("PLAY_SERVICE_ACCOUNT_JSON_PATH")
    or PROJECT_ROOT / "android" / "play_service_account.json"
)

# --- Capture -> store slot mapping. ---

# App Store Connect groups screenshots into one set per "display type" per
# locale. The WxH token take_screenshots.py embeds in each filename
# identifies the capture device, and this maps it onto the right set. Note
# there are no 6.9"/6.3"/13" enum values: Apple folded the newer panels
# into the older slots, so APP_IPHONE_67 is the slot that accepts
# 1320x2868, and so on. Landscape captures carry the portrait WxH token in
# their filename; the slots accept either orientation.
IOS_DISPLAY_TYPES = {
    "1320x2868": "APP_IPHONE_67",          # iPhone 17 Pro Max -> 6.9" slot.
    "1206x2622": "APP_IPHONE_61",          # iPhone 17 -> 6.3" slot.
    "2064x2752": "APP_IPAD_PRO_3GEN_129",  # iPad Pro 13" -> 13" slot.
}

# Google Play instead has one image slot per device class. The tablet
# captures fill both tablet slots (Play still distinguishes 7" from 10" in
# the API and scales as needed). The 1920x1080 touch-TV captures have no
# Play slot at all — tvScreenshots is for Android TV releases, which this
# app doesn't ship — so they stay local-only.
ANDROID_IMAGE_TYPES = {
    "1080x2400": ["phoneScreenshots"],
    "2560x1600": ["sevenInchScreenshots", "tenInchScreenshots"],
    "1920x1080": [],  # Touch TV; no Play slot, see above.
}

# --- Which captures actually go up, in storefront order. ---

# The stores cap a listing's screenshots (10 per App Store display type, 8
# per Play slot) and the harness captures more than that, so these ordered
# lists pick the marketable subset. Edit freely to re-curate: order here is
# the order shoppers see. A listed shot missing on disk is an error;
# unlisted shots are skipped with a log line.
APP_STORE_LIMIT = 10
PLAY_LIMIT = 8
APP_STORE_SHOTS = [
    "01-search",
    "02-searchResults",
    "03-wordPage",
    "04-saveToList",
    "05-lists",
    "06-insideList",
    "07-revisionLanding",
    "08-flashcardFront",
    "09-flashcardRevealed",
    "11-searchDark",
]
PLAY_SHOTS = [
    "01-search",
    "02-searchResults",
    "03-wordPage",
    "04-saveToList",
    "05-lists",
    "06-insideList",
    "08-flashcardFront",
    "09-flashcardRevealed",
]

# Filenames look like "iPhone 17-1206x2622-04-saveToList.png".
FILENAME_RE = re.compile(
    r"^(?P<device>.+)-(?P<res>\d+x\d+)-(?P<slug>\d{2}-[A-Za-z0-9]+)\.png$"
)

ASC_API = "https://api.appstoreconnect.apple.com"
# States in which a version's metadata (and so its screenshots) can still
# be edited. Apple doesn't publish this list; it matches what fastlane's
# spaceship used.
ASC_EDITABLE_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "WAITING_FOR_REVIEW",
    "INVALID_BINARY",
}

PLAY_API = "https://androidpublisher.googleapis.com/androidpublisher/v3"
PLAY_UPLOAD_API = (
    "https://androidpublisher.googleapis.com/upload/androidpublisher/v3"
)
PLAY_TOKEN_URL = "https://oauth2.googleapis.com/token"
PLAY_SCOPE = "https://www.googleapis.com/auth/androidpublisher"

LOG = logging.getLogger("upload")


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("-d", "--debug", action="store_true")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be uploaded where without touching the stores",
    )
    parser.add_argument(
        "--ios-only", action="store_true", help="Only upload to the App Store"
    )
    parser.add_argument(
        "--android-only",
        action="store_true",
        help="Only upload to Google Play",
    )
    return parser.parse_args()


# --- Small primitives -------------------------------------------------------


def http(method, url, *, headers=None, body=None):
    """Make an HTTP request and return the raw response body, raising with
    the response text on any non-2xx status (store APIs put the useful
    error detail in the body)."""
    req = urllib.request.Request(
        url, data=body, method=method, headers=headers or {}
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.read()
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        raise RuntimeError(f"{method} {url} -> HTTP {e.code}:\n{detail}") from e


def png_dimensions(path):
    """Width and height from a PNG's IHDR header. Also rejects PNGs with an
    alpha channel up front: both stores refuse those (App Store Connect
    fails them with IMAGE_ALPHA_NOT_ALLOWED after upload), and
    take_screenshots.py flattens its captures, so alpha here means the file
    predates that and needs regenerating."""
    with open(path, "rb") as f:
        head = f.read(26)
    if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        raise RuntimeError(f"{path} is not a PNG")
    colour_type = head[25]
    if colour_type in (4, 6):  # Greyscale+alpha / RGBA.
        raise RuntimeError(
            f"{path} has an alpha channel, which the stores reject — "
            "regenerate it with take_screenshots.py (which now flattens "
            "captures to 24-bit RGB)"
        )
    return struct.unpack(">II", head[16:24])


def _b64url(data):
    return base64.urlsafe_b64encode(data).decode().rstrip("=")


def _openssl_sign(key_path, message):
    """SHA-256 sign with openssl; the key's type picks the algorithm
    (EC .p8 -> ECDSA for Apple, RSA -> RS256 for Google)."""
    res = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(key_path)],
        input=message,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if res.returncode != 0:
        raise RuntimeError(f"openssl signing failed: {res.stderr.decode()}")
    return res.stdout


def _der_to_raw_ecdsa(der):
    """Convert openssl's ASN.1 DER ECDSA signature (SEQUENCE of two
    INTEGERs) into the raw 64-byte r||s form JWTs want."""

    def read_int(pos):
        if der[pos] != 0x02:
            raise RuntimeError("expected ASN.1 INTEGER in ECDSA signature")
        length = der[pos + 1]
        start = pos + 2
        return der[start:start + length], start + length

    # P-256 signatures are < 128 bytes total, so the single-byte ASN.1
    # length form is guaranteed and der[1] needs no long-form handling.
    if der[0] != 0x30:
        raise RuntimeError("expected ASN.1 SEQUENCE in ECDSA signature")
    r, pos = read_int(2)
    s, _ = read_int(pos)

    def pad(component):
        return component.lstrip(b"\x00").rjust(32, b"\x00")

    return pad(r) + pad(s)


def make_jwt(header, payload, sign):
    def compact(obj):
        return _b64url(json.dumps(obj, separators=(",", ":")).encode())

    signing_input = f"{compact(header)}.{compact(payload)}"
    return f"{signing_input}.{_b64url(sign(signing_input.encode()))}"


# --- Discovery: what's on disk and where it should go -----------------------


def discover(platform):
    """Walk screenshots/<platform>/<locale>/ and return
    {locale: [(res_token, ordered list of Paths), ...]} after applying the
    selection list and sanity-checking each file's pixel size against the
    size its name claims (in either orientation, since landscape captures
    keep the portrait token)."""
    root = SCREENSHOTS_DIR / platform
    selection = APP_STORE_SHOTS if platform == "ios" else PLAY_SHOTS
    limit = APP_STORE_LIMIT if platform == "ios" else PLAY_LIMIT
    slot_map = IOS_DISPLAY_TYPES if platform == "ios" else ANDROID_IMAGE_TYPES
    if len(selection) > limit:
        raise RuntimeError(
            f"{platform} selection lists {len(selection)} shots but the "
            f"store caps a listing at {limit}; trim the list"
        )

    out = {}
    for locale_dir in sorted(root.iterdir()) if root.exists() else []:
        if not locale_dir.is_dir() or locale_dir.name.startswith("."):
            continue
        groups = {}
        for f in sorted(locale_dir.glob("*.png")):
            m = FILENAME_RE.match(f.name)
            if not m:
                raise RuntimeError(f"unrecognized screenshot filename: {f}")
            if m["res"] not in slot_map:
                raise RuntimeError(
                    f"{f} has unmapped size {m['res']} — a new capture "
                    "device? Add it to IOS_DISPLAY_TYPES / "
                    "ANDROID_IMAGE_TYPES in this script."
                )
            claimed = sorted(int(x) for x in m["res"].split("x"))
            if sorted(png_dimensions(f)) != claimed:
                raise RuntimeError(
                    f"{f} is {'x'.join(map(str, png_dimensions(f)))} but its "
                    f"name claims {m['res']} — stale or corrupt capture?"
                )
            if platform == "android" and claimed[1] > 2 * claimed[0]:
                # Play's published rule is that the long side may be at
                # most twice the short side. The server has the final say
                # (the upload either succeeds or fails loudly before the
                # edit commits), but flag it up front.
                LOG.warning(
                    "%s is taller than Play's documented 2:1 aspect limit; "
                    "the upload may be rejected",
                    f.name,
                )
            by_slug = groups.setdefault(m["res"], {})
            if m["slug"] in by_slug:
                raise RuntimeError(
                    f"two devices with size {m['res']} both captured "
                    f"{m['slug']} in {locale_dir} — can't pick one"
                )
            by_slug[m["slug"]] = f

        locale_plan = []
        for res, by_slug in sorted(groups.items()):
            if not slot_map[res]:  # E.g. the Android touch-TV captures.
                LOG.info(
                    "Skipping %s %s captures (no store slot)", platform, res
                )
                continue
            missing = [s for s in selection if s not in by_slug]
            if missing:
                raise RuntimeError(
                    f"{locale_dir} {res} is missing selected shots "
                    f"{missing} — regenerate with take_screenshots.py or "
                    "edit the selection list"
                )
            skipped = sorted(set(by_slug) - set(selection))
            if skipped:
                LOG.info(
                    "Not publishing %s %s (not in the selection list)",
                    res,
                    ", ".join(skipped),
                )
            locale_plan.append((res, [by_slug[s] for s in selection]))
        if locale_plan:
            out[locale_dir.name] = locale_plan
    if not out:
        raise RuntimeError(f"no screenshots found under {root}")
    return out


def describe_plan(platform, plan):
    slot_map = IOS_DISPLAY_TYPES if platform == "ios" else ANDROID_IMAGE_TYPES
    for locale, groups in plan.items():
        for res, files in groups:
            slots = slot_map[res]
            slots = [slots] if isinstance(slots, str) else slots
            for slot in slots:
                LOG.info(
                    "%s %s: %s <- %d shots (%s)",
                    platform,
                    locale,
                    slot,
                    len(files),
                    ", ".join(FILENAME_RE.match(f.name)["slug"] for f in files),
                )


# --- App Store Connect ------------------------------------------------------


def load_ios_credentials():
    """The same credential scheme as ios/publish.sh: values come from
    ios/publish.env, real environment variables win, and the key ID is
    derived from the AuthKey_<ID>.p8 filename when possible."""
    names = (
        "APP_STORE_CONNECT_API_ISSUER_ID",
        "API_KEY_PATH",
        "APP_STORE_CONNECT_API_KEY_ID",
    )
    sourced = {}
    if IOS_PUBLISH_ENV.exists():
        fmt = "\\0".join(["%s"] * len(names))
        refs = " ".join(f'"${n}"' for n in names)
        res = subprocess.run(
            ["bash", "-c", f'. "{IOS_PUBLISH_ENV}" >/dev/null 2>&1; printf "{fmt}" {refs}'],
            capture_output=True,
            text=True,
        )
        if res.returncode == 0 and res.stdout.count("\0") == len(names) - 1:
            sourced = dict(zip(names, res.stdout.split("\0")))

    def get(name):
        return os.environ.get(name) or sourced.get(name) or ""

    issuer, key_path, key_id = (get(n) for n in names)
    if not issuer or not key_path:
        raise RuntimeError(
            "App Store Connect credentials missing: set "
            "APP_STORE_CONNECT_API_ISSUER_ID and API_KEY_PATH in "
            "ios/publish.env (see README -> Deploying to iOS)"
        )
    key_path = Path(key_path).expanduser()
    if not key_path.is_file():
        raise RuntimeError(f"API key not found at {key_path}")
    m = re.fullmatch(r"AuthKey_(.+)\.p8", key_path.name)
    if m:
        key_id = m.group(1)
    if not key_id:
        raise RuntimeError(
            "Set APP_STORE_CONNECT_API_KEY_ID or name the key AuthKey_<ID>.p8"
        )
    return issuer, key_id, key_path


class AppStoreClient:
    def __init__(self, issuer_id, key_id, key_path):
        self.issuer_id = issuer_id
        self.key_id = key_id
        self.key_path = key_path
        self._token = None
        self._token_born = 0.0

    def token(self):
        # Apple rejects JWTs older than 20 minutes; re-mint after 15 so a
        # long upload run never trips over an expiring token.
        if self._token is None or time.monotonic() - self._token_born > 15 * 60:
            now = int(time.time())
            self._token = make_jwt(
                {"alg": "ES256", "kid": self.key_id, "typ": "JWT"},
                {
                    "iss": self.issuer_id,
                    "iat": now,
                    "exp": now + 1200,
                    "aud": "appstoreconnect-v1",
                },
                lambda msg: _der_to_raw_ecdsa(_openssl_sign(self.key_path, msg)),
            )
            self._token_born = time.monotonic()
        return self._token

    def request(self, method, path, body=None):
        url = path if path.startswith("http") else ASC_API + path
        headers = {"Authorization": f"Bearer {self.token()}"}
        data = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(body).encode()
        raw = http(method, url, headers=headers, body=data)
        return json.loads(raw) if raw else None

    def get_all(self, path):
        """GET a collection, following pagination."""
        items = []
        resp = self.request("GET", path)
        while True:
            items.extend(resp["data"])
            next_url = (resp.get("links") or {}).get("next")
            if not next_url:
                return items
            resp = self.request("GET", next_url)


def find_editable_version(client):
    apps = client.request(
        "GET", f"/v1/apps?filter[bundleId]={urllib.parse.quote(IOS_BUNDLE_ID)}"
    )["data"]
    if not apps:
        raise RuntimeError(f"no App Store app with bundle id {IOS_BUNDLE_ID}")
    versions = client.get_all(
        f"/v1/apps/{apps[0]['id']}/appStoreVersions?filter[platform]=IOS&limit=50"
    )

    def state(v):
        attrs = v["attributes"]
        return attrs.get("appVersionState") or attrs.get("appStoreState")

    editable = [v for v in versions if state(v) in ASC_EDITABLE_STATES]
    if not editable:
        raise RuntimeError(
            "no editable App Store version found (screenshots attach to a "
            "version in e.g. Prepare for Submission) — create the new "
            "version in App Store Connect first"
        )
    version = editable[0]
    LOG.info(
        "Uploading to App Store version %s (%s)",
        version["attributes"]["versionString"],
        state(version),
    )
    return version


def upload_one_ios(client, set_id, path):
    """Reserve, upload, and commit a single screenshot; returns its id.
    Apple's flow: POST a reservation to get pre-signed upload operations,
    PUT the byte ranges they describe, then PATCH to commit with an MD5."""
    data = path.read_bytes()
    LOG.info("  Uploading %s (%d KB)", path.name, len(data) // 1024)
    shot = client.request(
        "POST",
        "/v1/appScreenshots",
        {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileName": path.name, "fileSize": len(data)},
                "relationships": {
                    "appScreenshotSet": {
                        "data": {"type": "appScreenshotSets", "id": set_id}
                    }
                },
            }
        },
    )["data"]
    for op in shot["attributes"]["uploadOperations"]:
        # Pre-signed URLs: send exactly the headers Apple specifies and no
        # Authorization header.
        http(
            op["method"],
            op["url"],
            headers={h["name"]: h["value"] for h in op.get("requestHeaders") or []},
            body=data[op["offset"]:op["offset"] + op["length"]],
        )
    client.request(
        "PATCH",
        f"/v1/appScreenshots/{shot['id']}",
        {
            "data": {
                "type": "appScreenshots",
                "id": shot["id"],
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": hashlib.md5(data).hexdigest(),
                },
            }
        },
    )
    return shot["id"]


def verify_ios_processing(client, set_labels, timeout=600):
    """App Store Connect processes screenshots asynchronously after the
    commit PATCH, and one that fails processing silently never shows up on
    the listing — so block until every screenshot in every touched set
    reaches a terminal state and fail loudly otherwise."""
    LOG.info("Waiting for App Store Connect to process the screenshots...")
    pending = dict(set_labels)
    failures = []
    deadline = time.monotonic() + timeout
    while pending and time.monotonic() < deadline:
        for set_id, label in list(pending.items()):
            shots = client.get_all(
                f"/v1/appScreenshotSets/{set_id}/appScreenshots?limit=50"
            )
            states = {
                s["attributes"]["fileName"]: (
                    s["attributes"].get("assetDeliveryState") or {}
                )
                for s in shots
            }
            if any(
                st.get("state") not in ("COMPLETE", "FAILED")
                for st in states.values()
            ):
                continue
            for name, st in states.items():
                if st.get("state") == "FAILED":
                    failures.append(f"{label} {name}: {st.get('errors')}")
            LOG.info("  %s: %d processed", label, len(states))
            del pending[set_id]
        if pending:
            time.sleep(5)
    if pending:
        raise RuntimeError(
            f"timed out waiting for processing of: {sorted(pending.values())}"
        )
    if failures:
        raise RuntimeError(
            "App Store Connect rejected some screenshots:\n  "
            + "\n  ".join(failures)
        )


def upload_ios(plan):
    client = AppStoreClient(*load_ios_credentials())
    version = find_editable_version(client)
    locs = client.get_all(
        f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations?limit=50"
    )
    locs_by_locale = {l["attributes"]["locale"]: l for l in locs}

    touched_sets = {}
    for locale, groups in plan.items():
        loc = locs_by_locale.get(locale)
        if loc is None:
            raise RuntimeError(
                f"the App Store listing has no {locale} localization (has: "
                f"{sorted(locs_by_locale)}) — add it in App Store Connect"
            )
        sets = client.get_all(
            f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets?limit=50"
        )
        sets_by_type = {
            s["attributes"]["screenshotDisplayType"]: s for s in sets
        }
        for res, files in groups:
            display_type = IOS_DISPLAY_TYPES[res]
            label = f"{locale}/{display_type}"
            LOG.info("Replacing screenshot set %s", label)
            sset = sets_by_type.get(display_type)
            if sset is None:
                sset = client.request(
                    "POST",
                    "/v1/appScreenshotSets",
                    {
                        "data": {
                            "type": "appScreenshotSets",
                            "attributes": {
                                "screenshotDisplayType": display_type
                            },
                            "relationships": {
                                "appStoreVersionLocalization": {
                                    "data": {
                                        "type": "appStoreVersionLocalizations",
                                        "id": loc["id"],
                                    }
                                }
                            },
                        }
                    },
                )["data"]
            # Out with the old: the 10-per-set cap means the new shots
            # can't coexist with the old ones, so this mirrors what
            # fastlane's deliver did (delete, upload, reorder). If a run
            # dies between here and the re-upload, just run it again.
            for old in client.get_all(
                f"/v1/appScreenshotSets/{sset['id']}/appScreenshots?limit=50"
            ):
                client.request("DELETE", f"/v1/appScreenshots/{old['id']}")
            new_ids = [
                upload_one_ios(client, sset["id"], path) for path in files
            ]
            # Apple doesn't promise display order follows creation order,
            # so set it explicitly.
            client.request(
                "PATCH",
                f"/v1/appScreenshotSets/{sset['id']}/relationships/appScreenshots",
                {
                    "data": [
                        {"type": "appScreenshots", "id": i} for i in new_ids
                    ]
                },
            )
            touched_sets[sset["id"]] = label
    verify_ios_processing(client, touched_sets)
    LOG.info("App Store: done.")


# --- Google Play ------------------------------------------------------------


def play_access_token():
    """OAuth2 service-account JWT bearer flow, no client libraries."""
    if not PLAY_KEY_PATH.is_file():
        raise RuntimeError(
            f"Play service account key not found at {PLAY_KEY_PATH}. Drop a "
            "JSON key for the CI publishing service account there, or set "
            "PLAY_SERVICE_ACCOUNT_JSON_PATH (see README -> Screenshots)."
        )
    info = json.loads(PLAY_KEY_PATH.read_text())
    now = int(time.time())
    with tempfile.NamedTemporaryFile("w", suffix=".pem") as f:
        f.write(info["private_key"])
        f.flush()
        assertion = make_jwt(
            {"alg": "RS256", "typ": "JWT"},
            {
                "iss": info["client_email"],
                "scope": PLAY_SCOPE,
                "aud": PLAY_TOKEN_URL,
                "iat": now,
                "exp": now + 3600,
            },
            lambda msg: _openssl_sign(f.name, msg),
        )
    resp = json.loads(
        http(
            "POST",
            PLAY_TOKEN_URL,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            body=urllib.parse.urlencode(
                {
                    "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                    "assertion": assertion,
                }
            ).encode(),
        )
    )
    return resp["access_token"]


def upload_android(plan):
    token = play_access_token()
    auth = {"Authorization": f"Bearer {token}"}

    def api(method, path, *, upload_body=None):
        base = PLAY_UPLOAD_API if upload_body is not None else PLAY_API
        headers = dict(auth)
        if upload_body is not None:
            headers["Content-Type"] = "image/png"
        raw = http(
            method,
            f"{base}/applications/{ANDROID_PACKAGE_NAME}{path}",
            headers=headers,
            body=upload_body,
        )
        return json.loads(raw) if raw else None

    # Everything below happens inside this edit; the store only changes at
    # the commit at the very end.
    edit_id = api("POST", "/edits")["id"]
    LOG.info("Opened Play edit %s", edit_id)
    listings = api("GET", f"/edits/{edit_id}/listings").get("listings") or []
    languages = {l["language"] for l in listings}
    for locale, groups in plan.items():
        if locale not in languages:
            raise RuntimeError(
                f"the Play listing has no {locale} language (has: "
                f"{sorted(languages)}) — add it in the Play Console. (The "
                "images API silently no-ops on unknown languages, so this "
                "is checked up front.)"
            )
        for res, files in groups:
            for image_type in ANDROID_IMAGE_TYPES[res]:
                slot_path = f"/edits/{edit_id}/listings/{locale}/{image_type}"
                LOG.info("Replacing Play slot %s/%s", locale, image_type)
                deleted = api("DELETE", slot_path) or {}
                LOG.info(
                    "  Cleared %d existing", len(deleted.get("deleted") or [])
                )
                for path in files:
                    LOG.info(
                        "  Uploading %s (%d KB)",
                        path.name,
                        path.stat().st_size // 1024,
                    )
                    api(
                        "POST",
                        f"{slot_path}?uploadType=media",
                        upload_body=path.read_bytes(),
                    )
                now_there = api("GET", slot_path).get("images") or []
                if len(now_there) != len(files):
                    raise RuntimeError(
                        f"{image_type} holds {len(now_there)} images after "
                        f"uploading {len(files)} — aborting before commit"
                    )
    api("POST", f"/edits/{edit_id}:commit")
    LOG.info("Play edit committed. Google Play: done.")


# --- Main -------------------------------------------------------------------


def main():
    args = parse_args()
    logging.basicConfig(
        level=logging.DEBUG if args.debug else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )

    ios_plan = None if args.android_only else discover("ios")
    android_plan = None if args.ios_only else discover("android")
    if ios_plan:
        describe_plan("ios", ios_plan)
    if android_plan:
        describe_plan("android", android_plan)
    if args.dry_run:
        LOG.info("Dry run: nothing uploaded.")
        return

    if ios_plan:
        upload_ios(ios_plan)
    if android_plan:
        upload_android(android_plan)
    LOG.info("Done!")


if __name__ == "__main__":
    main()
