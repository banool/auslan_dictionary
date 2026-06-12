"""
Generate App Store / Play Store screenshots by driving the app's
integration_test screenshot target across the device formats each store
requires.

The simulators and emulators this needs are CREATED ON DEMAND (and reused on
later runs), so you don't have to set any up by hand first — see IOS_TARGETS and
ANDROID_TARGETS below. Captures land in screenshots/<platform>/en-AU/.

Run from anywhere:
    python3 screenshots/take_screenshots.py                 # both platforms
    python3 screenshots/take_screenshots.py --ios-only
    python3 screenshots/take_screenshots.py --android-only
    python3 screenshots/take_screenshots.py --clear-screenshots

Prerequisites: Xcode (iOS) and the Android SDK command-line tools + emulator
(found via ANDROID_HOME / ANDROID_SDK_ROOT, else ~/Library/Android/sdk). The
first Android run downloads a system image (~1 GB).

This whole script is a bit janky; sometimes all you need is some strategic
retries (and the odd `flutter clean`) and what was previously not working will
magically start to work.
"""

import argparse
import json
import logging
import os
import re
import shutil
import subprocess
import time
import urllib.request
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SCREENSHOTS_DIR = PROJECT_ROOT / "screenshots"

# First-frame posters for the videos the screenshot flow can display.
# Android emulators cannot render mpv video at all (mpv's GL context
# creation fails in the emulator's EGL), so the app is pointed at these
# stills instead via SCREENSHOT_POSTERS_URL — the captures then contain a
# real frame of the real video rather than a black pane. Served to the
# emulator over host loopback (10.0.2.2) by a throwaway local HTTP server.
POSTERS_DIR = SCREENSHOTS_DIR / ".posters"
POSTERS_PORT = 8123
# Must match the words screenshot_test.dart seeds into the Animals list
# (any of their videos can appear on the flashcard screens).
SEEDED_WORDS = ["kangaroo", "platypus", "echidna", "dog", "cat", "bird"]

DRIVER = "test_driver/integration_driver.dart"
TARGET = "integration_test/screenshot_test.dart"

# --- Target devices: one per screenshot format the stores require. ---

# App Store Connect requires a 6.9" iPhone and (for iPad apps) a 13" iPad, and
# scales those down for every smaller device; the 6.3" iPhone is an optional
# standard-size extra. Each entry is (simulator name — which shows up in the
# screenshot path — and the `xcrun simctl list devicetypes` identifier to
# create it from). The newest installed iOS runtime is used automatically.
IOS_TARGETS = [
    ("iPhone 17 Pro Max",
     "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"),         # 6.9" (required)
    ("iPhone 17",
     "com.apple.CoreSimulator.SimDeviceType.iPhone-17"),                 # 6.3" (standard)
    ("iPad Pro 13-inch (M5)",
     "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB"),  # 13" (required for iPad)
]

# Google Play requires phone screenshots and, for tablet support, 7"/10" tablet
# screenshots. Each entry is (AVD name, `avdmanager list device` profile id).
# AD_tv approximates the school touch TVs the app runs on: a landscape-natural
# 1080p panel at mdpi, i.e. a 1920x1080dp logical display, far larger than any
# tablet. avdmanager has no TV-sized touch profile, so it's created from the
# tablet profile and resized via config.ini (see _patch_tv_avd).
ANDROID_TARGETS = [
    ("AD_phone", "pixel_7"),        # phone (required)
    ("AD_tablet", "pixel_tablet"),  # ~11" tablet (covers the 10" slot)
    ("AD_tv", "pixel_tablet"),      # touch TV (schools)
]

TV_AVD_NAME = "AD_tv"
TV_LCD_CONFIG = {
    "hw.lcd.width": "1920",
    "hw.lcd.height": "1080",
    "hw.lcd.density": "160",
}
# System image every AVD is created from. arm64-v8a for Apple Silicon hosts;
# API 35 = Android 15.
ANDROID_SYSTEM_IMAGE = "system-images;android-35;google_apis;arm64-v8a"

