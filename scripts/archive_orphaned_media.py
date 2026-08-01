#!/usr/bin/env python3

"""
Find (and optionally archive) R2 mirror objects that the data no longer
references.

The auslan-mirror bucket is the app's fallback media host, populated by
sync_media_to_r2.py from data-v2.json. When filter_dead_media.py removes a
dead video from the data, or a sign's media path changes, the mirror can be
left holding objects nothing references. This lists those orphans, and with
--archive moves each from <key> to archive/<key> — out of the app's way (the
mirror serves keys matching data-v2.json paths) but still in the bucket, so a
mistaken archive is recoverable by moving the object back. Nothing is ever
hard-deleted.

Only keys under the media prefixes (mp4video/, auslan/) are ever candidates:
the bucket also holds the CI data mirror under data/ and previous archives
under archive/, and any key outside the known prefixes is reported but never
touched.

This is the Auslan analog of the SLSL admin site's find_unused_videos
management command. That one is Django/DB-backed and deliberately SLSL-only;
this one is driven by data-v2.json. They stay separate on purpose.

Credentials come from the environment, same as sync_media_to_r2.py
(R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY — see scripts'
secrets.env).

Usage:

    # Just list the orphans (read-only).
    uv run python archive_orphaned_media.py

    # List + move them to archive/.
    uv run python archive_orphaned_media.py --archive
"""

import argparse
import logging
import os
from pathlib import Path

from common import LOG
from sync_media_to_r2 import (
    DEFAULT_BUCKET,
    DEFAULT_DATA_FILE,
    collect_media_paths,
    list_existing_keys,
    make_s3_client,
    r2_key_for,
)

# Where archived orphans go: a sibling prefix the app never reads.
ARCHIVE_PREFIX = "archive/"

# The only prefixes this script will ever move objects out of. data-v2.json
# media paths span exactly these today; a new prefix showing up in the bucket
# is surfaced for a human rather than treated as archivable.
MEDIA_PREFIXES = ("mp4video/", "auslan/")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--data-file",
        type=Path,
        default=DEFAULT_DATA_FILE,
        help=f"Path to data-v2.json (default: {DEFAULT_DATA_FILE}).",
    )
    parser.add_argument(
        "--bucket",
        default=DEFAULT_BUCKET,
        help=f"R2 bucket name (default: {DEFAULT_BUCKET}).",
    )
    parser.add_argument(
        "--archive",
        action="store_true",
        help="Move each orphan to archive/<key> (server-side copy then delete). "
        "Without this flag the script only lists them.",
    )
    parser.add_argument("-d", "--debug", action="store_true")
    args = parser.parse_args()

    LOG.setLevel(logging.DEBUG if args.debug else logging.INFO)

    if not args.data_file.exists():
        parser.error(f"Data file not found: {args.data_file}")
    for var in ("R2_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY"):
        if not os.environ.get(var):
            parser.error(f"Missing required env var: {var}")

    referenced = {r2_key_for(path) for path in collect_media_paths(args.data_file)}
    LOG.info(f"{len(referenced)} media paths referenced by {args.data_file}")

    s3 = make_s3_client()
    LOG.info(f"Listing objects in {args.bucket}...")
    all_keys = list_existing_keys(s3, args.bucket)

    candidates = {key for key in all_keys if key.startswith(MEDIA_PREFIXES)}
    ignored = all_keys - candidates
    already_archived = sum(1 for key in ignored if key.startswith(ARCHIVE_PREFIX))
    other_ignored = sorted(
        key
        for key in ignored
        if not key.startswith(ARCHIVE_PREFIX) and not key.startswith("data/")
    )
    LOG.info(
        f"{len(all_keys)} objects in bucket: {len(candidates)} media, "
        f"{already_archived} already archived, "
        f"{len(ignored) - already_archived} outside the media prefixes"
    )
    if other_ignored:
        LOG.warning(
            f"{len(other_ignored)} keys outside every known prefix "
            f"(never touched, but worth a look): {other_ignored[:10]}"
        )

    orphans = sorted(candidates - referenced)
    missing = referenced - candidates
    if missing:
        # The inverse (data pointing at objects the mirror lacks) is a separate
        # concern (sync_media_to_r2.py), surfaced so a clean orphan count isn't
        # mistaken for a fully healthy mirror.
        LOG.warning(
            f"(also {len(missing)} referenced paths with no object in the bucket "
            f"— run sync_media_to_r2.py)"
        )

    for key in orphans:
        LOG.info(f"  orphan: {key}")
    LOG.info(f"{len(orphans)} orphaned media objects")

    if not args.archive:
        if orphans:
            LOG.info("Re-run with --archive to move these to the archive/ prefix.")
        return 0

    moved = 0
    failed = 0
    for key in orphans:
        dst_key = f"{ARCHIVE_PREFIX}{key}"
        try:
            # Server-side copy, then delete the original: an S3/R2 "move".
            s3.copy_object(
                Bucket=args.bucket,
                CopySource={"Bucket": args.bucket, "Key": key},
                Key=dst_key,
            )
            s3.delete_object(Bucket=args.bucket, Key=key)
        except Exception as e:
            LOG.error(f"Failed to archive {key}: {e}")
            failed += 1
            continue
        moved += 1
        LOG.info(f"  archived: {key} -> {dst_key}")

    LOG.info(
        f"Archived {moved}/{len(orphans)} orphans"
        + (f", {failed} failed" if failed else "")
    )
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
