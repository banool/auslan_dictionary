#!/usr/bin/env python3

"""
Remove videos that no longer exist on the media host from a scraped data file.

Some Signbank pages list <source> tags for videos whose objects are gone from
the media host (Nectar Swift, MEDIA_BASE_URL in common.py). Left in the data,
tapping such a sign gives the user a spinner and then an error. This script
takes a v1-shaped data file ({"data": [...]} with full video URLs), checks
every unique video URL against the media host, removes the ones that are
definitively dead (pruning sub_entries/entries this leaves empty), and writes
the cleaned file. scrape.sh runs it as the final phase of every scrape so dead
videos never reach assets/data; it can also be run standalone against any
v1-shaped file, e.g. the committed assets/data/data.json.

A URL is only removed on overwhelming evidence: --dead-attempts separate
requests, spread across rounds --recheck-delay seconds apart, must ALL return
an authentic Swift 404 — right status, Swift's transaction headers present,
and the exact not-found body — with not a single live answer in between. A
200/206 at any point keeps the video. Anything else (timeout, rate limiting,
5xx, redirects, 404s that don't match the Swift fingerprint) resolves nothing:
the URL gets extra rounds, and if it still hasn't produced a definitive answer
after --max-rounds the whole run FAILS rather than guess (exit 3, output not
written). Same philosophy as the scrape itself: a page that won't load fails
the letter; nothing is ever silently dropped OR silently kept on a flaky day.
This is also what keeps the weekly data PRs from flapping: a flaky week
produces a red run and no PR, not churn.

Expect the dead list to be stable week to week: Signbank keeps listing the
same dead videos, so every scrape re-collects them and this script re-removes
them (the workflow's diff-gate then sees no net change). A video Signbank
re-uploads answers alive and returns to the data automatically.

Every removal decision is recorded with full per-attempt evidence (status,
headers, body) in <report-dir>/report.json, and verify_removed_media.py
independently double-checks the removals in CI before a data PR opens.

Usage:

    # What scrape.sh runs (cleans the scrape output in place).
    uv run python filter_dead_media.py --input all_letters.json --output all_letters.json

    # Standalone against the committed data, extra-patient re-checks.
    uv run python filter_dead_media.py --input ../assets/data/data.json \\
        --output all_letters.json --recheck-delay 300

Exit codes:

    0  cleaned output written
    1  unexpected error
    2  too many dead URLs (--max-dead-fraction); output NOT written. Protects
       against a host-side event that 404s everything (e.g. a container
       rename) gutting the dictionary.
    3  some URLs never resolved to alive-or-dead; output NOT written.
"""

import argparse
import datetime
import hashlib
import json
import logging
import os
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from threading import Lock

import requests

from common import (
    LOG,
    _rate_limit,
    _respect_retry_after,
    make_session,
    strip_media_base,
)

# The exact body Swift serves for a missing object. Part of the authentic-404
# fingerprint: a 404 whose body differs is treated as inconclusive, not dead.
SWIFT_404_BODY = (
    b"<html><h1>Not Found</h1><p>The resource could not be found.</p></html>"
)

# Per-attempt classifications.
ALIVE = "alive"
AUTHENTIC_404 = "authentic_404"
INCONCLUSIVE = "inconclusive"

# Response headers worth keeping as evidence. x-trans-id/x-openstack-request-id
# prove the answer came from Swift itself rather than an intermediary.
REPORT_HEADERS = (
    "x-trans-id",
    "x-openstack-request-id",
    "content-type",
    "content-length",
    "content-range",
    "etag",
    "server",
    "date",
    "retry-after",
)

# How much of a response body we read for fingerprinting. The Swift 404 body is
# 70 bytes; anything bigger than this cap can't match it anyway.
BODY_CAP = 4096

REPORT_NAME = "report.json"


def utc_now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


def collect_url_refs(data) -> tuple:
    """All video URLs in a v1-shaped dict: (sorted unique URLs, total ref count)."""
    urls = set()
    refs = 0
    for entry in data["data"]:
        for sub_entry in entry.get("sub_entries", []):
            for url in sub_entry.get("video_links", []):
                urls.add(url)
                refs += 1
    return sorted(urls), refs


