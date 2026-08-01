#!/usr/bin/env python3

"""
Independently confirm that every video URL the media filter removed really is
gone from the media host.

This is a deliberate second implementation, not a refactor target: it must
stay a different code path from filter_dead_media.py so that a bug in the
filter's classifier can't agree with itself. The differences are on purpose:
stdlib urllib instead of requests (none of common.py's HTTP machinery), plain
full GETs with no Range header, sequential requests at ~1s + jitter instead of
a threaded sweep, a different User-Agent, and a locally re-implemented
authentic-404 fingerprint.

It computes the removed set itself by diffing --before and --after (never
trusting the filter's report), then re-checks every removed URL against the
media host over --attempts rounds spaced --attempt-delay apart:

    FALSE_POSITIVE  answered alive at any point -> the filter removed a
                    working video; FAIL.
    CONFIRMED       every attempt was an authentic Swift 404.
    UNCONFIRMED     anything else -> the removal can't be verified; FAIL.

It also fails if the filter ADDED any URL, and samples kept URLs, warning
(without failing — keeping too much is the safe direction) if any look dead.
The mirror (MIRROR_BASE_URL) status of each removed URL is recorded for
information only: a Nectar-dead video may legitimately still sit in the mirror
bucket until archive_orphaned_media.py moves it aside.

Usage:

    uv run python verify_removed_media.py \\
        --before all_letters_prefilter.json --after all_letters.json

Exit codes: 0 all removals confirmed; 1 verification failed or error.
"""

import argparse
import json
import logging
import os
import random
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from common import LOG, MIRROR_BASE_URL, strip_media_base

VERIFY_USER_AGENT = "auslan-dictionary-verify/1.0"

# Swift's exact body for a missing object. Re-implemented here rather than
# imported from filter_dead_media on purpose (see module docstring).
NOT_FOUND_BODY = (
    b"<html><h1>Not Found</h1><p>The resource could not be found.</p></html>"
)

# How much body we read: enough to prove a video serves bytes / to hold the
# 70-byte not-found body, without downloading whole videos.
READ_CAP = 1024

VERDICT_CONFIRMED = "CONFIRMED"
VERDICT_FALSE_POSITIVE = "FALSE_POSITIVE"
VERDICT_UNCONFIRMED = "UNCONFIRMED"


def collect_urls(path: Path) -> set:
    """Every video URL in a v1-shaped data file."""
    with open(path) as f:
        data = json.load(f)
    urls = set()
    for entry in data["data"]:
        for sub_entry in entry.get("sub_entries", []):
            urls.update(sub_entry.get("video_links", []))
    return urls


def pace():
    """Sequential, deliberately un-burst-y pacing (vs the filter's threaded
    0.1s-interval sweep)."""
    time.sleep(0.5 + random.random())


