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
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Dict, List, Tuple

from bs4 import BeautifulSoup
from retry import retry

from common import LOG, load_url

SITE_ROOT = "https://www.auslan.org.au"
# These should be lower case.
IGNORED_CATEGORY_NAMES = ["all", "metalg", "people"]
# The keys should be lower case.
RENAMED_CATEGORY_NAMES = {
    "animal": "Animals",
    "body part": "Body Parts",
    "utensil": "Utensils",
    "number": "Numbers",
}

# Historically real Signbank updates only ever remove a couple of words at a
# time (see the history of categories.json), so losses beyond these limits
# almost certainly mean the scrape silently got bad pages rather than the site
# genuinely culling content. --force overrides.
MAX_LOST_WORDS_PER_CATEGORY = 10
MAX_LOST_WORDS_TOTAL = 25

# When a 200 response doesn't parse as a results page we save the body here
# (one file per page, overwritten per attempt) so a persistent failure can be
# diagnosed from the artifacts rather than guessed at.
BAD_PAGES_DIR = Path(__file__).parent / "bad_pages"

# Strings that, when found in a bad response body, identify a known failure
# mode: either we're being blocked, or the site served its soft-404 page (the
# proxy returns "page not found" content with a 200 when the backend hiccups,
# which is exactly what used to silently wipe categories from the output).
SUSPICIOUS_BODY_HINTS = [
    "was not found on the server",
    "captcha",
    "cloudflare",
    "rate limit",
    "too many requests",
    "access denied",
    "blocked",
    "forbidden",
    "unusual traffic",
]


class BadResultsPageError(RuntimeError):
    """The server returned 200 but the body isn't a usable results page.

    Signbank sometimes serves a well-formed page whose result table is empty
    (the search backend hiccups). Such a page is indistinguishable from a
    category with no words, but we only ever request categories the site
    itself lists, so every page we ask for should have at least one word.
    Treating anything else as a retryable error is what stops entire pages or
    whole categories from silently vanishing from the output.
    """


def build_category_page_url(category_query: str, page: int) -> str:
    return f"{SITE_ROOT}/dictionary/search/?query=&page={page}&category=semantic:{category_query}"


def describe_bad_response(response, save_slug: str) -> str:
    """Build a diagnostic string for a 200 response that didn't parse as a
    results page, saving the body for inspection. The goal is that if the
    scraper is being blocked (WAF, captcha, rate limiting, UA filtering), the
    logs say so directly instead of leaving it to be guessed at.
    """
    soup = BeautifulSoup(response.text, "html.parser")
    title = soup.title.text.strip() if soup.title else "<no title>"
    body_lower = response.text.lower()
    hints = [hint for hint in SUSPICIOUS_BODY_HINTS if hint in body_lower]
    headers = {
        k: v
        for k, v in response.headers.items()
        if k.lower()
        in ("server", "content-type", "retry-after", "cf-ray", "cf-mitigated")
    }
    user_agent = response.request.headers.get("User-Agent")

    BAD_PAGES_DIR.mkdir(exist_ok=True)
    save_path = BAD_PAGES_DIR / f"{re.sub(r'[^A-Za-z0-9._-]', '_', save_slug)}.html"
    save_path.write_text(response.text)

    return (
        f"Diagnostics: page title {title!r}, body length "
        f"{len(response.text)}, suspicious phrases in body {hints or 'none'}, "
        f"response headers {headers}, our user agent {user_agent!r}, body "
        f"saved to {save_path}"
    )


# Returns a map of category name to query value.
@retry(
    exceptions=BadResultsPageError,
    delay=2,
    backoff=2,
    max_delay=120,
    tries=12,
    logger=LOG,
)
def load_categories() -> Dict[str, str]:
    response = load_url(SITE_ROOT)

    # Use BeautifulSoup to parse the HTML content
    soup = BeautifulSoup(response.text, "html.parser")

    # Find the select element by its ID
    category_select = soup.find("select", {"id": "id_menu_category"})
    if category_select is None:
        raise BadResultsPageError(
            f"No category dropdown found on the home page {SITE_ROOT}. "
            + describe_bad_response(response, "home")
        )

    # Extract options from the select element
    categories = {}
    for option in category_select.find_all("option"):
        category_name = option.text.strip()
        query_value = option["value"].replace("semantic:", "")
        if category_name.lower() in IGNORED_CATEGORY_NAMES:
            continue
        categories[category_name] = query_value

    if not categories:
        raise BadResultsPageError(
            "The category dropdown had no options. "
            + describe_bad_response(response, "home")
        )

    return categories


