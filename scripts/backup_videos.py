#!/usr/bin/env python3

"""
Download every sign video referenced by assets/data/data.json into a local
directory tree, so we have a full offline backup of the media that the app
streams from auslan.org.au's object store.

The videos are written preserving the exact path from the source host, e.g.

    https://object-store.rc.nectar.org.au/v1/AUTH_.../staticauslanorgau/mp4video/11/11450.mp4
        ->  <dest>/v1/AUTH_.../staticauslanorgau/mp4video/11/11450.mp4

This means the backup doubles as a drop-in mirror: point any static file
server at <dest> and the original URLs are reproduced by swapping only the
scheme + host (https://object-store.rc.nectar.org.au -> https://<your-mirror>).

The script is idempotent: re-running only fetches videos that are missing.
Downloads land in a .part file that is atomically renamed on completion, so an
interrupted run never leaves a complete-looking partial behind. Each file's
modification time is set from the server's Last-Modified header to preserve the
source metadata.

Usage:

    # Back up everything (this is long-running: ~5.5k unique files).
    uv run python backup_videos.py --dest /path/to/backup

    # Quick test against the first 20 unique videos.
    uv run python backup_videos.py --dest /tmp/auslan_test --limit 20

    # Re-check sizes of already-downloaded files and repair any mismatches.
    uv run python backup_videos.py --dest /path/to/backup --verify
"""

import argparse
import json
import logging
import os
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from email.utils import parsedate_to_datetime
from pathlib import Path
from threading import Lock
from urllib.parse import urlsplit

import requests
from retry import retry

from common import LOG, DEFAULT_TIMEOUT, _rate_limit

# Retry config for network calls. The source object store is slow and flaky, so
# we retry generously with exponential backoff (1s, 2s, 4s, ... capped at 120s).
# Mirrors the policy in common.py but with a few more tries.
RETRY_KWARGS = dict(
    exceptions=(requests.exceptions.RequestException, RuntimeError),
    delay=1,
    backoff=2,
    max_delay=120,
    tries=12,
    logger=LOG,
)

# Cap on how long we'll honor a server's Retry-After header (seconds), so a
# pathological value can't stall a worker indefinitely.
RETRY_AFTER_CAP = 120

# Default location of the scraped data relative to this script (scripts/ ->
# repo root -> assets/data/data.json).
DEFAULT_DATA_FILE = (
    Path(__file__).resolve().parent.parent / "assets" / "data" / "data.json"
)

# Name of the manifest written into the destination directory.
MANIFEST_NAME = "backup_manifest.json"

# Size of chunks streamed from the network to disk.
CHUNK_SIZE = 1 << 16  # 64 KiB.


class VideoNotFound(Exception):
    """Raised when a video URL returns 404. Deliberately not retried."""


def _respect_retry_after(response):
    """
    If the server sent a Retry-After header (typically with a 429 or 503),
    sleep for the requested duration (capped) so we back off politely. Supports
    both the integer-seconds and HTTP-date forms of the header.
    """
    header = response.headers.get("Retry-After")
    if not header:
        return
    delay = None
    try:
        delay = float(header)
    except ValueError:
        try:
            delay = parsedate_to_datetime(header).timestamp() - time.time()
        except (TypeError, ValueError):
            delay = None
    if delay and delay > 0:
        delay = min(delay, RETRY_AFTER_CAP)
        LOG.warning(f"Server asked us to back off; sleeping {delay:.0f}s (Retry-After)")
        time.sleep(delay)


def collect_video_urls(data_file: Path) -> list:
    """
    Walk data.json and return a sorted, deduplicated list of every video URL.

    The structure is {"data": [{"sub_entries": [{"video_links": [url, ...]}]}]}.
    """
    with open(data_file) as f:
        data = json.load(f)

    urls = set()
    for entry in data["data"]:
        for sub_entry in entry.get("sub_entries", []):
            for url in sub_entry.get("video_links", []):
                if not url.lower().startswith("http"):
                    # Every link in the data file is a full URL today; skip any
                    # relative ones defensively rather than guessing a host.
                    LOG.warning(f"Skipping non-http video link: {url}")
                    continue
                urls.add(url)
    return sorted(urls)


