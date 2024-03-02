# Scripts

## Automation
For automated scraping, just run something like this:
```
cd /var/www/auslan/scripts
/usr/bin/pipenv run bash create_data_update_pr.sh
```

## Scraping manually
First, enter the venv:
```
pipenv shell
```

To scrape Auslan Signbank, do this:

```
./incremental_scrape.sh
```

This starts with the existing data as the base. This will scrape one letter at a time. If the script crashes or you must stop it for some reason, you can resume from a particular letter by invoking it like this:

```
./incremental_scrape.sh '[d-z]'
```

Once you've got the data downloaded, move it in to place with this:
```
./move_data.sh
```

This moves the data and updates `latest_version`, which the app uses to see if there is new data to download. Before committing, make sure the changes look good with `git diff`.

This script assumes that the categories data is present at `../assets/data/categories.json` from a previous step. If it's not, you can get it like this:
```
python scrape_categories.py --output-file ../assets/data/categories.json
```

You can update the categories data without scraping for new words like this (we have to pass at least one URL to look at):
```
python scrape_signbank.py -d --existing-file ../assets/data/words_latest.json --categories-file ../assets/data/categories.json --urls 'https://auslan.org.au/dictionary/words/age-1.html' --output-file /tmp/data.json
cp /tmp/data.json ../assets/data/words_latest.json
```

## Old non incremental way
To run the scraper non-incrementally, do this:
```
python scrape_signbank.py -d --output-file data.json --existing-file ../assets/data/words_latest.json
```

This will read in the existing file and apply the changes over the top. If you want to start fresh, remove the `--existing-file` part.

If this looks good, move it into the place of the existing file:
```
mv data.json ../assets/data/words_latest.json
```

Note, often we fail to load some words or even pages for letters or even worse the entire letter, in which case you should probably do something like this:

```
python scrape_signbank.py -d --output-file data.json --existing-file ../assets/data/words_latest.json --letters c g
```
