#!/bin/bash

# Scrapes the signbank for category data first and then for entry data.

cd "$(dirname "$0")"

# Scrape categories
python scrape_categories.py -d --output-file ../assets/data/categories.json

sleep 10

# Scrape entries
./incremental_scrape.sh
