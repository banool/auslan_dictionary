# Scripts

## Automation
For automated scraping, just run something like this:
```
cd /var/www/auslan/scripts
uv run bash create_data_update_pr.sh
```

## Scraping manually
First, install `uv`.

To scrape Auslan Signbank, do this:

```
uv run ./incremental_scrape.sh
```

This starts with the existing data as the base. This will scrape one letter at a time. If the script crashes or you must stop it for some reason, you can resume from a particular letter by invoking it like this:

```
uv run ./incremental_scrape.sh '[d-z]'
```

Once you've got the data downloaded, move it in to place with this:
```
./move_data.sh
```

This moves the data and updates `latest_version`, which the app uses to see if there is new data to download. Before committing, make sure the changes look good with `git diff`.

This script assumes that the categories data is present at `../assets/data/categories.json` from a previous step. If it's not, you can get it like this:
```
uv run scrape_categories.py --output-file ../assets/data/categories.json
```

You can update the categories data without scraping for new words like this (we have to pass at least one URL to look at):
```
uv run scrape_signbank.py -d --existing-file ../assets/data/data.json --categories-file ../assets/data/categories.json --urls 'https://auslan.org.au/dictionary/words/age-1.html' --output-file /tmp/data.json
cp /tmp/data.json ../assets/data/data.json
```

---
Out of date, likely doesn't work:

## Old non incremental way
To run the scraper non-incrementally, do this:
```
uv run scrape_signbank.py -d --categories-file ../assets/data/categories.json --existing-file ../assets/data/words_latest.json --output-file data.json
```

This will read in the existing file and apply the changes over the top. If you want to start fresh, remove the `--existing-file` part.

If this looks good, move it into the place of the existing file:
```
mv data.json ../assets/data/words_latest.json
```

Note, often we fail to load some words or even pages for letters or even worse the entire letter, in which case you should probably do something like this:

```
uv run scrape_signbank.py -d --output-file data.json --existing-file ../assets/data/words_latest.json --letters c g
```
