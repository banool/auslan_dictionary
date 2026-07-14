# Scripts

Scripts for scraping data from Auslan Signbank.

## Prerequisites

Install [uv](https://github.com/astral-sh/uv) for Python dependency management.

## Quick Start

### Automated Scraping (GitHub Actions)

The scrape runs automatically as the **Scrape Signbank** workflow
(`.github/workflows/scrape-signbank.yaml`): weekly (Sundays 04:00 UTC) and on
manual dispatch. It runs `scrape.sh` + `move_data.sh` and opens/updates a single
rolling data-update PR (branch `automated/update-signbank-data`, label
`data_update`) whenever the scraped data differs from what's committed.

To trigger a run by hand: **Actions → Scrape Signbank → Run workflow**, or
`gh workflow run scrape-signbank.yaml`.

> This previously ran as a weekly CronJob on the home k8s cluster
> (`server-platform`, now disabled) via `create_data_update_pr.sh`. That script
> is kept below for reference / local use, but the workflow no longer calls it —
> `create-pull-request` handles the branch/commit/PR instead of the old git
> dance.

For automated scraping on a server that creates a PR automatically (legacy):

```bash
cd /var/www/auslan/scripts
uv run bash create_data_update_pr.sh
```

This will:
1. Create a new branch with a timestamp (e.g., `update_data_20240115_143022`).
2. Scrape all data.
3. Create a PR if there are changes.

### Local Scraping (Manual)

For running locally with manual PR creation:

```bash
cd scripts

# Step 1: Run the full scrape
uv run ./scrape.sh --validate |& tee ~/run-out.log

# Step 2: Review the output
# Check all_letters.json looks correct
# Optionally diff against current data:
diff all_letters.json ../assets/data/data.json | head -100

# Step 3: Move data into place (updates latest_version)
./move_data.sh

# Step 4: Review and commit
git diff
git add -A
git commit -m "Update signbank data"

# Step 5: Create PR
git checkout -b banool/update-data-$(date +%Y%m%d)
git push -u origin HEAD
gh pr create --fill
```

## Scraping Options

### Full Scrape

```bash
uv run ./scrape.sh
```

This scrapes categories first, then entries letter by letter.

### Scrape with Video URL Validation

Validates each video URL with an OPTIONS request and removes entries with invalid videos:

```bash
uv run ./scrape.sh --validate
```

### Resume an Interrupted Scrape

The scraper automatically saves progress after each letter. If interrupted, just run it again:

```bash
uv run ./incremental_scrape.sh
```

It will skip already-completed letters and resume from where it left off.

### Force a Fresh Start

To ignore existing progress and start fresh:

```bash
uv run ./incremental_scrape.sh --fresh
```

### Start from a Specific Letter

To start (or resume) from a specific letter:

```bash
uv run ./incremental_scrape.sh --from d
```

## Individual Scripts

### scrape_categories.py

Scrapes category data from the site:

```bash
uv run python scrape_categories.py -d --output-file ../assets/data/categories.json
```

### scrape_signbank.py

Scrapes entry data. Usually called via `incremental_scrape.sh`, but can be run directly:

```bash
# Scrape specific letters
uv run python scrape_signbank.py -d \
    --letters a b c \
    --categories-file ../assets/data/categories.json \
    --existing-file ../assets/data/data.json \
    --output-file output.json

# Scrape specific URLs
uv run python scrape_signbank.py -d \
    --urls 'https://auslan.org.au/dictionary/words/hello-1.html' \
    --categories-file ../assets/data/categories.json \
    --output-file output.json

# With video URL validation
uv run python scrape_signbank.py -d \
    --letters a \
    --categories-file ../assets/data/categories.json \
    --output-file output.json \
    --validate-video-urls
```

### move_data.sh

Moves scraped data into place and updates `latest_version`:

```bash
./move_data.sh
```

### backup_videos.py

Downloads every sign video referenced by `assets/data/data.json` into a local directory tree, for an offline backup that doubles as a drop-in mirror. `--dest` is required.

```bash
# Back up everything (long-running: ~5.5k unique files, several GB).
uv run python backup_videos.py --dest /path/to/backup

# Quick test against the first 20 unique videos.
uv run python backup_videos.py --dest /tmp/auslan_test --limit 20

# Re-check sizes of already-downloaded files and repair any mismatches.
uv run python backup_videos.py --dest /path/to/backup --verify
```

Key behaviours:

- **Idempotent.** Re-running only fetches what's missing; existing files are skipped (use `--verify` to also re-check sizes via a HEAD request and repair mismatches). Downloads land in a `.part` file that is atomically renamed on completion, so an interrupted run never leaves a complete-looking partial behind.
- **Faithful layout.** Files are stored under `<dest>/<url-path>`, preserving the exact names and directory structure from the source (e.g. `<dest>/v1/AUTH_.../staticauslanorgau/mp4video/11/11450.mp4`). Each file's mtime is set from the server's `Last-Modified` header.
- **Resilient.** The source object store is slow and flaky, so each request retries with exponential backoff (12 tries, capped at 120s) and honours `Retry-After` on `429`/`503` responses. A `404` is recorded as `missing` and the run continues.
- **Manifest.** Writes `<dest>/backup_manifest.json` summarising every URL (`ok`/`skipped`/`missing`/`failed`) plus totals.

To operate it as a mirror, point a static file server at `<dest>` and replace `https://object-store.rc.nectar.org.au` with your mirror's host in the video URLs (the path after the host is unchanged). If `--dest` points inside the repo, add it to `.gitignore` so the multi-GB blob is never committed.

## Progress Files

The scraper creates several files to track progress:

- `scrape_state.txt` - List of completed letters
- `scrape_progress.json` - Current accumulated data
- `all_letters.json` - Final output (copy of progress when complete)

These can be safely deleted to start fresh, or will be automatically managed by `--fresh`.

## Troubleshooting

### Scrape keeps failing on a specific letter

Try running just that letter with more debug output:

```bash
uv run python scrape_signbank.py -d \
    --letters x \
    --categories-file ../assets/data/categories.json \
    --existing-file scrape_progress.json \
    --output-file test.json
```

### Video URLs are returning errors

Some video URLs on the site may be broken. Use `--validate` to filter these out:

```bash
uv run ./scrape.sh --validate
```

### Rate limiting

The scraper includes basic rate limiting. If you're getting many failures, try reducing concurrency by editing `--num-workers` in the Python scripts (default is 8).

## Updating Just Categories

To update category data without re-scraping all entries:

```bash
# Scrape fresh categories
uv run python scrape_categories.py -d --output-file ../assets/data/categories.json

# Re-apply categories to existing data (pass a dummy URL)
uv run python scrape_signbank.py -d \
    --existing-file ../assets/data/data.json \
    --categories-file ../assets/data/categories.json \
    --urls 'https://auslan.org.au/dictionary/words/age-1.html' \
    --output-file /tmp/data.json

cp /tmp/data.json ../assets/data/data.json
```
