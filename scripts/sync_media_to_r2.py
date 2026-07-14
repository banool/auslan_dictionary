#!/usr/bin/env python3

"""
Mirror every sign video referenced by assets/data/data-v2.json from the primary
media host (Nectar, MEDIA_BASE_URL in common.py) into the Cloudflare R2 bucket
that backs cdn.auslandictionary.org.

R2 is a *fallback* media host: the app lists it after Nectar in mediaBaseUrls
(see AUSLAN_MEDIA_MIRROR_BASE_URL in lib/main.dart), and the players fall
through to it when a Nectar fetch fails. For that to work each object must live
at the SAME path the app stores, i.e. data-v2.json's "/mp4video/11/11450.mp4"
becomes the R2 key "mp4video/11/11450.mp4", served at
https://cdn.auslandictionary.org/mp4video/11/11450.mp4.

Idempotent + incremental: it lists the keys already in the bucket once up front
and skips them, so a re-run only copies signs added since. Pass --force to
re-upload everything (e.g. after changing cache headers).

Credentials come from the environment (an R2 S3-API token — the same secrets
the CI mirror-to-r2 job uses):

    R2_ACCOUNT_ID          Cloudflare account id (for the S3 endpoint host)
    R2_ACCESS_KEY_ID       R2 access key id
    R2_SECRET_ACCESS_KEY   R2 secret access key

Usage:

    # Full initial backfill (long-running: ~5.5k unique files).
    R2_ACCOUNT_ID=... R2_ACCESS_KEY_ID=... R2_SECRET_ACCESS_KEY=... \
        uv run python sync_media_to_r2.py

    # Quick test against the first 20 unique videos.
    uv run python sync_media_to_r2.py --limit 20

    # See what would be uploaded without writing anything.
    uv run python sync_media_to_r2.py --dry-run
"""

import argparse
import json
import logging
import os
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from threading import Lock

import boto3
import requests
from botocore.config import Config
from retry import retry

from common import LOG, DEFAULT_TIMEOUT, MEDIA_BASE_URL, _rate_limit

# data-v2.json (paths, read by current app builds) is the source of truth for
# what media the app references. scripts/ -> repo root -> assets/data.
DEFAULT_DATA_FILE = (
    Path(__file__).resolve().parent.parent / "assets" / "data" / "data-v2.json"
)

# The R2 bucket. Media keys match the stored media paths, which span more than
# one top-level prefix (mp4video/ and auslan/), so the incremental skip-list
# below lists the whole bucket rather than a single prefix.
DEFAULT_BUCKET = "auslan-mirror"

# Long-lived cache: a given media path's bytes never change (a re-record gets a
# new path), so let the CDN + clients hold onto it.
MEDIA_CACHE_CONTROL = "public, max-age=31536000, immutable"

CHUNK_SIZE = 1 << 16  # 64 KiB.

# Same generous retry policy backup_videos.py uses against the slow/flaky source
# object store (1s, 2s, 4s, ... capped at 120s).
RETRY_KWARGS = dict(
    exceptions=(requests.exceptions.RequestException, RuntimeError),
    delay=1,
    backoff=2,
    max_delay=120,
    tries=12,
    logger=LOG,
)


class VideoNotFound(Exception):
    """Raised when a source video URL 404s. Not retried."""


def collect_media_paths(data_file: Path) -> list:
    """Sorted, deduplicated list of every media path in data-v2.json.

    data-v2.json stores paths (e.g. "/mp4video/11/11450.mp4"), not full URLs —
    that's the whole point of v2. Structure:
    {"data": [{"sub_entries": [{"video_links": [path, ...]}]}]}.
    """
    with open(data_file) as f:
        data = json.load(f)

    paths = set()
    for entry in data["data"]:
        for sub_entry in entry.get("sub_entries", []):
            for link in sub_entry.get("video_links", []):
                if link.lower().startswith("http"):
                    # v2 must store paths, not URLs. A full URL here means the
                    # data pipeline regressed — fail loudly rather than mirror
                    # to a wrong key.
                    raise ValueError(
                        f"Expected a media path in data-v2.json, got a full URL: "
                        f"{link!r}"
                    )
                paths.add(link)
    return sorted(paths)


def r2_key_for(path: str) -> str:
    """The R2 object key for a stored media path ("/mp4video/x.mp4" -> "mp4video/x.mp4")."""
    return path.lstrip("/")


def content_type_for(path: str) -> str:
    """Best-effort content type. .bak files are mp4 bytes the app renames, but
    they aren't served as <video> so octet-stream is safest for them."""
    return "video/mp4" if path.endswith(".mp4") else "application/octet-stream"


def make_s3_client():
    """An S3 client pointed at the account's R2 endpoint. Reads creds from env."""
    account_id = os.environ["R2_ACCOUNT_ID"]
    return boto3.client(
        "s3",
        endpoint_url=f"https://{account_id}.r2.cloudflarestorage.com",
        aws_access_key_id=os.environ["R2_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["R2_SECRET_ACCESS_KEY"],
        region_name="auto",
        config=Config(retries={"max_attempts": 5, "mode": "standard"}),
    )


def list_existing_keys(s3, bucket: str) -> set:
    """Every key already in the bucket, so we can skip re-uploads with a handful
    of list calls instead of a HEAD per file. Lists the whole bucket (media
    spans several prefixes); the few data/ keys are harmless in the set."""
    keys = set()
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket):
        for obj in page.get("Contents", []):
            keys.add(obj["Key"])
    return keys


