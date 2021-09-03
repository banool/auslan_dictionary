#!/bin/bash

cd "$(dirname "$0")"

mv all_letters.json ../assets/data/words.json

date +%s > ../assets/data/latest_version
