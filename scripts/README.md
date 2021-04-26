# Scripts

To scrape Auslan Signbank, do this:

```
python scrape_signbank.py -d --output-file data.json --existing-file ../assets/data/words.json
```

This will read in the existing file and apply the changes over the top. If you want to start fresh, remove the `--existing-file` part.

If this looks good, move it into the place of the existing file:
```
mv data.json ../assets/data/words.json
```

Note, often we fail to load some words or even pages for letters or even worse the entire letter, in which case you should probably do something like this:

```
python scrape_signbank.py -d --output-file data.json --existing-file ../assets/data/words.json --letters c g
```
