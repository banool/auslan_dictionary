#!/usr/bin/env python3

"""
This script scrapes the Auslan Signbank website and builds up JSON
with this format:
{
    "word": {
        video_links: ["link1", "link2"],
        keywords: ["keyword1", "keyword2"],
        definitions: {
            "heading1": [
                "subdefintion1",
                "subdefinition2",
            ],
            "heading2": [
                "subdefintion1",
                "subdefinition2",
            ],
        }
    },
}
"""

import argparse
import asyncio
import logging
import json
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from typing import Dict, List, Tuple

import requests
from bs4 import BeautifulSoup


LOG = logging.getLogger(__name__)
formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
ch = logging.StreamHandler()
ch.setFormatter(formatter)
LOG.addHandler(ch)


@dataclass
class Word:
    word: str
    keywords: List[str]
    video_links: List[str]
    definitions: List[Dict[str, List[str]]]

    def get_dict(self):
        return {
            self.word: {
                "video_links": self.video_links,
                "keywords": self.keywords,
                "definitions": self.definitions,
            }
        }


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("-d", "--debug", action="store_true")
    parser.add_argument("--urls", nargs="*", help="Specific URLs to look at")
    output_args = parser.add_mutually_exclusive_group(required=True)
    output_args.add_argument("--output-file")
    output_args.add_argument("--stdout", action="store_true")
    return parser.parse_args()


def load_url(url, timeout=15):
    return requests.get(url, timeout=timeout)


async def get_word_page_urls(executor) -> List[str]:
    """
    Scanning through all of the per-letter pages, get links to
    all the pages for each of the words.
    """
    return []


async def get_pages_html(executor, urls: List[str]) -> List[str]:
    """
    Get the HTML of a list of URLs. If getting the HTML of any URL fails,
    this function will throw an exception.
    """
    loop = asyncio.get_running_loop()
    futures = [loop.run_in_executor(executor, load_url, url) for url in urls]
    return await asyncio.gather(*futures)


def parse_definition(definition_div_html) -> Dict[str, List[str]]:
    """
    Given one definition div, return the heading of the div, e.g. "As Verb",
    and return a list of dict of heading -> a list of definitions under that heading.
    """
    heading = definition_div_html.find("h3").text

    definitions = []
    for span in definition_div_html.find_all("span"):
        definition = span.next_sibling.lstrip().rstrip()
        definitions.append(definition)

    return {heading: definitions}


def parse_information(html) -> Word:
    """
    Returns a tuple of the word and the info for the word.
    """
    soup = BeautifulSoup(html.text, 'html.parser')

    # Get the word
    word = soup.find_all("em")[0].string

    # Get the keywords
    keywords_div = soup.find("div", {"id": "keywords"})
    keywords_lines = [l.lstrip() for l in keywords_div.text.split('\n')][4:]
    keywords = [k.rstrip(",") for k in keywords_lines if k]

    # Get the video links
    video_links = [t["src"] for t in soup.find_all("source")]

    # Get the definitions
    definition_divs_html = soup.find_all("div", {"class": "definition-panel"})
    definitions = []
    for definition_div_html in definition_divs_html:
        definitions.append(parse_definition(definition_div_html))

    return Word(
        word=word,
        keywords=keywords,
        video_links=video_links,
        definitions=definitions,
    )


async def main():
    args = parse_args()

    if args.debug:
        LOG.setLevel("DEBUG")
    else:
        LOG.setLevel("INFO")

    executor = ThreadPoolExecutor(max_workers=16)

    # Get the URLs for all the word pages.
    if args.urls:
        urls = args.urls
    else:
        urls = await get_word_page_urls(executor)

    # Get the HTML for each of the word pages.
    word_pages_html = await get_pages_html(executor, urls)

    # Parse the information in each of the pages.
    word_to_info = {}
    for html in word_pages_html:
        word = parse_information(html)
        word_dict = word.get_dict()
        word_to_info.update(word_dict)

    LOG.debug(word_to_info)

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
