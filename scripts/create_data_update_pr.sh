#!/bin/bash

set -e

# Putting ||: at the end of a command means the script won't abort if that one
# command fails.

onexit() {
    # Switch back to master.
    git checkout master

    # Delete branch.
    git branch -D update_data ||:
}

if [ -z "$PIP_PYTHON_PATH" ]
then
    echo "ERROR: Run this from within the pipenv."
    exit 1
fi

cd "$(dirname "$0")"

# Go to top level directory.
cd ..

# Forcibly make repo match remote.
git fetch
git reset --hard origin/master
git checkout master

# Delete PR if it already exists.
existingpr=`gh pr list --label data_update --json number | jq -r .[0].number`
if [ "$existingpr" != "null" ]; then
    gh pr close $existingpr -d 
fi

# Delete branch if it already exists.
git push -d origin update_data ||:
git branch -D update_data ||:

# Switch to a new branch.
git checkout -b update_data

# Scrape for new data.
scripts/incremental_scrape.sh

# Exit if nothing changed.
if diff all_letters.json ../assets/data/words_latest.json > /dev/null; then
    echo "No new data, exiting..."
    onexit
    exit 1
fi

# Move data into place.
scripts/move_data.sh

# Bump version number.
./bump_version.sh

# Create and push the commit.
git add -A
git commit -m "Update signbank data"
git push --set-upstream origin update_data

# Make a PR with the commit.
gh pr create --fill --label data_update

onexit

echo 'Done!'
