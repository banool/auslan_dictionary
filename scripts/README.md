# Scripts

Scripts for scraping data from Auslan Signbank.

## Prerequisites

Install [uv](https://github.com/astral-sh/uv) for Python dependency management.

## Quick Start

### Automated Scraping (Server)

For automated scraping on a server that creates a PR automatically:

```bash
cd /var/www/auslan/scripts
uv run bash create_data_update_pr.sh
```

This will:
1. Create a new branch with a timestamp (e.g., `update_data_20240115_143022`)
2. Scrape all data
3. Create a PR if there are changes

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
