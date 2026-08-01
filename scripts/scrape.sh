#!/bin/bash

# Scrapes the signbank for category data, then entry data, then filters out
# videos that 404 on the media host so they never ship (filter_dead_media.py).
# This is the main entry point for a full scrape.
#
# Usage:
#   ./scrape.sh              # Normal scrape
#   ./scrape.sh --fresh      # Force fresh start (ignore existing progress)

set -e

cd "$(dirname "$0")"

# Pass through any arguments.
ARGS="$@"

echo "========================================"
echo "Starting full scrape"
echo "========================================"
echo ""

# Step 1: Scrape categories.
echo "Step 1: Scraping categories..."
if python scrape_categories.py -d --output-file ../assets/data/categories.json; then
    echo "Categories scraped successfully."
else
    echo "ERROR: Failed to scrape categories."
    exit 1
fi

# Brief pause between major operations.
echo "Waiting 10 seconds before scraping entries..."
sleep 10

# Step 2: Scrape entries.
echo ""
echo "Step 2: Scraping entries..."
./incremental_scrape.sh $ARGS

# Step 3: Remove videos that 404 on the media host. The prefilter snapshot is
# taken here (not by the filter) so verify_removed_media.py's "before" input is
# something the filter never touched.
echo ""
echo "Step 3: Filtering dead media..."
cp all_letters.json all_letters_prefilter.json
python filter_dead_media.py \
    --input all_letters.json \
    --output all_letters.json \
    --report-dir media_filter_report

echo ""
echo "========================================"
echo "Full scrape complete!"
echo "========================================"
echo "Output is in all_letters.json"
echo "If everything looks good, run: ./move_data.sh"
