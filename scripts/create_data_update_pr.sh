#!/bin/bash

set +e

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

# Delete PR and branch if it already exists.
existingpr=`gh pr list --label data_update --json number | jq -r .[0]`
if [ "$existingpr" != "null" ]; then
    gh pr close $existingpr -d 
fi

# Switch to a new branch.
git checkout -b update_data

# Scrape for new data.
scripts/incremental_scrape.sh

# Move data into place.
scripts/move_data.sh

# Create and push the commit.
git add -A
git commit -m "Update signbank data"
git push --set-upstream origin update_data

# Make a PR with the commit.
gh pr create --fill --label data_update

# Switch back to master.
git checkout master

# Delete branch.
git branch -d update_data

echo 'Done!'
