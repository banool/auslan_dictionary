#!/usr/bin/env python3

"""
This script scrapes the Auslan Signbank website and builds up JSON
with this format:

{
    "word": [
        {
            video_links: ["link1", "link2"],
            keywords: ["keyword1", "keyword2"],
            regions: ["northern", "qld", "nsw", "act"],
            definitions: {
                "heading1": [
                    "subdefintion1",
                    "subdefinition2",
                ],
                "heading2": [
                    "subdefintion1",
                    "subdefinition2",
                ],
            },
        ],
    },
}

Note: For a single entry, there can be multiple sub entries. This means
the entry will have multiple sub entries that each might have multiple
videos, their own definitions, and so on.
"""

import argparse
import asyncio
import json
import string
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from enum import IntEnum
from typing import Dict, List, Tuple

from bs4 import BeautifulSoup

from common import LOG, get_pages_html

SITE_ROOT = "http://www.auslan.org.au"
LETTER_PAGE_TEMPLATE = SITE_ROOT + "/dictionary/search/?query={letter}&page={page}"

# Words to ignore because the page isn't actually there.
WORDS_PAGE_BASE = r"http://www.auslan.org.au/dictionary/words/"


# IMPORTANT:
# Keep this in sync with lib/types.dart, the indexes must line up.
class Region(IntEnum):
    EVERYWHERE = 0
    SOUTHERN = 1
    NORTHERN = 2
    WA = 3
    NT = 4
    SA = 5
    QLD = 6
    NSW = 7
    ACT = 8
    VIC = 9
    TAS = 10

    @classmethod
    def regions_from_link(cls, link):
        d = {
            "/img/maps/Auslan/AustraliaWide-traditional": [e.value for e in cls],
            "/img/maps/Auslan/SouthernDialect-traditional": [
                cls.SOUTHERN,
                cls.WA,
                cls.NT,
                cls.SA,
                cls.VIC,
                cls.TAS,
            ],
            "/img/maps/Auslan/NorthernDialect-traditional": [
                cls.NORTHERN,
                cls.QLD,
                cls.NSW,
                cls.ACT,
            ],
            "/img/maps/Auslan/WesternAustralia-traditional": [cls.WA],
            "/img/maps/Auslan/NorthernTerritory-traditional": [cls.NT],
            "/img/maps/Auslan/SouthAustralia-traditional": [cls.SA],
            "/img/maps/Auslan/Queensland-traditional": [cls.QLD],
            "/img/maps/Auslan/NewSouthWales-traditional": [cls.NSW, cls.ACT],
            "/img/maps/Auslan/Victoria-traditional": [cls.VIC],
            "/img/maps/Auslan/Tasmania-traditional": [cls.TAS],
        }
        updated = {}
        for k, v in d.items():
            updated[k] = v
            updated["/static" + k] = v
        regions = None
        for link_substring in updated.keys():
            if link_substring in link:
                return d[link_substring]
        return regions


@dataclass
class Entry:
    entry_in_english: str
    sub_entries: List["SubEntry"]
    categories: List[str]
    entry_type: str = "WORD"  # They're all words for now.

    # We return the dict inside another dict keyed by entry_in_english. Later on we'll
    # collapse this into a list of dicts but for now this helps when we're starting
    # with existing data.
    def get_dict(self):
        sub_entries = [sw.get_dict() for sw in self.sub_entries]
        return {
            self.entry_in_english: {
                "entry_in_english": self.entry_in_english,
                "sub_entries": sub_entries,
                "categories": self.categories,
                "entry_type": self.entry_type,
            },
        }


@dataclass
class SubEntry:
    video_links: List[str]
    keywords: List[str]
    definitions: Dict[str, List[str]]
    regions: List[str]

    def get_dict(self):
        return {
            "video_links": self.video_links,
            "keywords": self.keywords,
            "definitions": self.definitions,
            "regions": self.regions,
        }


