#!/bin/bash

# Scrapes the signbank one letter at a time.
# Optionally accepts a positional argument, a regex for the letters.
# For example, if you only want to do from d onwards, you could run:
#   ./incremental_scrape.sh '[d-z]'
# This allows you to scrape a few letters at a time without losing progress.

if [ -z "$UV" ]
then
    echo "ERROR: Run this with uv."
    exit 1
fi

set -e

REGEX=$1

cd "$(dirname "$0")"

if [[ -z $REGEX ]]; then
    echo "No regex was passed, copying in current data"
    cp ../assets/data/data.json previous.json
else
    echo "Regex was passed, using current previous.json"
fi

rm -f letters_retrieved.txt

for l in {a..z}
do
    if [[ -z $REGEX || $l =~ $REGEX ]]; then
        echo "Getting words for letter $l"
        if python scrape_signbank.py -d --output-file next.json --existing-file previous.json --letter $l --categories-file ../assets/data/categories.json ; then
            echo "Successfully got words for letter $l"
        else
            echo "Failed on letter $l"
            exit 1
        fi
        mv next.json previous.json
        echo $l >> letters_retrieved.txt
    fi
done

mv previous.json all_letters.json

echo "Scraped all letters, now make sure all_letters.json looks good. If it does, run move_data.sh"


