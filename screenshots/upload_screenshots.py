#!/usr/bin/env python3
"""Upload the captured store screenshots. Thin wrapper: the implementation
lives in dictionarylib/scripts/upload_screenshots_lib.py (sibling checkout,
or set DICTIONARYLIB_DIR); this supplies Auslan's app-specific values. Same
CLI as before: --ios-only / --android-only / --dry-run / -d."""

import os
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DICTIONARYLIB = Path(
    os.environ.get("DICTIONARYLIB_DIR") or PROJECT_ROOT.parent / "dictionarylib"
)
if not (DICTIONARYLIB / "scripts" / "upload_screenshots_lib.py").exists():
    sys.exit(
        f"error: dictionarylib checkout not found at {DICTIONARYLIB}. Clone "
        "https://github.com/banool/dictionarylib next to this repo, or set "
        "DICTIONARYLIB_DIR."
    )
sys.path.insert(0, str(DICTIONARYLIB / "scripts"))

import upload_screenshots_lib as lib  # noqa: E402

lib.configure(
    project_root=PROJECT_ROOT,
    ios_bundle_id="com.banool.auslanDictionary",
    android_package_name="com.banool.auslan_dictionary",
    # Captures are taken under en-AU, but the Play listing has only ever had
    # an en-US language entry. App Store Connect's listing really is en-AU.
    play_locale_map={"en-AU": "en-US"},
    ios_locale_map={},
    android_image_types={
        "1080x2400": ["phoneScreenshots"],
        "2560x1600": ["sevenInchScreenshots", "tenInchScreenshots"],
        # Touch TV: no Play slot (tvScreenshots is for Android TV releases,
        # which this app doesn't ship) — stays local-only.
        "1920x1080": [],
    },
)

if __name__ == "__main__":
    lib.main()
