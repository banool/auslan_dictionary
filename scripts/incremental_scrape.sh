#!/bin/bash

# Scrapes the signbank one letter at a time.
# Optionally accepts a positional argument, a regex for the letters.
# For example, if you only want to do from d onwards, you could run:
#   ./incremental_scrape.sh '[d-z]'
# This allows you to scrape a few letters at a time without losing progress.

if [ -z "$PIP_PYTHON_PATH" ]
then
    echo "ERROR: Run this from within the pipenv."
    exit 1
fi

REGEX=$1

cd "$(dirname "$0")"

if [[ -z $REGEX ]]; then
    echo "No regex was passed, copying in current data"
    cp ../assets/data/words_latest.json previous.json
else
    echo "Regex was passed, using current previous.json"
fi

rm -f letters_retrieved.txt

for l in {a..z}
do
    if [[ -z $REGEX || $l =~ $REGEX ]]; then
        echo "Getting words for letter $l"
        python scrape_signbank.py -d --output-file next.json --existing-file previous.json --letter $l
        echo "Successfully got words for letter $l"
        mv next.json previous.json
        echo $l >> letters_retrieved.txt
    fi
done

mv previous.json all_letters.json

echo "Scraped all letters, now make sure all_letters.json looks good. If it does, run move_data.sh"