def parse_results_page(html_text: str) -> Tuple[List[str], int]:
    """Parse one search results page, returning the words on it and the total
    number of pages in the category. Raises BadResultsPageError if the page
    doesn't look like a real, non-empty results page.
    """
    soup = BeautifulSoup(html_text, "html.parser")

    # Find the div that contains the words and extract the text within each
    # word link.
    table_responsive_div = soup.find("div", class_="table-responsive")
    if table_responsive_div is None:
        raise BadResultsPageError("No results table found on the page")

    words = []
    for p in table_responsive_div.find_all("p"):
        a_tag = p.find("a")
        if a_tag:
            words.append(a_tag.text.strip())

    if not words:
        raise BadResultsPageError("The results table on the page was empty")

    # Categories with a single page of results have no pagination nav at all.
    page_nav = soup.find("nav", {"aria-label": "Page navigation"})
    if page_nav is None:
        return words, 1

    # The last numeric <li> in the pagination ul is the highest page number.
    pagination_ul = page_nav.find("ul", class_="pagination")
    page_numbers = []
    if pagination_ul:
        page_numbers = [
            li.text.strip()
            for li in pagination_ul.find_all("li")
            if li.text.strip().isdigit()
        ]
    if not page_numbers:
        raise BadResultsPageError(
            "A pagination nav was present but no page numbers were found in it"
        )

    return words, int(page_numbers[-1])


@retry(
    exceptions=BadResultsPageError,
    delay=2,
    backoff=2,
    max_delay=120,
    tries=12,
    logger=LOG,
)
def load_category_page(category_query: str, page: int) -> Tuple[List[str], int]:
    """Fetch and parse one page of a category's results, retrying if the
    server returns a page that doesn't parse as a non-empty results page.
    Note: load_url already retries network errors / non-200s internally.
    """
    url = build_category_page_url(category_query, page)
    response = load_url(url)
    try:
        return parse_results_page(response.text)
    except BadResultsPageError as e:
        raise BadResultsPageError(
            f"{url}: {e}. "
            + describe_bad_response(response, f"{category_query}_page_{page}")
        ) from e


async def get_words_in_category(executor, category_name, category_query) -> List[str]:
    loop = asyncio.get_running_loop()

    # Load the first page, which also tells us the total number of pages.
    words, number_of_pages = await loop.run_in_executor(
        executor, load_category_page, category_query, 1
    )
    LOG.info(f"Category {category_name} has {number_of_pages} page(s)")

    # Load the rest of the pages. If any page keeps coming back bad after
    # retries this raises, aborting the whole scrape: better no output than
    # output with chunks of categories silently missing.
    futures = [
        loop.run_in_executor(executor, load_category_page, category_query, page)
        for page in range(2, number_of_pages + 1)
    ]
    for page_words, _ in await asyncio.gather(*futures):
        words.extend(page_words)

    return words


def load_existing_data(path: str):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return None


def log_diff_summary(old_data: Dict[str, List[str]], new_data: Dict[str, List[str]]):
    for category in sorted(set(old_data) | set(new_data)):
        old_words = set(old_data.get(category, []))
        new_words = set(new_data.get(category, []))
        added = len(new_words - old_words)
        removed = len(old_words - new_words)
        if added or removed:
            LOG.info(f"Category {category}: +{added} -{removed} words")


def find_data_loss(
    old_data: Dict[str, List[str]], new_data: Dict[str, List[str]]
) -> List[str]:
    """Compare freshly scraped data against the previous output and describe
    any losses large enough to suggest the scrape quietly got bad pages."""
    problems = []
    total_lost = 0
    for category, old_words in old_data.items():
        new_words = new_data.get(category)
        if new_words is None:
            problems.append(
                f"Category {category!r} ({len(old_words)} words) is missing "
                f"from the new data"
            )
            continue
        lost = sorted(set(old_words) - set(new_words))
        total_lost += len(lost)
        if len(lost) > MAX_LOST_WORDS_PER_CATEGORY:
            problems.append(
                f"Category {category!r} lost {len(lost)} of {len(old_words)} "
                f"words, e.g. {lost[:5]}"
            )
    if total_lost > MAX_LOST_WORDS_TOTAL:
        problems.append(f"{total_lost} words were lost across all categories")
    return problems


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("-d", "--debug", action="store_true")
    parser.add_argument("--categories", nargs="*", help="Fetch only these categories")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Write the output even if it lost suspiciously many words "
        "compared to the existing output file",
    )
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
    loop = asyncio.get_running_loop()

    if args.categories:
        # We assume the category name and query are the same if --categories is given.
        # This is a bad assumption for some categories, so only use this for testing.
        categories = {c: c for c in args.categories}
    else:
        categories = await loop.run_in_executor(executor, load_categories)

    LOG.info(f"Fetching data for these categories: {list(categories.keys())}")

    data = {}
    for category_name, category_query in categories.items():
        words = await get_words_in_category(executor, category_name, category_query)
        category_name = RENAMED_CATEGORY_NAMES.get(category_name.lower(), category_name)
        data[category_name] = words
        LOG.info(f"Found {len(words)} words in category {category_name}")

    # Guard against writing output that silently lost data. Only applies to a
    # full scrape over an existing output file; --categories is a test mode.
    if args.output_file and not args.categories:
        old_data = load_existing_data(args.output_file)
        if old_data is not None:
            log_diff_summary(old_data, data)
            problems = find_data_loss(old_data, data)
            if problems:
                for problem in problems:
                    LOG.error(problem)
                if args.force:
                    LOG.warning("--force given, writing the output anyway")
                else:
                    LOG.error(
                        "This much data loss usually means the scrape got bad "
                        "pages rather than Signbank genuinely removing "
                        "content. If the removals are real (check the site), "
                        "re-run with --force."
                    )
                    sys.exit(1)

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
