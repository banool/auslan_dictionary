#!/bin/bash

# Scrapes the signbank for category data first and then for entry data.
# This is the main entry point for a full scrape.
#
# Usage:
#   ./scrape.sh              # Normal scrape
#   ./scrape.sh --validate   # Also validate video URLs
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

echo ""
echo "========================================"
echo "Full scrape complete!"
echo "========================================"
echo "Output is in all_letters.json"
echo "If everything looks good, run: ./move_data.sh"
