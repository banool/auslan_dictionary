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
import json
import logging
import string
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


SITE_ROOT = "http://www.auslan.org.au"
LETTER_PAGE_TEMPLATE = SITE_ROOT + "/dictionary/search/?query={letter}&page={page}"

# Words to ignore because the page isn't actually there.
DENYLIST = [
    r"http://www.auslan.org.au/dictionary/words/at%20last-1.html",
    r"http://www.auslan.org.au/dictionary/words/athletics-1.html",
    r"http://www.auslan.org.au/dictionary/words/blazer-1.html",
    r"http://www.auslan.org.au/dictionary/words/buttons-1.html",
    r"http://www.auslan.org.au/dictionary/words/competed-1.html",
    r"http://www.auslan.org.au/dictionary/words/completion-1.html",
    r"http://www.auslan.org.au/dictionary/words/contiue-1.html",
    r"http://www.auslan.org.au/dictionary/words/continous-1.html",
    r"http://www.auslan.org.au/dictionary/words/coordinate-1.html",
    r"http://www.auslan.org.au/dictionary/words/coordinator-1.html",
    r"http://www.auslan.org.au/dictionary/words/dimension-1.html",
    r"http://www.auslan.org.au/dictionary/words/distance%20(long%20distance)-1.html",
    r"http://www.auslan.org.au/dictionary/words/distant%20(very%20distant)-1.html",
    r"http://www.auslan.org.au/dictionary/words/end-point-1.html",
    r"http://www.auslan.org.au/dictionary/words/far%20(very%20far)-1.html",
    r"http://www.auslan.org.au/dictionary/words/full%20stops-1.html",
    r"http://www.auslan.org.au/dictionary/words/oneself-1.html",
    r"http://www.auslan.org.au/dictionary/words/ongoing-1.html",
    r"http://www.auslan.org.au/dictionary/words/panel-1.html",
    r"http://www.auslan.org.au/dictionary/words/periods%20(full%20stops)-1.html",
    r"http://www.auslan.org.au/dictionary/words/point%20(tip)-1.html",
    r"http://www.auslan.org.au/dictionary/words/points%20(dots)-1.html",
    r"http://www.auslan.org.au/dictionary/words/predominant-1.html",
    r"http://www.auslan.org.au/dictionary/words/ricochet-1.html",
    r"http://www.auslan.org.au/dictionary/words/size%20(in%20height)-1.html",
    r"http://www.auslan.org.au/dictionary/words/size%20(packet)-1.html",
    r"http://www.auslan.org.au/dictionary/words/sprint-1.html",
    r"http://www.auslan.org.au/dictionary/words/specifically-1.html",
    r"http://www.auslan.org.au/dictionary/words/sports%20jacket-1.html",
    r"http://www.auslan.org.au/dictionary/words/sports%20coat-1.html",
]


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
    urls_args = parser.add_mutually_exclusive_group()
    urls_args.add_argument("--urls", nargs="*", help="Specific URLs to look at")
    urls_args.add_argument("--urls-file", help="File containing specific URLs to look at")
    parser.add_argument("--letters", nargs="*", help="Fetch only these letters")
    output_args = parser.add_mutually_exclusive_group(required=True)
    output_args.add_argument("--output-file")
    output_args.add_argument("--stdout", action="store_true")
    return parser.parse_args()


def load_url(url, timeout=180):
    LOG.debug(f"Getting HTML for URL: {url}")
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
    urls = [u for u in urls if u not in DENYLIST]
    LOG.debug(f"Getting HTML for these URLs: {urls}")
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
        if not span.next_sibling:
            continue
        definition = span.next_sibling.lstrip().rstrip()
        definitions.append(definition)

    return {heading: definitions}


def parse_information(html) -> Word:
    """
    Returns a tuple of the word and the info for the word.
    """
    soup = BeautifulSoup(html.text, "html.parser")

    # Get the word
    word = soup.find_all("em")[0].string

    # Get the keywords
    keywords_div = soup.find("div", {"id": "keywords"})
    keywords_lines = [l.lstrip() for l in keywords_div.text.split("\n")][4:]
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

    executor = ThreadPoolExecutor(max_workers=32)

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
