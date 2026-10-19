#!/usr/bin/env -S uv run --script
# Empty dependency list on purpose — see take_screenshots.py. Stdlib only; the
# block is here to pin the interpreter, not to install anything.
# /// script
# requires-python = ">=3.14"
# dependencies = []
# ///
"""Upload the captured store screenshots. Thin wrapper: the implementation
lives in appci/scripts/upload_screenshots_lib.py (sibling checkout,
or set APPCI_DIR); this supplies Auslan's app-specific values. Same
CLI as before: --ios-only / --android-only / --dry-run / -d."""

import os
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
APPCI = Path(
    os.environ.get("APPCI_DIR") or PROJECT_ROOT.parent / "appci"
)
if not (APPCI / "scripts" / "upload_screenshots_lib.py").exists():
    sys.exit(
        f"error: appci checkout not found at {APPCI}. Clone "
        "https://github.com/banool/appci next to this repo, or set "
        "APPCI_DIR."
    )
sys.path.insert(0, str(APPCI / "scripts"))

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
        # The touch-TV captures fill Play's Android TV slot.
        "1920x1080": ["tvScreenshots"],
    },
    # The marketable subset of the captured slugs, in storefront order (the
    # stores cap listings at 10 / 8 images).
    # The marketable subset of the captured slugs, in storefront order (the
    # stores cap listings at 10 / 8 images). The word page leads: a signer's
    # video says what the app is at a glance, where the empty search screen
    # didn't.
    app_store_shots=[
        "03-wordPage",
        "02-searchResults",
        "09-flashcardRevealed",
        "07-revisionLanding",
        "04-saveToList",
        "05-lists",
        "06-insideList",
        "01-search",
        "08-flashcardFront",
        "11-searchDark",
    ],
    play_shots=[
        "03-wordPage",
        "02-searchResults",
        "09-flashcardRevealed",
        "07-revisionLanding",
        "04-saveToList",
        "05-lists",
        "06-insideList",
        "01-search",
    ],
    # The 5.5"/4.7" iPhone and older iPad sets still held pre-Hearth captures
    # from the fastlane days; drop them so older devices get the current
    # 6.9"/13" shots scaled down.
    prune_unmanaged_ios_sets=True,
)

if __name__ == "__main__":
    lib.main()