def fetch(url: str, timeout: int) -> dict:
    """One plain GET. Returns {status, headers (HTTPMessage or None), body,
    error}; 4xx/5xx come back as records, not exceptions."""
    request = urllib.request.Request(url, headers={"User-Agent": VERIFY_USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return {
                "status": response.status,
                "headers": response.headers,
                "body": response.read(READ_CAP),
                "error": None,
            }
    except urllib.error.HTTPError as e:
        try:
            body = e.read(READ_CAP)
        except Exception:
            body = b""
        return {"status": e.code, "headers": e.headers, "body": body, "error": None}
    except Exception as e:
        return {"status": None, "headers": None, "body": b"", "error": str(e)}


def is_alive(result: dict) -> bool:
    return result["status"] == 200 and len(result["body"]) > 0


def is_authentic_404(result: dict) -> bool:
    headers = result["headers"]
    return (
        result["status"] == 404
        and headers is not None
        and headers.get("x-trans-id") is not None
        and headers.get("x-openstack-request-id") is not None
        and (headers.get("content-type") or "").startswith("text/html")
        and result["body"].strip() == NOT_FOUND_BODY
    )


def attempt_record(result: dict, attempt: int) -> dict:
    """A JSON-serializable evidence record for one fetch."""
    headers = result["headers"]
    kept_headers = {}
    if headers is not None:
        for name in (
            "x-trans-id",
            "x-openstack-request-id",
            "content-type",
            "content-length",
            "server",
            "date",
            "cf-cache-status",
        ):
            if headers.get(name) is not None:
                kept_headers[name] = headers.get(name)
    return {
        "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "attempt": attempt,
        "status": result["status"],
        "headers": kept_headers,
        "body_snippet": repr(result["body"][:200]),
        "alive": is_alive(result),
        "authentic_404": is_authentic_404(result),
        "error": result["error"],
    }


def write_json_atomic(path: Path, obj):
    tmp_path = path.with_name(path.name + ".part")
    with open(tmp_path, "w") as f:
        f.write(json.dumps(obj, indent=2))
    os.replace(tmp_path, path)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--before", required=True, type=Path)
    parser.add_argument("--after", required=True, type=Path)
    parser.add_argument(
        "--report-file",
        type=Path,
        default=Path("media_filter_report/verify_report.json"),
    )
    parser.add_argument(
        "--attempts",
        type=int,
        default=3,
        help="Rounds of checks per removed URL (default: 3).",
    )
    parser.add_argument(
        "--attempt-delay",
        type=int,
        default=30,
        help="Seconds between rounds (default: 30).",
    )
    parser.add_argument(
        "--initial-delay",
        type=int,
        default=0,
        help="Sleep this long before the first check, so probes land at a "
        "different time than the filter's (CI passes 120).",
    )
    parser.add_argument(
        "--kept-sample-size",
        type=int,
        default=30,
        help="How many kept URLs to spot-check as alive (default: 30).",
    )
    parser.add_argument("--timeout", type=int, default=60)
    parser.add_argument("-d", "--debug", action="store_true")
    args = parser.parse_args()

    LOG.setLevel(logging.DEBUG if args.debug else logging.INFO)

    for path in (args.before, args.after):
        if not path.exists():
            parser.error(f"File not found: {path}")

    before = collect_urls(args.before)
    after = collect_urls(args.after)
    removed = sorted(before - after)
    added = sorted(after - before)
    LOG.info(
        f"{len(before)} unique URLs before, {len(after)} after: "
        f"{len(removed)} removed, {len(added)} added"
    )
    if added:
        LOG.error(
            f"The filter must never ADD URLs, but {len(added)} appeared: "
            f"{added[:5]}{'...' if len(added) > 5 else ''}"
        )

    if args.initial_delay and removed:
        LOG.info(f"Sleeping {args.initial_delay}s before checking (--initial-delay)")
        time.sleep(args.initial_delay)

    # Re-check every removed URL over --attempts spaced rounds. A URL that ever
    # answers alive is decided immediately (false positive); everything else
    # gets all attempts so CONFIRMED means "authentic 404 every single time".
    evidence = {url: [] for url in removed}
    false_positives = []
    undecided = list(removed)
    for attempt in range(args.attempts):
        if attempt > 0 and undecided:
            LOG.info(f"Sleeping {args.attempt_delay}s before round {attempt}")
            time.sleep(args.attempt_delay)
        still_undecided = []
        for url in undecided:
            pace()
            result = fetch(url, args.timeout)
            evidence[url].append(attempt_record(result, attempt))
            if is_alive(result):
                LOG.error(f"FALSE POSITIVE: removed URL answered alive: {url}")
                false_positives.append(url)
            else:
                still_undecided.append(url)
        undecided = still_undecided

    confirmed = []
    unconfirmed = []
    for url in removed:
        if url in false_positives:
            continue
        records = evidence[url]
        if len(records) == args.attempts and all(r["authentic_404"] for r in records):
            confirmed.append(url)
        else:
            unconfirmed.append(url)
            LOG.error(f"UNCONFIRMED: could not verify removal of {url}")

    # Informational: does the mirror still hold a copy? (Expected for videos
    # that died on Nectar after being mirrored; the archiver deals with them.)
    mirror_status = {}
    for url in removed:
        pace()
        result = fetch(MIRROR_BASE_URL + strip_media_base(url), args.timeout)
        if is_alive(result):
            mirror_status[url] = "alive"
        elif result["status"] == 404:
            mirror_status[url] = "404"
        else:
            mirror_status[url] = f"other ({result['status'] or result['error']})"
    mirror_alive = sorted(u for u, s in mirror_status.items() if s == "alive")
    if mirror_alive:
        LOG.info(
            f"{len(mirror_alive)} removed URLs still alive on the mirror "
            f"(informational; archive_orphaned_media.py handles these)"
        )

    # Spot-check kept URLs the same user-visible way (must serve bytes from the
    # primary host). Failures warn but don't fail the run: keeping too much is
    # the safe direction, and the filter itself refuses to guess.
    kept_sample = sorted(
        random.sample(sorted(after), min(args.kept_sample_size, len(after)))
    )
    kept_suspect = {}
    for url in kept_sample:
        pace()
        result = fetch(url, args.timeout)
        if not is_alive(result):
            kept_suspect[url] = attempt_record(result, 0)
            LOG.warning(
                f"KEPT_SUSPECT: kept URL did not answer alive "
                f"(status={result['status']} error={result['error']}): {url}"
            )

    report = {
        "schema_version": 1,
        "finished_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "params": {
            key: (str(value) if isinstance(value, Path) else value)
            for key, value in vars(args).items()
        },
        "removed_total": len(removed),
        "confirmed": len(confirmed),
        "false_positives": [
            {"url": url, "attempts": evidence[url]} for url in false_positives
        ],
        "unconfirmed": [{"url": url, "attempts": evidence[url]} for url in unconfirmed],
        "added_urls": added,
        "mirror_status": mirror_status,
        "kept_sampled": len(kept_sample),
        "kept_suspect": kept_suspect,
    }
    args.report_file.parent.mkdir(parents=True, exist_ok=True)
    write_json_atomic(args.report_file, report)
    LOG.info(f"Report written to {args.report_file}")

    LOG.info(
        f"Removed {len(removed)}: confirmed={len(confirmed)} "
        f"false_positives={len(false_positives)} unconfirmed={len(unconfirmed)}; "
        f"kept sample {len(kept_sample)}, suspect {len(kept_suspect)}"
    )
    if false_positives or unconfirmed or added:
        LOG.error("Verification FAILED.")
        return 1
    LOG.info("All removals independently confirmed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
