#!/usr/bin/env python

import argparse
import json

parser = argparse.ArgumentParser()
parser.add_argument(
    "words_json_file",
    help="Path to JSON data file"
)
parser.add_argument(
    "other_words_file",
    help="Path to file containing one word on each line"
)
args = parser.parse_args()

with open(args.words_json_file, "r") as f:
    current_words = list(json.loads(f.read()).keys())

with open(args.other_words_file, "r") as f:
    other_words = f.read().splitlines()


def normalise(w):
    return w.lower().replace(",", "").replace(" ", "")


current_words = {normalise(w) for w in current_words if len(w)}


for word in other_words:
    word = normalise(word)
    if len(word) <= 1:
        continue
    if word not in current_words:
        print(word)
