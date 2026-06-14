#!/bin/bash

set -e

cd "$(dirname "$0")"

mv all_letters.json ../assets/data/data.json

# Produce the path-based data-v2.json that current app builds read (old builds
# keep reading the full-URL data.json). Raises if any video moved hosts.
python3 make_data_v2.py

date +%s > ../assets/data/latest_version
