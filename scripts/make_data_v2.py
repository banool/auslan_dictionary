#!/usr/bin/env python3

"""
Produce assets/data/data-v2.json from assets/data/data.json by stripping the
media base off every video_link, leaving just the path (e.g.
/mp4video/11/11450.mp4).

Current app builds read data-v2.json and re-prepend AUSLAN_MEDIA_BASE_URL (see
lib/main.dart), so the same path resolves wherever the media is hosted. Old app
builds keep reading the full-URL data.json. Raises if any video_link isn't
under the expected base — see common.strip_media_base.
"""

import json
from pathlib import Path

from common import LOG, strip_media_base

DATA_DIR = Path(__file__).resolve().parent.parent / "assets" / "data"
SRC = DATA_DIR / "data.json"
DST = DATA_DIR / "data-v2.json"


def main():
    LOG.setLevel("INFO")
    with open(SRC) as f:
        data = json.load(f)

    n = 0
    for entry in data["data"]:
        for sub_entry in entry.get("sub_entries", []):
            sub_entry["video_links"] = [
                strip_media_base(url) for url in sub_entry.get("video_links", [])
            ]
            n += len(sub_entry["video_links"])

    with open(DST, "w") as f:
        json.dump(data, f, indent=2)

    LOG.info(f"Wrote {DST} ({n} media paths from {SRC.name})")


if __name__ == "__main__":
    main()
