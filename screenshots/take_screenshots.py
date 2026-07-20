#!/usr/bin/env python3
"""Generate the store screenshots. Thin wrapper: the implementation lives in
appci/scripts/take_screenshots_lib.py (sibling checkout, or set
APPCI_DIR); this supplies Auslan's app-specific values. Same CLI as
before: --ios-only / --android-only / --clear-screenshots / -d."""

import json
import logging
import os
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
APPCI = Path(
    os.environ.get("APPCI_DIR") or PROJECT_ROOT.parent / "appci"
)
if not (APPCI / "scripts" / "take_screenshots_lib.py").exists():
    sys.exit(
        f"error: appci checkout not found at {APPCI}. Clone "
        "https://github.com/banool/appci next to this repo, or set "
        "APPCI_DIR."
    )
sys.path.insert(0, str(APPCI / "scripts"))

import take_screenshots_lib as lib  # noqa: E402

# Must match the words the shared screenshot suite seeds into the Animals
# list for this app (integration_test/test_config.dart), so every
# video-bearing capture has a poster.
SEEDED_WORDS = ["kangaroo", "platypus", "echidna", "dog", "cat", "bird"]


def poster_video_urls():
    """Video URLs for the seeded words, from the bundled legacy data file
    (which stores full URLs — see entries_loader.dart)."""
    data = json.loads(
        (PROJECT_ROOT / "assets" / "data" / "data.json").read_text())
    urls = []
    for entry in data["data"]:
        if entry.get("entry_in_english") not in SEEDED_WORDS:
            continue
        for sub in entry.get("sub_entries") or []:
            urls.extend(sub.get("video_links") or [])
    return urls


# AD_tv approximates the school touch TVs the app runs on: a landscape-natural
# 1080p panel at mdpi, i.e. a 1920x1080dp logical display, far larger than any
# tablet. avdmanager has no TV-sized touch profile, so it's created from the
# tablet profile and resized via config.ini (patch_tv_avd below).
TV_AVD_NAME = "AD_tv"
TV_LCD_CONFIG = {
    "hw.lcd.width": "1920",
    "hw.lcd.height": "1080",
    "hw.lcd.density": "160",
}


def patch_tv_avd():
    """Resize the AD_tv AVD to TV dimensions by rewriting its config.ini
    LCD keys (avdmanager can only create from fixed device profiles)."""
    cfg = Path.home() / ".android" / "avd" / f"{TV_AVD_NAME}.avd" / "config.ini"
    if not cfg.exists():
        logging.getLogger("screenshots").warning(
            "AD_tv config.ini not found at %s; skipping TV resize", cfg)
        return
    lines = cfg.read_text().splitlines()
    keys_seen = set()
    out = []
    for line in lines:
        key = line.split("=")[0].strip()
        if key in TV_LCD_CONFIG:
            out.append(f"{key}={TV_LCD_CONFIG[key]}")
            keys_seen.add(key)
        else:
            out.append(line)
    for key, value in TV_LCD_CONFIG.items():
        if key not in keys_seen:
            out.append(f"{key}={value}")
    cfg.write_text("\n".join(out) + "\n")
    logging.getLogger("screenshots").info(
        "Patched %s to %sx%s @ %sdpi", TV_AVD_NAME,
        TV_LCD_CONFIG["hw.lcd.width"], TV_LCD_CONFIG["hw.lcd.height"],
        TV_LCD_CONFIG["hw.lcd.density"])


lib.configure(
    project_root=PROJECT_ROOT,
    locale_dir="en-AU",
    ios_targets=[
        ("iPhone 17 Pro Max",
         "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"),         # 6.9" (required)
        ("iPhone 17",
         "com.apple.CoreSimulator.SimDeviceType.iPhone-17"),                 # 6.3" (standard)
        ("iPad Pro 13-inch (M5)",
         "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB"),  # 13" (required for iPad)
    ],
    android_targets=[
        ("AD_phone", "pixel_7"),        # phone (required)
        ("AD_tablet", "pixel_tablet"),  # ~11" tablet (covers the 10" slot)
        ("AD_tv", "pixel_tablet"),      # touch TV (schools)
    ],
    poster_video_urls=poster_video_urls,
    post_create_avds=patch_tv_avd,
)

if __name__ == "__main__":
    lib.main()