LOG = logging.getLogger("screenshots")


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("-d", "--debug", action="store_true")
    parser.add_argument(
        "--clear-screenshots",
        action="store_true",
        help="Delete all existing local screenshots first",
    )
    parser.add_argument(
        "--ios-only", action="store_true", help="Only take screenshots for iOS"
    )
    parser.add_argument(
        "--android-only",
        action="store_true",
        help="Only take screenshots for Android",
    )
    return parser.parse_args()


def run(cmd, *, cwd=None, check=True, capture=False, stdin=None):
    """Run a subprocess. Returns the CompletedProcess; raises on failure when
    check is set."""
    cmd = [str(c) for c in cmd]
    LOG.debug("$ %s", " ".join(cmd))
    res = subprocess.run(
        cmd,
        cwd=cwd,
        text=True,
        input=stdin,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )
    if check and res.returncode != 0:
        raise RuntimeError(
            f"command failed ({res.returncode}): {' '.join(cmd)}\n"
            f"{res.stderr or ''}"
        )
    return res


def drive(device_id):
    """Run the screenshot integration test on one device via flutter_driver,
    then verify the captures actually landed. The drive's exit code is
    deliberately ignored (it sometimes crashes at the very end after every
    screenshot has been written); completeness is checked instead via the
    SCREENSHOTS_COMPLETE marker the test prints — a drive that dies partway
    (or whose files never reach disk) fails loudly rather than leaving a
    silently-partial set."""
    LOG.info("Capturing screenshots on %s", device_id)
    cmd = ["flutter", "drive", f"--driver={DRIVER}", f"--target={TARGET}",
           "-d", device_id]
    if device_id.startswith("emulator-"):
        # Android emulators cannot render mpv video (GL context creation
        # fails), so point the app at first-frame posters served from the
        # host — see POSTERS_DIR above. Real builds never set the define.
        cmd.append(
            f"--dart-define=SCREENSHOT_POSTERS_URL=http://10.0.2.2:{POSTERS_PORT}")
    res = run(
        cmd,
        cwd=PROJECT_ROOT,
        check=False,
        capture=True,
    )
    output = (res.stdout or "") + (res.stderr or "")
    LOG.debug("drive output for %s:\n%s", device_id, output)
    # The prefix runs to the end of the line, NOT \S+: iOS simulator names
    # (and so the prefix) contain spaces, e.g. "ios/en-AU/iPhone 17-...".
    m = re.search(r"SCREENSHOTS_COMPLETE count=(\d+) prefix=(.+)", output)
    if not m:
        raise RuntimeError(
            f"drive on {device_id} never reached the completion marker — it "
            f"died partway through the captures. Full output:\n{output}"
        )
    expected, prefix = int(m.group(1)), m.group(2).strip()
    actual = sorted(SCREENSHOTS_DIR.glob(f"{prefix}-*.png"))
    if len(actual) != expected:
        names = "\n".join(f"  {p.relative_to(SCREENSHOTS_DIR)}" for p in actual)
        raise RuntimeError(
            f"drive on {device_id} reported {expected} screenshots but "
            f"{len(actual)} matching {prefix}-*.png are on disk:\n{names}\n"
            "(more than expected usually means stale files from a previous "
            "run — re-run with --clear-screenshots)"
        )
    strip_alpha(actual)
    LOG.info("Verified %d screenshots for %s", expected, prefix)


def strip_alpha(paths):
    """Flatten captures to 24-bit RGB in place. Flutter's takeScreenshot
    writes RGBA PNGs, but App Store Connect rejects screenshots that have an
    alpha channel (IMAGE_ALPHA_NOT_ALLOWED) and Google Play wants "24-bit
    PNG (no alpha)" too."""
    ffmpeg = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
    for png in paths:
        tmp = png.with_suffix(".rgb24.png")
        run([ffmpeg, "-y", "-loglevel", "error", "-i", png,
             "-pix_fmt", "rgb24", tmp])
        tmp.replace(png)


# --- Video posters (Android emulators only) --------------------------------


def poster_name(url):
    """Poster filename for a video URL: its last two path segments joined
    with '_'. Must match _posterUrlFor in dictionarylib's
    video_player_screen.dart."""
    segments = url.rstrip("/").split("/")
    return f"{segments[-2]}_{segments[-1]}" if len(segments) >= 2 else segments[-1]