def classify_response(response, body: bytes) -> str:
    """Classify one response as ALIVE, AUTHENTIC_404, or INCONCLUSIVE.

    Alive needs no body check: an intermediary faking a 200 misclassifies
    toward KEEPING a video, which is the safe direction. Dead requires the full
    Swift fingerprint; any deviation degrades to inconclusive (also safe)."""
    status = response.status_code
    if status in (200, 206):
        return ALIVE
    if (
        status == 404
        and response.headers.get("x-trans-id")
        and response.headers.get("x-openstack-request-id")
        and response.headers.get("content-type", "").startswith("text/html")
        and body == SWIFT_404_BODY
    ):
        return AUTHENTIC_404
    return INCONCLUSIVE


def probe(session, url: str, timeout: int, round_num: int) -> dict:
    """One Range GET against [url], returning a full evidence record."""
    _rate_limit()
    record = {
        "ts": utc_now_iso(),
        "round": round_num,
        "status": None,
        "classification": INCONCLUSIVE,
        "headers": {},
        "body_sha256": None,
        "body_snippet": None,
        "body_matches_swift_404": False,
        "elapsed_ms": None,
        "error": None,
    }
    started = time.time()
    try:
        # stream=True so a host that ignores the Range header can't make us
        # download a whole video; we only read the body on non-2xx answers.
        with session.get(
            url,
            headers={"Range": "bytes=0-0"},
            timeout=timeout,
            allow_redirects=False,
            stream=True,
        ) as response:
            record["status"] = response.status_code
            record["headers"] = {
                name: response.headers[name]
                for name in REPORT_HEADERS
                if name in response.headers
            }
            body = b""
            if response.status_code not in (200, 206):
                for chunk in response.iter_content(256):
                    body += chunk
                    if len(body) > BODY_CAP:
                        break
                record["body_sha256"] = hashlib.sha256(body).hexdigest()
                record["body_snippet"] = repr(body[:200])
                record["body_matches_swift_404"] = body == SWIFT_404_BODY
            record["classification"] = classify_response(response, body)
            if response.status_code in (429, 503):
                _respect_retry_after(response)
    except requests.exceptions.RequestException as e:
        record["error"] = str(e)
    record["elapsed_ms"] = int((time.time() - started) * 1000)
    return record


def check_urls(session, urls: list, args) -> dict:
    """Resolve every URL to alive or dead, or leave it unresolved.

    Returns url -> {"result": "alive"|"dead"|None, "attempts": [...],
    "authentic_404s": int}. Round 0 probes everything; later rounds sleep
    --recheck-delay then re-probe only the still-undecided URLs."""
    results = {
        url: {"result": None, "attempts": [], "authentic_404s": 0} for url in urls
    }
    undecided = set(urls)
    for round_num in range(args.max_rounds):
        if not undecided:
            break
        if round_num > 0:
            LOG.info(
                f"Round {round_num}: {len(undecided)} URLs undecided; sleeping "
                f"{args.recheck_delay}s before re-probing"
            )
            time.sleep(args.recheck_delay)
        done = 0
        lock = Lock()
        total = len(undecided)
        with ThreadPoolExecutor(max_workers=args.num_workers) as executor:
            futures = {
                executor.submit(probe, session, url, args.timeout, round_num): url
                for url in sorted(undecided)
            }
            for future in as_completed(futures):
                url = futures[future]
                record = future.result()
                state = results[url]
                state["attempts"].append(record)
                if record["classification"] == ALIVE:
                    state["result"] = "alive"
                elif record["classification"] == AUTHENTIC_404:
                    state["authentic_404s"] += 1
                    if state["authentic_404s"] >= args.dead_attempts:
                        state["result"] = "dead"
                with lock:
                    done += 1
                    if done % 100 == 0 or done == total:
                        LOG.info(f"Round {round_num} progress: {done}/{total}")
        undecided = {url for url in undecided if results[url]["result"] is None}
    return results


