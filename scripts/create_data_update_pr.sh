#!/bin/bash

set -x
set -e

# Putting ||: at the end of a command means the script won't abort if that one
# command fails.

# Generate a unique branch name with timestamp.
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BRANCH_NAME="update_data_${TIMESTAMP}"

onexit() {
    # Switch back to master.
    git checkout master
}

if [ -z "$UV" ]
then
    echo "ERROR: Run this with uv."
    exit 1
fi

cd "$(dirname "$0")"

# Go to top level directory.
cd ..

# Forcibly make repo match remote.
git fetch
git reset --hard origin/master
git checkout master

# Switch to a new branch with timestamp.
git checkout -b "$BRANCH_NAME"

# Scrape for new data.
scripts/scrape.sh

# Exit if nothing changed.
if diff scripts/all_letters.json assets/data/data.json > /dev/null; then
    echo "No new data, exiting..."
    onexit
    exit 0
fi

# Move data into place.
scripts/move_data.sh

# Create and push the commit.
git add -A
git commit -m "Update signbank data (${TIMESTAMP})"
git push --set-upstream origin "$BRANCH_NAME"

# Make a PR with the commit.
gh pr create --fill --label data_update

onexit

echo 'Done!'
