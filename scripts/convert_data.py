#!/usr/bin/env python

"""
Previously the definitions were structured like this:
    List[Dict[str, List[str]]]
This script restructures the existing data to:
    Dict[str, List[str]]
This was a one time operation, the scrape_signbank.py script
now outputs the data in the latter format.
"""

import argparse
import collections
import json


parser = argparse.ArgumentParser()
parser.add_argument("file")
args = parser.parse_args()

with open(args.file, "r") as f:
    data = json.load(f)


out = {}
for k, v in data.items():
    definitions = collections.defaultdict(list)
    for x in v["definitions"]:
        for subk, subv in x.items():
            definitions[subk] += subv
    v["definitions"] = definitions
    out[k] = v

print(json.dumps(out, indent=4))