def ensure_posters():
    """Download each seeded word's videos and extract a first-frame PNG.
    Both steps are cached in POSTERS_DIR, so reruns are instant (delete the
    cached *.png after changing extraction settings). The sources are tiny
    (320-640px wide) while the panes they fill reach ~2400px, so frames are
    upscaled here with Lanczos — far cleaner than leaving the whole stretch
    to the renderer's bilinear filter."""
    data = json.loads(
        (PROJECT_ROOT / "assets" / "data" / "data.json").read_text())
    urls = []
    for entry in data["data"]:
        if entry.get("entry_in_english") not in SEEDED_WORDS:
            continue
        for sub in entry.get("sub_entries") or []:
            urls.extend(sub.get("video_links") or [])
    POSTERS_DIR.mkdir(exist_ok=True)
    ffmpeg = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
    for url in urls:
        name = poster_name(url)
        png = POSTERS_DIR / f"{name}.png"
        if png.exists():
            continue
        mp4 = POSTERS_DIR / name
        if not mp4.exists():
            LOG.info("Downloading %s", url)
            urllib.request.urlretrieve(url, mp4)
        run([ffmpeg, "-y", "-loglevel", "error", "-i", mp4,
             "-frames:v", "1", "-vf", "scale=1280:-2:flags=lanczos", png])
    count = len(list(POSTERS_DIR.glob("*.png")))
    LOG.info("Posters ready: %d frames in %s", count, POSTERS_DIR)