async def get_word_page_urls(executor, letters=None) -> List[str]:
    """
    This scrapes the site pretty much like this:

    words_urls = []
    for letter:
        for results_page in letter:
            for word_url in results_page:
                words_urls.append(word_url)
    """

    letters = letters or string.ascii_lowercase

    # Get the HTML for the first page of each letter.
    first_letter_pages_urls = [
        LETTER_PAGE_TEMPLATE.format(letter=letter, page=1) for letter in letters
    ]
    first_letter_pages_html = await get_pages_html(executor, first_letter_pages_urls)

    # Count how many pages there are for each letter.
    letters_to_num_pages = {}
    for idx, html in enumerate(first_letter_pages_html):
        letter = letters[idx]

        soup = BeautifulSoup(html.text, "html.parser")
        pages_list = soup.find_all("ul")[-1]
        last_pages_button = pages_list.find_all("li")[-1]
        try:
            num_pages = int(last_pages_button.text)
        except ValueError:
            LOG.debug(f"Only one page for letter {letter}")
            num_pages = 1

        letters_to_num_pages[letter] = num_pages

    # Get the URLs for all of the letter pages.
    other_letter_pages_urls = []
    for letter in letters:
        num_pages = letters_to_num_pages[letter]
        for page in range(2, num_pages + 1):
            url = LETTER_PAGE_TEMPLATE.format(letter=letter, page=page)
            other_letter_pages_urls.append(url)

    # Get the HTML for all of the letter pages.
    letter_pages_html = first_letter_pages_html
    other_letter_pages_html = await get_pages_html(executor, other_letter_pages_urls)
    letter_pages_html += other_letter_pages_html

    # Get the word URLs from all the letter pages' HTML.
    word_page_urls = []
    for html in letter_pages_html:
        soup = BeautifulSoup(html.text, "html.parser")
        url_suffixes = [
            u["href"] for u in soup.find_all("a") if "dictionary/words/" in u["href"]
        ]
        full_urls = [SITE_ROOT + u for u in url_suffixes]
        word_page_urls += full_urls

    return word_page_urls


def parse_definition(definition_div_html) -> Dict[str, List[str]]:
    """
    Given one definition div, return the heading of the div, e.g. "As Verb",
    and return a list of dict of heading -> a list of definitions under that heading.
    """
    heading = definition_div_html.find("h3").text

    definitions = []
    for span in definition_div_html.find_all("span"):
        if not span.next_sibling:
            continue
        definition = span.next_sibling.lstrip().rstrip()
        definitions.append(definition)

    return {heading: definitions}


async def parse_information(executor, html) -> Entry:
    soup = BeautifulSoup(html.text, "html.parser")

    # Get the word
    word = soup.find_all("em")[0].string

    # Get the SubWord for this first page
    first_subword = parse_subpage(html, word)
    sub_entries = [first_subword]

    # Get links to the subpages
    subpages_tags = soup.find_all("a", {"class": "btn btn-default navbar-btn"})
    subpages_urls = [WORDS_PAGE_BASE + t["href"] for t in subpages_tags]

    # Fetch their HTML
    # TODO: This part is synchronous and slow, surface this and gather it later.
    if subpages_urls:
        sub_entries_html = await get_pages_html(executor, subpages_urls)
    else:
        sub_entries_html = []

    # Pull subwords information from them
    additional_subwords = [parse_subpage(html, word) for html in sub_entries_html]
    sub_entries += additional_subwords

    return Entry(
        entry_in_english=word,
        sub_entries=sub_entries,
        categories=[],  # We fill this in later.
    )