def local_path_for(url: str, dest: Path, include_host: bool) -> Path:
    """Map a video URL to its path within the backup tree."""
    parts = urlsplit(url)
    path = parts.path.lstrip("/")
    if include_host:
        return dest / parts.netloc / path
    return dest / path


@retry(**RETRY_KWARGS)
def _download_request(url: str, tmp_path: Path, timeout: int):
    """
    Stream a video to tmp_path. Returns (bytes_written, last_modified_header).

    Retries with exponential backoff on network errors and unexpected status
    codes. A 404 raises VideoNotFound, which is not retried. On a 429/503 with a
    Retry-After header we sleep as instructed before letting the retry fire.
    """
    _rate_limit()
    with requests.get(url, stream=True, timeout=timeout) as response:
        if response.status_code == 404:
            raise VideoNotFound(url)
        if response.status_code != 200:
            if response.status_code in (429, 503):
                _respect_retry_after(response)
            raise RuntimeError(f"Got status code {response.status_code} for {url}")
        total = 0
        with open(tmp_path, "wb") as f:
            for chunk in response.iter_content(chunk_size=CHUNK_SIZE):
                if chunk:
                    f.write(chunk)
                    total += len(chunk)
        return total, response.headers.get("Last-Modified")


@retry(**RETRY_KWARGS)
def _remote_content_length(url: str, timeout: int):
    """Return the remote Content-Length via a HEAD request, or None if unknown."""
    _rate_limit()
    response = requests.head(url, timeout=timeout, allow_redirects=True)
    if response.status_code == 404:
        return None
    if response.status_code != 200:
        if response.status_code in (429, 503):
            _respect_retry_after(response)
        raise RuntimeError(f"Got status code {response.status_code} for HEAD {url}")
    length = response.headers.get("Content-Length")
    return int(length) if length is not None else None


def _apply_last_modified(path: Path, last_modified: str):
    """Set the file's mtime from a Last-Modified header value, if parseable."""
    if not last_modified:
        return
    try:
        ts = parsedate_to_datetime(last_modified).timestamp()
        os.utime(path, (ts, ts))
    except (TypeError, ValueError) as e:
        LOG.debug(f"Could not apply Last-Modified '{last_modified}' to {path}: {e}")


def process_url(
    url: str, dest: Path, include_host: bool, verify: bool, dry_run: bool, timeout: int
) -> dict:
    """
    Download a single video if needed and return a manifest record:
    {url, path (relative to dest), bytes, last_modified, status}.

    status is one of: ok, skipped, missing, failed, would_download.
    """
    local_path = local_path_for(url, dest, include_host)
    rel_path = str(local_path.relative_to(dest))

    def record(status, num_bytes=None, last_modified=None, error=None):
        rec = {
            "url": url,
            "path": rel_path,
            "bytes": num_bytes,
            "last_modified": last_modified,
            "status": status,
        }
        if error is not None:
            rec["error"] = error
        return rec

    # Idempotent skip: a non-empty final file means a previously completed
    # download (the atomic rename below guarantees this).
    if local_path.exists() and local_path.stat().st_size > 0:
        local_size = local_path.stat().st_size
        if not verify:
            return record("skipped", num_bytes=local_size)
        try:
            remote_size = _remote_content_length(url, timeout)
        except Exception as e:
            LOG.warning(f"Could not verify size for {url}, keeping existing file: {e}")
            return record("skipped", num_bytes=local_size)
        if remote_size is None or remote_size == local_size:
            return record("skipped", num_bytes=local_size)
        LOG.info(
            f"Size mismatch for {url} (local {local_size} != remote {remote_size}), re-downloading"
        )

    if dry_run:
        return record("would_download")

    tmp_path = local_path.with_name(local_path.name + ".part")
    try:
        os.makedirs(local_path.parent, exist_ok=True)
        num_bytes, last_modified = _download_request(url, tmp_path, timeout)
        os.replace(tmp_path, local_path)
        _apply_last_modified(local_path, last_modified)
        return record("ok", num_bytes=num_bytes, last_modified=last_modified)
    except VideoNotFound:
        LOG.warning(f"Video not found (404), skipping: {url}")
        return record("missing")
    except Exception as e:
        LOG.error(f"Failed to download {url}: {e}")
        return record("failed", error=str(e))
    finally:
        # Clean up any partial file from a failed/aborted download.
        if tmp_path.exists():
            try:
                tmp_path.unlink()
            except OSError:
                pass