@retry(**RETRY_KWARGS)
def _download_to(url: str, tmp_path: Path, timeout: int) -> int:
    """Stream a source video to tmp_path, returning the byte count. A 404 raises
    VideoNotFound (not retried); other non-200s retry with backoff."""
    _rate_limit()
    with requests.get(url, stream=True, timeout=timeout) as response:
        if response.status_code == 404:
            raise VideoNotFound(url)
        if response.status_code != 200:
            raise RuntimeError(f"Got status code {response.status_code} for {url}")
        total = 0
        with open(tmp_path, "wb") as f:
            for chunk in response.iter_content(chunk_size=CHUNK_SIZE):
                if chunk:
                    f.write(chunk)
                    total += len(chunk)
        return total


def process_path(path: str, s3, bucket: str, dry_run: bool, timeout: int) -> dict:
    """Copy one media path from Nectar to R2. Returns a status record with one
    of: ok, missing, failed."""
    key = r2_key_for(path)
    url = f"{MEDIA_BASE_URL}{path}"

    def record(status, num_bytes=None, error=None):
        rec = {"key": key, "bytes": num_bytes, "status": status}
        if error is not None:
            rec["error"] = error
        return rec

    if dry_run:
        return record("would_upload")

    tmp_fd, tmp_name = tempfile.mkstemp(suffix=".part")
    os.close(tmp_fd)
    tmp_path = Path(tmp_name)
    try:
        num_bytes = _download_to(url, tmp_path, timeout)
        s3.upload_file(
            str(tmp_path),
            bucket,
            key,
            ExtraArgs={
                "ContentType": content_type_for(path),
                "CacheControl": MEDIA_CACHE_CONTROL,
            },
        )
        return record("ok", num_bytes=num_bytes)
    except VideoNotFound:
        LOG.warning(f"Source video not found (404), skipping: {url}")
        return record("missing")
    except Exception as e:
        LOG.error(f"Failed to mirror {url} -> {key}: {e}")
        return record("failed", error=str(e))
    finally:
        try:
            tmp_path.unlink()
        except OSError:
            pass


def main():
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
        "--num-workers",
        type=int,
        default=8,
        help="Number of concurrent transfers (default: 8).",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Only process the first N unique paths (for testing).",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-upload even paths already present in the bucket.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report what would be uploaded without writing to R2.",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=DEFAULT_TIMEOUT,
        help=f"Per-request timeout in seconds (default: {DEFAULT_TIMEOUT}).",
    )
    parser.add_argument(
        "-d", "--debug", action="store_true", help="Enable debug logging."
    )
    args = parser.parse_args()

    LOG.setLevel(logging.DEBUG if args.debug else logging.INFO)

    if not args.data_file.exists():
        parser.error(f"Data file not found: {args.data_file}")

    for var in ("R2_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY"):
        if not os.environ.get(var):
            parser.error(f"Missing required env var: {var}")

    paths = collect_media_paths(args.data_file)
    LOG.info(f"Found {len(paths)} unique media paths in {args.data_file}")

    s3 = make_s3_client()

    if args.force:
        existing = set()
    else:
        LOG.info("Listing existing objects to skip (incremental)...")
        existing = list_existing_keys(s3, args.bucket)
        LOG.info(f"{len(existing)} objects already in {args.bucket}")

    todo = [p for p in paths if r2_key_for(p) not in existing]
    skipped_existing = len(paths) - len(todo)
    if args.limit is not None:
        todo = todo[: args.limit]
    LOG.info(
        f"{len(todo)} to mirror, {skipped_existing} already present"
        + (f" (limited to {args.limit})" if args.limit is not None else "")
    )

    records = []
    done = 0
    lock = Lock()
    total = len(todo)

    def run(path):
        return process_path(path, s3, args.bucket, args.dry_run, args.timeout)

    with ThreadPoolExecutor(max_workers=args.num_workers) as executor:
        futures = {executor.submit(run, p): p for p in todo}
        for future in as_completed(futures):
            records.append(future.result())
            with lock:
                done += 1
                if done % 100 == 0 or done == total:
                    LOG.info(f"Progress: {done}/{total}")

    summary = {
        "considered": len(paths),
        "skipped_existing": skipped_existing,
        "ok": sum(1 for r in records if r["status"] == "ok"),
        "missing": sum(1 for r in records if r["status"] == "missing"),
        "failed": sum(1 for r in records if r["status"] == "failed"),
        "would_upload": sum(1 for r in records if r["status"] == "would_upload"),
        "uploaded_bytes": sum(r["bytes"] or 0 for r in records),
    }
    LOG.info(
        "Done. ok=%(ok)d missing=%(missing)d failed=%(failed)d "
        "skipped_existing=%(skipped_existing)d would_upload=%(would_upload)d "
        "uploaded_bytes=%(uploaded_bytes)d" % summary
    )

    if summary["failed"] > 0:
        LOG.error(
            f"{summary['failed']} uploads failed after retries; re-run to retry them."
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
