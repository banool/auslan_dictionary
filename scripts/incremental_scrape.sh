#!/bin/bash

# Scrapes the signbank one letter at a time with automatic resume support.
#
# Usage:
#   ./incremental_scrape.sh              # Start fresh or resume from last checkpoint
#   ./incremental_scrape.sh --fresh      # Force a fresh start (ignore any existing progress)
#   ./incremental_scrape.sh --from d     # Start/resume from letter 'd'
#   ./incremental_scrape.sh --validate   # Also validate video URLs with OPTIONS requests
#
# The script automatically saves progress after each letter, so if it crashes
# or you need to stop it, you can just run it again to resume.

if [ -z "$UV" ]; then
    echo "ERROR: Run this with uv."
    exit 1
fi

set -e

cd "$(dirname "$0")"

# Parse arguments.
FRESH=false
START_FROM=""
VALIDATE_FLAG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --fresh)
            FRESH=true
            shift
            ;;
        --from)
            START_FROM="$2"
            shift 2
            ;;
        --validate)
            VALIDATE_FLAG="--validate-video-urls"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--fresh] [--from LETTER] [--validate]"
            exit 1
            ;;
    esac
done

# State file tracks which letters we've completed.
STATE_FILE="scrape_state.txt"
PROGRESS_FILE="scrape_progress.json"

# Initialize state.
if [ "$FRESH" = true ] || [ ! -f "$STATE_FILE" ]; then
    echo "Starting fresh scrape..."
    cp ../assets/data/data.json "$PROGRESS_FILE"
    rm -f "$STATE_FILE"
    touch "$STATE_FILE"
else
    echo "Resuming from previous state..."
    if [ ! -f "$PROGRESS_FILE" ]; then
        echo "Warning: State file exists but progress file is missing. Starting fresh."
        cp ../assets/data/data.json "$PROGRESS_FILE"
        rm -f "$STATE_FILE"
        touch "$STATE_FILE"
    fi
fi

# Determine which letters have already been completed.
COMPLETED_LETTERS=$(cat "$STATE_FILE" 2>/dev/null | tr '\n' ' ')
echo "Already completed letters: ${COMPLETED_LETTERS:-none}"

# Track statistics.
TOTAL_SUCCESS=0
TOTAL_FAILED=0
FAILED_LETTERS=""

for l in {a..z}; do
    # Skip if we should start from a specific letter.
    if [ -n "$START_FROM" ] && [[ "$l" < "$START_FROM" ]]; then
        echo "Skipping letter $l (starting from $START_FROM)"
        continue
    fi

    # Skip if already completed (unless --from was specified, which overrides).
    if [ -z "$START_FROM" ] && grep -q "^${l}$" "$STATE_FILE" 2>/dev/null; then
        echo "Skipping letter $l (already completed)"
        continue
    fi

    echo ""
    echo "========================================"
    echo "Processing letter: $l"
    echo "========================================"

    # Try up to 3 times for each letter.
    SUCCESS=false
    for attempt in 1 2 3; do
        echo "Attempt $attempt for letter $l..."

        if python scrape_signbank.py -d \
            --output-file "next_${l}.json" \
            --existing-file "$PROGRESS_FILE" \
            --letters "$l" \
            --categories-file ../assets/data/categories.json \
            $VALIDATE_FLAG; then

            # Success - update progress file and state.
            mv "next_${l}.json" "$PROGRESS_FILE"
            echo "$l" >> "$STATE_FILE"
            echo "Successfully scraped letter $l"
            SUCCESS=true
            TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
            break
        else
            echo "Attempt $attempt failed for letter $l"
            rm -f "next_${l}.json"

            if [ $attempt -lt 3 ]; then
                echo "Waiting 30 seconds before retry..."
                sleep 30
            fi
        fi
    done

    if [ "$SUCCESS" = false ]; then
        echo "WARNING: All attempts failed for letter $l, continuing to next letter..."
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        FAILED_LETTERS="${FAILED_LETTERS} $l"
    fi
done

echo ""
echo "========================================"
echo "Scraping complete!"
echo "========================================"
echo "Successful letters: $TOTAL_SUCCESS"
echo "Failed letters: $TOTAL_FAILED"

if [ -n "$FAILED_LETTERS" ]; then
    echo "Letters that failed:$FAILED_LETTERS"
    echo ""
    echo "You can retry failed letters with:"
    echo "  uv run ./incremental_scrape.sh --from <letter>"
fi

# Copy final result to expected output file.
cp "$PROGRESS_FILE" all_letters.json

echo ""
echo "Output written to all_letters.json"
echo "If everything looks good, run: ./move_data.sh"