def prune_dead_urls(data, dead_urls: set) -> dict:
    """Remove [dead_urls] from every video_links list, dropping sub_entries and
    entries this leaves empty. Only prunes what the removal emptied: anything
    already empty on the way in passes through untouched, so the script's
    footprint is exactly the dead URLs and their consequences."""
    refs_removed = 0
    sub_entries_removed = []
    entries_removed = []
    affected_entries = {}  # dead url -> [entry_in_english, ...]
    kept_entries = []
    for entry in data["data"]:
        word = entry["entry_in_english"]
        had_sub_entries = bool(entry.get("sub_entries"))
        kept_sub_entries = []
        for index, sub_entry in enumerate(entry.get("sub_entries", [])):
            links = sub_entry.get("video_links", [])
            kept_links = [url for url in links if url not in dead_urls]
            if len(kept_links) < len(links):
                refs_removed += len(links) - len(kept_links)
                for url in links:
                    if url in dead_urls:
                        words = affected_entries.setdefault(url, [])
                        if word not in words:
                            words.append(word)
                sub_entry["video_links"] = kept_links
                if not kept_links:
                    sub_entries_removed.append({"word": word, "index": index})
                    continue
            kept_sub_entries.append(sub_entry)
        entry["sub_entries"] = kept_sub_entries
        if had_sub_entries and not kept_sub_entries:
            entries_removed.append(word)
            continue
        kept_entries.append(entry)
    data["data"] = kept_entries
    return {
        "refs_removed": refs_removed,
        "sub_entries_removed": sub_entries_removed,
        "entries_removed": entries_removed,
        "affected_entries": affected_entries,
    }


def write_json_atomic(path: Path, obj):
    """Write JSON via a temp file + rename so an interrupted run never leaves a
    complete-looking partial behind. Matches scrape_signbank.py's format
    (indent=2, no trailing newline) so outputs are byte-comparable."""
    tmp_path = path.with_name(path.name + ".part")
    with open(tmp_path, "w") as f:
        f.write(json.dumps(obj, indent=2))
    os.replace(tmp_path, path)