def serve_posters():
    """Serve POSTERS_DIR on 0.0.0.0:POSTERS_PORT so emulators can reach it
    at http://10.0.2.2:POSTERS_PORT. Returns the server process; caller
    terminates it."""
    import sys
    return subprocess.Popen(
        [sys.executable, "-m", "http.server", str(POSTERS_PORT),
         "--bind", "0.0.0.0", "--directory", str(POSTERS_DIR)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


# --- iOS ------------------------------------------------------------------


def ios_simulators_by_name():
    out = run(["xcrun", "simctl", "list", "devices"], capture=True).stdout
    devices = {}
    for line in out.splitlines():
        # Anchor to end-of-line so "(unavailable, runtime profile not found)"
        # sims (left over from older runtimes) are skipped, not reused.
        m = re.match(
            r"\s+(.+?) \(([0-9A-Fa-f-]{36})\) \((?:Booted|Shutdown)\)\s*$", line
        )
        if m:
            devices.setdefault(m.group(1).strip(), m.group(2))
    return devices


def ensure_ios_simulators():
    """Create any missing target simulators; reuse those that already exist.
    Returns name -> udid."""
    existing = ios_simulators_by_name()
    out = {}
    for name, devtype in IOS_TARGETS:
        if name in existing:
            LOG.info("Reusing simulator: %s", name)
            out[name] = existing[name]
        else:
            LOG.info("Creating simulator: %s", name)
            udid = run(
                ["xcrun", "simctl", "create", name, devtype], capture=True
            ).stdout.strip()
            out[name] = udid
    return out


def boot_ios(udid):
    # Boot if needed and block until the simulator has finished booting.
    run(["xcrun", "simctl", "bootstatus", udid, "-b"], check=False)


# --- Android --------------------------------------------------------------


def android_sdk():
    for var in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        p = os.environ.get(var)
        if p:
            return Path(p)
    return Path.home() / "Library" / "Android" / "sdk"


def android_tool(*parts):
    return android_sdk().joinpath(*parts)


def ensure_android_avds():
    """Install the system image (no-op once present) and create any missing
    target AVDs."""
    sdkmanager = android_tool("cmdline-tools", "latest", "bin", "sdkmanager")
    avdmanager = android_tool("cmdline-tools", "latest", "bin", "avdmanager")
    if not avdmanager.exists():
        raise RuntimeError(
            f"Android cmdline-tools not found under {android_sdk()}. Install "
            "them via Android Studio > SDK Manager (or set ANDROID_HOME)."
        )
    LOG.info("Ensuring system image %s (downloads on first run)", ANDROID_SYSTEM_IMAGE)
    # Pipe a stream of "y" to accept the licence prompt non-interactively.
    run([sdkmanager, ANDROID_SYSTEM_IMAGE], stdin="y\n" * 50, check=False)

    existing = run([avdmanager, "list", "avd", "-c"], capture=True).stdout.split()
    for name, device in ANDROID_TARGETS:
        if name in existing:
            LOG.info("Reusing AVD: %s", name)
            continue
        LOG.info("Creating AVD: %s (%s)", name, device)
        # Answer "no" to the "custom hardware profile?" prompt.
        run(
            [avdmanager, "create", "avd", "-n", name, "-k", ANDROID_SYSTEM_IMAGE,
             "-d", device, "--force"],
            stdin="no\n",
        )
    # Idempotent: re-applied every run so a hand-edited or stale AD_tv
    # config converges back to the TV dimensions.
    _patch_tv_avd()


def _patch_tv_avd():
    """Resize the AD_tv AVD to TV dimensions by rewriting its config.ini
    LCD keys (avdmanager can only create from fixed device profiles)."""
    cfg = Path.home() / ".android" / "avd" / f"{TV_AVD_NAME}.avd" / "config.ini"
    if not cfg.exists():
        LOG.warning("AD_tv config.ini not found at %s; skipping TV resize", cfg)
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
    LOG.info("Patched %s to %sx%s @ %sdpi", TV_AVD_NAME,
             TV_LCD_CONFIG["hw.lcd.width"], TV_LCD_CONFIG["hw.lcd.height"],
             TV_LCD_CONFIG["hw.lcd.density"])


def boot_android(name, port):
    """Launch an AVD on a fixed console port and wait for it to finish
    booting. Returns its adb serial.

    The port is pinned so the serial is deterministic (emulator-<port>) and
    every adb call can use `-s` — the previous bare `adb get-serialno` /
    `adb shell` calls broke with "more than one device/emulator" whenever any
    other emulator or device happened to be connected."""
    emulator = android_tool("emulator", "emulator")
    adb = android_tool("platform-tools", "adb")
    serial = f"emulator-{port}"
    LOG.info("Booting emulator: %s (%s)", name, serial)
    subprocess.Popen(
        [str(emulator), "-avd", name, "-port", str(port), "-no-boot-anim",
         "-no-snapshot"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    run([adb, "-s", serial, "wait-for-device"])
    for _ in range(150):
        done = run(
            [adb, "-s", serial, "shell", "getprop", "sys.boot_completed"],
            capture=True,
            check=False,
        ).stdout.strip()
        if done == "1":
            time.sleep(2)
            return serial
        time.sleep(2)
    raise RuntimeError(f"emulator {name} did not finish booting")


def kill_android(serial):
    adb = android_tool("platform-tools", "adb")
    run([adb, "-s", serial, "emu", "kill"], check=False)


# --- Main -----------------------------------------------------------------


def main():
    args = parse_args()
    logging.basicConfig(
        level=logging.DEBUG if args.debug else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )

    if args.clear_screenshots:
        for platform in ("ios", "android"):
            leaf = SCREENSHOTS_DIR / platform / "en-AU"
            if leaf.exists():
                shutil.rmtree(leaf)
            leaf.mkdir(parents=True, exist_ok=True)
        LOG.info("Cleared existing screenshots")

    if not args.android_only:
        LOG.info("Preparing iOS simulators")
        sims = ensure_ios_simulators()
        # Boot, capture and shut down one at a time. Running several fresh
        # simulators at once thrashes the host (each spins up its own system
        # services) and slows every drive to a crawl.
        for name, udid in sims.items():
            LOG.info("Booting simulator: %s", name)
            boot_ios(udid)
            try:
                drive(udid)
            finally:
                run(["xcrun", "simctl", "shutdown", udid], check=False)

    if not args.ios_only:
        LOG.info("Preparing Android emulators")
        ensure_android_avds()
        ensure_posters()
        poster_server = serve_posters()
        try:
            # High even ports well away from the default 5554 so a
            # user-started emulator can't collide with ours.
            for i, (name, _) in enumerate(ANDROID_TARGETS):
                serial = boot_android(name, 5584 + i * 2)
                try:
                    drive(serial)
                finally:
                    kill_android(serial)
                    time.sleep(3)
        finally:
            poster_server.terminate()

    LOG.info("Done! Screenshots in %s", SCREENSHOTS_DIR)


if __name__ == "__main__":
    main()