def parse_subpage(html, word_str) -> SubEntry:
    soup = BeautifulSoup(html.text, "html.parser")

    # Get the keywords
    keywords_div = soup.find("div", {"id": "keywords"})
    keywords_lines = [l.lstrip() for l in keywords_div.text.split("\n")]
    keywords = [k.rstrip(",") for k in keywords_lines if k]
    keywords.remove("Keywords:")
    keywords.remove(word_str)

    # Get the video links
    video_links = [t["src"] for t in soup.find_all("source")]

    # Get the definitions
    definition_divs_html = soup.find_all("div", {"class": "definition-panel"})
    definitions = {}
    for definition_div_html in definition_divs_html:
        definitions.update(parse_definition(definition_div_html))

    # Get the regions image.
    regions_img_tags = soup.find_all("img", {"alt": "Region"})

    try:
        regions_img_link = [
            t["src"] for t in regions_img_tags if "Auslan/" in t["src"]
        ][0]
        try:
            # Derive the regions based on the image.
            regions = Region.regions_from_link(regions_img_link)
            if not regions:
                raise KeyError()
        except KeyError:
            # This implies a new img src.
            LOG.warning(f"Encountered unexpected regions image URL: {regions_img_link}")
            regions = []
    except IndexError:
        # This implies that there is no regions img (which is pretty common), or an issue with the scraper.
        LOG.debug(f"Failed to get regions information for {html.url}")
        regions = []

    return SubEntry(
        video_links=video_links,
        keywords=keywords,
        definitions=definitions,
        regions=regions,
    )


def get_existing_data(filename):
    with open(filename, "r") as f:
        existing_data = json.loads(f.read())
    return existing_data


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("-d", "--debug", action="store_true")
    urls_args = parser.add_mutually_exclusive_group()
    urls_args.add_argument("--urls", nargs="*", help="Specific URLs to look at")
    urls_args.add_argument(
        "--urls-file", help="File containing specific URLs to look at"
    )
    parser.add_argument("--letters", nargs="*", help="Fetch only these letters")
    # This should come from running scrape_categories.py
    parser.add_argument("--categories-file", required=True)
    output_args = parser.add_mutually_exclusive_group(required=True)
    output_args.add_argument("--output-file")
    output_args.add_argument("--stdout", action="store_true")
    parser.add_argument("--existing-file", help="Start with this file as the base")
    return parser.parse_args()


async def main():
    args = parse_args()

    if args.debug:
        LOG.setLevel("DEBUG")
    else:
        LOG.setLevel("INFO")

    # Load up category data.
    category_data = get_existing_data(args.categories_file)
    word_to_categories = {}
    for category, words in category_data.items():
        for word in words:
            if word not in word_to_categories:
                word_to_categories[word] = []
            word_to_categories[word].append(category)

    # Load up data from the existing file if given. We turn the data inside "data" into
    # a dict where the key is entry_in_english.
    if args.existing_file:
        existing_data = get_existing_data(args.existing_file)
        word_to_info = {d["entry_in_english"]: d for d in existing_data["data"]}
    else:
        word_to_info = {}

    if args.existing_file == args.output_file and args.existing_file is not None:
        raise RuntimeError("--existing-file and --output-file cannot be the same file")

    executor = ThreadPoolExecutor(max_workers=4)

    # Get the URLs for all the word pages.
    if args.urls:
        urls = args.urls
    elif args.urls_file:
        with open(args.urls_file, "r") as f:
            urls = f.read().splitlines()
    else:
        urls = await get_word_page_urls(executor, letters=args.letters)

    # Get the HTML for each of the word pages.
    word_pages_html = await get_pages_html(executor, urls)

    # Parse the information in each of the pages.
    for html in word_pages_html:
        try:
            word = await parse_information(executor, html)
        except:
            LOG.error(f"Failed to parse information for {html.url}")
            raise
        word_dict = word.get_dict()
        word_to_info.update(word_dict)

    # Attach category data.
    for word, info in word_to_info.items():
        categories = word_to_categories.get(word, [])
        info["categories"] = categories

    # Flatten the data, structure inside "data".
    out = {"data": list(word_to_info.values())}

    # Build and output the JSON.
    json_output = json.dumps(out, indent=2)
    if args.stdout:
        print(json_output)
    else:
        with open(args.output_file, "w") as f:
            f.write(json_output)


def main_wrapper():
    asyncio.run(main())


if __name__ == "__main__":
    main_wrapper()