def write_manifest(dest: Path, records: list, data_file: Path):
    """Atomically write the backup manifest into the destination directory."""
    summary = {
        "total": len(records),
        "ok": sum(1 for r in records if r["status"] == "ok"),
        "skipped": sum(1 for r in records if r["status"] == "skipped"),
        "missing": sum(1 for r in records if r["status"] == "missing"),
        "failed": sum(1 for r in records if r["status"] == "failed"),
        "would_download": sum(1 for r in records if r["status"] == "would_download"),
        "total_bytes": sum(r["bytes"] or 0 for r in records),
        "source_data_file": str(data_file),
        "source_data_file_mtime": int(data_file.stat().st_mtime),
    }
    manifest = {"summary": summary, "videos": sorted(records, key=lambda r: r["url"])}

    manifest_path = dest / MANIFEST_NAME
    tmp_path = manifest_path.with_name(manifest_path.name + ".part")
    with open(tmp_path, "w") as f:
        json.dump(manifest, f, indent=2)
    os.replace(tmp_path, manifest_path)
    return summary


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--dest",
        required=True,
        type=Path,
        help="Directory to write the video backup into (required).",
    )
    parser.add_argument(
        "--data-file",
        type=Path,
        default=DEFAULT_DATA_FILE,
        help=f"Path to data.json (default: {DEFAULT_DATA_FILE}).",
    )
    parser.add_argument(
        "--num-workers",
        type=int,
        default=8,
        help="Number of concurrent downloads (default: 8).",
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="HEAD-check existing files and re-download on size mismatch.",
    )
    parser.add_argument(
        "--include-host",
        action="store_true",
        help="Nest files under <dest>/<host>/<path> instead of <dest>/<path>.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Only process the first N unique URLs (for testing).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report what would be downloaded without writing video files.",
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

    urls = collect_video_urls(args.data_file)
    LOG.info(f"Found {len(urls)} unique video URLs in {args.data_file}")

    # Guard the host-stripping layout: if the data ever spans multiple hosts,
    # stripping the host would collide paths, so require --include-host instead.
    hosts = {urlsplit(u).netloc for u in urls}
    if len(hosts) > 1 and not args.include_host:
        parser.error(
            f"Video URLs span multiple hosts {sorted(hosts)}; re-run with --include-host "
            f"to nest files under <dest>/<host>/<path>."
        )

    if args.limit is not None:
        urls = urls[: args.limit]
        LOG.info(f"Limiting to first {len(urls)} URLs")

    args.dest.mkdir(parents=True, exist_ok=True)

    records = []
    done = 0
    lock = Lock()
    total = len(urls)

    def run(url):
        return process_url(
            url, args.dest, args.include_host, args.verify, args.dry_run, args.timeout
        )

    with ThreadPoolExecutor(max_workers=args.num_workers) as executor:
        futures = {executor.submit(run, url): url for url in urls}
        for future in as_completed(futures):
            record = future.result()
            records.append(record)
            with lock:
                done += 1
                if done % 100 == 0 or done == total:
                    LOG.info(f"Progress: {done}/{total}")

    summary = write_manifest(args.dest, records, args.data_file)

    LOG.info(
        "Done. ok=%(ok)d skipped=%(skipped)d missing=%(missing)d failed=%(failed)d "
        "would_download=%(would_download)d total_bytes=%(total_bytes)d" % summary
    )
    LOG.info(f"Manifest written to {args.dest / MANIFEST_NAME}")

    if summary["failed"] > 0:
        LOG.error(
            f"{summary['failed']} downloads failed after retries; re-run to retry them."
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
