#!/bin/bash

# Scrapes the signbank for category data first and then for entry data.

if [ -z "$PIPENV_ACTIVE" ]
then
    echo "ERROR: Run this from within the pipenv."
    exit 1
fi

cd "$(dirname "$0")"

# Scrape categories
python scrape_categories.py -d --output-file ../assets/data/categories.json

sleep 10

# Scrape entries
./incremental_scrape.sh
