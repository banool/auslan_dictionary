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

Note: For a single word, there can be multiple entries. This means
the word will have multiple "subwords" that each might have multiple
videos, their own defitions, and so on.
"""

import argparse
import asyncio
import json
import logging
import string
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from enum import IntEnum
from typing import Dict, List, Tuple

import requests
from bs4 import BeautifulSoup
from retry import retry

LOG = logging.getLogger(__name__)
formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
ch = logging.StreamHandler()
ch.setFormatter(formatter)
LOG.addHandler(ch)


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
                cls.ACT
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
                regions = d[link_substring]
        return regions


@dataclass
class Word:
    word: str
    subwords: List["SubWord"]

    def get_dict(self):
        return {
            self.word: [sw.get_dict() for sw in self.subwords],
        }


@dataclass
class SubWord:
    keywords: List[str]
    video_links: List[str]
    definitions: Dict[str, List[str]]
    regions: List[str]

    def get_dict(self):
        return {
            "video_links": self.video_links,
            "keywords": self.keywords,
            "definitions": self.definitions,
            "regions": self.regions,
        }


@retry(RuntimeError, delay=1, backoff=3, tries=5)
def load_url(url, timeout=180):
    # LOG.debug(f"Getting HTML for URL: {url}")
    response = requests.get(url, timeout=timeout)
    if response.status_code != 200:
        raise RuntimeError(f"Got status code {response.status_code} for {url}")
    return response


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


async def get_pages_html(executor, urls: List[str]) -> List[str]:
    """
    Get the HTML of a list of URLs. If getting the HTML of any URL fails,
    this function will throw an exception.
    """
    LOG.debug(f"Getting HTML for these URLs: {urls}")
    loop = asyncio.get_running_loop()
    futures = [loop.run_in_executor(executor, load_url, url) for url in urls]
    html_or_exceptions = await asyncio.gather(*futures, return_exceptions=True)
    htmls = []
    failed = []
    for result in html_or_exceptions:
        if isinstance(result, Exception):
            LOG.warning(f"Failed to get a page: {result}")
            failed.append(result)
            continue
        htmls.append(result)
    if failed:
        LOG.debug("Pages we failed to get")
        for fa in failed:
            LOG.debug(f"Failed to get: {fa}")
    return htmls


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


async def parse_information(executor, html) -> Word:
    """
    Returns a tuple of the word and the info for the word.
    """
    soup = BeautifulSoup(html.text, "html.parser")

    # Get the word
    word = soup.find_all("em")[0].string

    # Get the SubWord for this first page
    first_subword = parse_subpage(html, word)
    subwords = [first_subword]

    # Get links to the subpages
    subpages_tags = soup.find_all("a", {"class": "btn btn-default navbar-btn"})
    subpages_urls = [WORDS_PAGE_BASE + t["href"] for t in subpages_tags]

    # Fetch their HTML
    # TODO: This part is synchronous and slow, surface this and gather it later.
    if subpages_urls:
        subwords_html = await get_pages_html(executor, subpages_urls)
    else:
        subwords_html = []

    # Pull subwords information from them
    additional_subwords = [parse_subpage(html, word) for html in subwords_html]
    subwords += additional_subwords

    return Word(
        word=word,
        subwords=subwords,
    )


def parse_subpage(html, word_str) -> SubWord:
    soup = BeautifulSoup(html.text, "html.parser")

    # Get the keywords
    keywords_div = soup.find("div", {"id": "keywords"})
    keywords_lines = [l.lstrip() for l in keywords_div.text.split("\n")]
    keywords = [k.rstrip(",") for k in keywords_lines if k]
    keywords.remove("Keywords:")
    keywords.remove(word_str)

    # Get the video links
    video_links = [t["src"] for t in soup.find_all("source")]

    # Assert that all the videos come from the same URL.
    for l in video_links:
        if not l.startswith("https://media.auslan.org.au"):
            raise RuntimeError(f"Unexpected video source: {l}")

    # Trim the base from the video links
    video_links = [l.split(".org.au/")[1] for l in video_links]

    # Get the definitions
    definition_divs_html = soup.find_all("div", {"class": "definition-panel"})
    definitions = {}
    for definition_div_html in definition_divs_html:
        definitions.update(parse_definition(definition_div_html))

    # Get the regions image.
    regions_img_tags = soup.find_all("img", {"alt": "Region"})

    try:
        regions_img_link = [t["src"] for t in regions_img_tags if "Auslan/" in t["src"]][0]
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
        # This implies that there is no regions img, or an issue with the scraper.
        LOG.warning(f"Failed to get regions information for {html.url}")
        regions = []

    return SubWord(
        keywords=keywords,
        video_links=video_links,
        definitions=definitions,
        regions=regions,
    )


def get_existing_data(filename):
    with open(filename, "r") as f:
        existing_data = json.loads(f.read())
    # LOG.debug(f"Loaded existing data: {existing_data}")
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

    # Load up data from the existing file if given.
    if args.existing_file:
        word_to_info = get_existing_data(args.existing_file)
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
        word = await parse_information(executor, html)
        word_dict = word.get_dict()
        word_to_info.update(word_dict)

    # LOG.debug(word_to_info)

    # Build and output the JSON.
    json_output = json.dumps(word_to_info, indent=4)
    if args.stdout:
        print(json_output)
    else:
        with open(args.output_file, "w") as f:
            f.write(json_output)


def main_wrapper():
    asyncio.run(main())


if __name__ == "__main__":
    main_wrapper()