def evidence_for(url: str, state: dict, affected_entries: dict) -> dict:
    return {
        "url": url,
        "path": strip_media_base(url),
        "affected_entries": affected_entries.get(url, []),
        "attempts": state["attempts"],
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="Where to write the cleaned data. May equal --input.",
    )
    parser.add_argument(
        "--report-dir",
        type=Path,
        default=Path("media_filter_report"),
        help="Directory for report.json (default: media_filter_report).",
    )
    parser.add_argument("--num-workers", type=int, default=8)
    parser.add_argument(
        "--timeout", type=int, default=30, help="Per-request timeout in seconds."
    )
    parser.add_argument(
        "--recheck-delay",
        type=int,
        default=60,
        help="Seconds between re-check rounds (default: 60).",
    )
    parser.add_argument(
        "--dead-attempts",
        type=int,
        default=5,
        help="Authentic 404s required, across that many rounds, to call a URL "
        "dead (default: 5).",
    )
    parser.add_argument(
        "--max-rounds",
        type=int,
        default=8,
        help="Give up (exit 3) if a URL is still unresolved after this many "
        "rounds (default: 8).",
    )
    parser.add_argument(
        "--max-dead-fraction",
        type=float,
        default=0.05,
        help="Fail (exit 2) without writing output if more than this fraction "
        "of unique URLs is dead (default: 0.05).",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Only check the first N unique URLs (for testing).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Classify and report, but never write --output.",
    )
    parser.add_argument("-d", "--debug", action="store_true")
    args = parser.parse_args()

    LOG.setLevel(logging.DEBUG if args.debug else logging.INFO)

    if args.dead_attempts > args.max_rounds:
        parser.error("--dead-attempts cannot exceed --max-rounds")
    if not args.input.exists():
        parser.error(f"Input file not found: {args.input}")

    started_at = utc_now_iso()
    with open(args.input) as f:
        data = json.load(f)

    urls, total_refs = collect_url_refs(data)
    # Every URL must be under the media base (the scrape guarantees this);
    # raises otherwise, same as make_data_v2.py would.
    for url in urls:
        strip_media_base(url)
    LOG.info(f"{len(urls)} unique video URLs ({total_refs} references) in {args.input}")
    if args.limit is not None:
        urls = urls[: args.limit]
        LOG.info(f"Limiting to first {len(urls)} URLs")

    session = make_session()
    results = check_urls(session, urls, args)

    alive_first_try = []
    alive_after_retry = []
    dead = []
    unresolved = []
    for url in urls:
        state = results[url]
        if state["result"] == "alive":
            if len(state["attempts"]) == 1:
                alive_first_try.append(url)
            else:
                alive_after_retry.append(url)
                if state["authentic_404s"] > 0:
                    LOG.warning(
                        f"Transient 404 recovered (host flakiness), keeping: {url}"
                    )
        elif state["result"] == "dead":
            dead.append(url)
            LOG.warning(f"Dead ({state['authentic_404s']} authentic 404s): {url}")
        else:
            unresolved.append(url)
            LOG.error(f"Unresolved after {len(state['attempts'])} attempts: {url}")

    dead_fraction = len(dead) / len(urls) if urls else 0.0
    prune_stats = prune_dead_urls(data, set(dead))

    report = {
        "schema_version": 1,
        "started_at": started_at,
        "finished_at": utc_now_iso(),
        "input": str(args.input),
        "output": str(args.output),
        "params": {
            key: (str(value) if isinstance(value, Path) else value)
            for key, value in vars(args).items()
        },
        "counts": {
            "unique_urls": len(urls),
            "total_refs": total_refs,
            "alive_first_try": len(alive_first_try),
            "alive_after_retry": len(alive_after_retry),
            "dead": len(dead),
            "unresolved": len(unresolved),
            "dead_fraction": round(dead_fraction, 4),
            "refs_removed": prune_stats["refs_removed"],
            "sub_entries_removed": len(prune_stats["sub_entries_removed"]),
            "entries_removed": len(prune_stats["entries_removed"]),
        },
        "dead": [
            evidence_for(url, results[url], prune_stats["affected_entries"])
            for url in dead
        ],
        "unresolved": [
            evidence_for(url, results[url], prune_stats["affected_entries"])
            for url in unresolved
        ],
        "alive_after_retry": [
            evidence_for(url, results[url], prune_stats["affected_entries"])
            for url in alive_after_retry
        ],
        "sub_entries_removed": prune_stats["sub_entries_removed"],
        "entries_removed": prune_stats["entries_removed"],
    }
    args.report_dir.mkdir(parents=True, exist_ok=True)
    report_path = args.report_dir / REPORT_NAME
    write_json_atomic(report_path, report)
    LOG.info(f"Report written to {report_path}")

    LOG.info(
        "Checked %d URLs: alive=%d (%d only after retries) dead=%d unresolved=%d; "
        "pruned %d refs, %d sub_entries, %d entries"
        % (
            len(urls),
            len(alive_first_try) + len(alive_after_retry),
            len(alive_after_retry),
            len(dead),
            len(unresolved),
            prune_stats["refs_removed"],
            len(prune_stats["sub_entries_removed"]),
            len(prune_stats["entries_removed"]),
        )
    )

    if unresolved:
        LOG.error(
            f"{len(unresolved)} URLs never resolved to alive-or-dead after "
            f"{args.max_rounds} rounds; refusing to write output. See {report_path}."
        )
        return 3
    if dead_fraction > args.max_dead_fraction:
        LOG.error(
            f"{len(dead)}/{len(urls)} URLs dead ({dead_fraction:.1%}) exceeds "
            f"--max-dead-fraction {args.max_dead_fraction:.1%}; this looks like a "
            f"host-side event, refusing to write output. See {report_path}."
        )
        return 2
    if args.dry_run:
        LOG.info("Dry run: not writing output.")
        return 0

    write_json_atomic(args.output, data)
    LOG.info(f"Cleaned data written to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
