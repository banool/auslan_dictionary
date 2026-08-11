#!/bin/bash

set -e

# Checked before the mv below, not after: make_data_v2.py pulls in common.py,
# which needs requests + retry from the venv, so a bare run used to move
# all_letters.json away and only then die on the import, leaving data.json
# updated with no matching data-v2.json.
if [ -z "$UV" ]; then
    echo "ERROR: Run this with uv."
    exit 1
fi

cd "$(dirname "$0")"

mv all_letters.json ../assets/data/data.json

# Produce the path-based data-v2.json that current app builds read (old builds
# keep reading the full-URL data.json). Raises if any video moved hosts.
python make_data_v2.py

date +%s > ../assets/data/latest_version
