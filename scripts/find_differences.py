import json
import sys
import argparse
from typing import Dict, List


def load_json_file(file_path: str) -> Dict:
    """Load and parse a JSON file."""
    try:
        with open(file_path, "r", encoding="utf-8") as file:
            return json.load(file)
    except Exception as e:
        print(f"Error loading file {file_path}: {e}")
        sys.exit(1)


def find_differing_entries(file1: str, file2: str) -> List[Dict]:
    """Find entries with the same English word but different sub-entry data."""
    data1 = load_json_file(file1)
    data2 = load_json_file(file2)

    # Create lookup dictionaries for faster comparison
    entries1 = {entry["entry_in_english"]: entry for entry in data1["data"]}
    entries2 = {entry["entry_in_english"]: entry for entry in data2["data"]}

    # Find common entries with differences
    differing_entries = []

    for english_word, entry1 in entries1.items():
        if english_word in entries2:
            entry2 = entries2[english_word]

            # Skip if they're identical
            if json.dumps(entry1) == json.dumps(entry2):
                continue

            differing_entries.append(english_word)

    return differing_entries


def main():
    parser = argparse.ArgumentParser(
        description="Compare two JSON dictionary files and find differences between entries."
    )
    parser.add_argument("file1", help="Path to the first JSON file")
    parser.add_argument("file2", help="Path to the second JSON file")
    parser.add_argument(
        "--output",
        default="differences_report.json",
        help="Output file path for the differences report (default: differences_report.json)",
    )
    args = parser.parse_args()

    print(f"Comparing entries in {args.file1} and {args.file2}...")
    differing_entries = find_differing_entries(args.file1, args.file2)

    if not differing_entries:
        print("No entries with differences found.")
        return

    print(f"Found {len(differing_entries)} entries with differences:")
    for entry in differing_entries:
        print(entry)


if __name__ == "__main__":
    main()
