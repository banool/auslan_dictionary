#!/usr/bin/env python3

"""
This script scrapes the Auslan Signbank website and builds up JSON
with this format:

{
    "category": ["word1", "word2", "word3"],
}
"""

import argparse
import asyncio
import json
from concurrent.futures import ThreadPoolExecutor
from typing import Dict, List

from bs4 import BeautifulSoup

from common import LOG, get_pages_html

SITE_ROOT = "http://www.auslan.org.au"
# These should be lower case.
IGNORED_CATEGORY_NAMES = ["all", "metalg", "people"]
# The keys should be lower case.
RENAMED_CATEGORY_NAMES = {
    "animal": "Animals",
    "body part": "Body Parts",
    "utensil": "Utensils",
    "number": "Numbers",
}


def build_category_page_url(category_query: str, page: int) -> str:
    return f"{SITE_ROOT}/dictionary/search/?query=&page={page}&category=semantic:{category_query}"


# Returns a map of category name to query value.
async def get_categories(executor) -> Dict[str, str]:
    html_text = (await get_pages_html(executor, [SITE_ROOT]))[0].text

    # Use BeautifulSoup to parse the HTML content
    soup = BeautifulSoup(html_text, "html.parser")

    # Find the select element by its ID
    category_select = soup.find("select", {"id": "id_menu_category"})

    # Extract options from the select element
    categories = {}
    for option in category_select.find_all("option"):
        category_name = option.text.strip()
        query_value = option["value"].replace("semantic:", "")
        if category_name.lower() in IGNORED_CATEGORY_NAMES:
            continue
        categories[category_name] = query_value

    return categories


# Give this the HTML of the first page in the category.
def get_number_of_pages_in_category(html_text) -> int:
    soup = BeautifulSoup(html_text, "html.parser")

    # Find the correct pagination element
    page_nav = soup.find("nav", {"aria-label": "Page navigation"})
    pagination_ul = page_nav.find("ul", class_="pagination")

    # Extract page numbers from the pagination ul
    # Assuming the last <li> element (before any possible "Next" button) contains the highest page number
    page_numbers = []
    if pagination_ul:
        page_numbers = [
            li.text.strip()
            for li in pagination_ul.find_all("li")
            if li.text.strip().isdigit()
        ]

    # Get the highest page number
    number_of_pages = int(page_numbers[-1]) if page_numbers else 1

    return number_of_pages


def get_words_on_page(html_text) -> List[str]:
    soup = BeautifulSoup(html_text, "html.parser")

    # Find the div that contains the words
    table_responsive_div = soup.find("div", class_="table-responsive")

    # Find all <p> tags within the div to extract words
    words = []
    if table_responsive_div:
        p_tags = table_responsive_div.find_all("p")
        for p in p_tags:
            a_tag = p.find("a")
            if a_tag:
                words.append(a_tag.text.strip())  # Extract the text within the <a> tag

    return words


async def get_words_in_category(executor, category_name, category_query) -> List[str]:
    # Load the first page.
    url = build_category_page_url(category_query, 1)
    html = (await get_pages_html(executor, [url]))[0]

    # Get the number of categories.
    try:
        number_of_pages = get_number_of_pages_in_category(html.text)
    except Exception as e:
        LOG.warning(f"Failed to get number of pages for category {category_name}: {e}")
        number_of_pages = 1

    if number_of_pages == 1:
        LOG.warning(f"Only one page in category {category_name} apparently")
    else:
        LOG.info(f"Category {category_name} has {number_of_pages} pages")

    # Load the rest of the pages.
    urls = [
        build_category_page_url(category_query, page)
        for page in range(2, number_of_pages + 1)
    ]
    htmls = await get_pages_html(executor, urls)
    htmls = [html] + htmls

    words = []
    for html in htmls:
        words.extend(get_words_on_page(html.text))

    return words


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("-d", "--debug", action="store_true")
    parser.add_argument("--categories", nargs="*", help="Fetch only these categories")
    output_args = parser.add_mutually_exclusive_group(required=True)
    output_args.add_argument("--output-file")
    output_args.add_argument("--stdout", action="store_true")
    return parser.parse_args()


async def main():
    args = parse_args()

    if args.debug:
        LOG.setLevel("DEBUG")
    else:
        LOG.setLevel("INFO")

    # We don't use too many thread to make sure we don't get ratelimited.
    executor = ThreadPoolExecutor(max_workers=4)

    if args.categories:
        # We assume the category name and query are the same if --categories is given.
        # This is a bad assumption for some categories, so only use this for testing.
        categories = {c: c for c in args.categories}
    else:
        categories = await get_categories(executor)

    LOG.info(f"Fetching data for these categories: {list(categories.keys())}")

    data = {}
    for category_name, category_query in categories.items():
        words = await get_words_in_category(executor, category_name, category_query)
        category_name = RENAMED_CATEGORY_NAMES.get(category_name.lower(), category_name)
        data[category_name] = words
        LOG.info(f"Found {len(words)} words in category {category_name}")

    # Build and output the JSON.
    json_output = json.dumps(data, indent=4)
    if args.stdout:
        print(json_output)
    else:
        with open(args.output_file, "w") as f:
            f.write(json_output)


def main_wrapper():
    asyncio.run(main())


if __name__ == "__main__":
    main_wrapper()
