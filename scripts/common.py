import asyncio
import logging
from typing import Dict, List, Tuple

import requests
from retry import retry

LOG = logging.getLogger(__name__)
formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
ch = logging.StreamHandler()
ch.setFormatter(formatter)
LOG.addHandler(ch)


@retry(RuntimeError, delay=2, backoff=4, tries=5)
def load_url(url, timeout=180):
    LOG.debug(f"Getting HTML for URL: {url}")
    response = requests.get(url, timeout=timeout)
    if response.status_code != 200:
        raise RuntimeError(f"Got status code {response.status_code} for {url}")
    return response


async def get_pages_html(executor, urls: List[str]) -> List[str]:
    """
    Get the HTML of a list of URLs. If getting the HTML of any URL fails,
    this function will throw an exception.
    """
    # LOG.debug(f"Getting HTML for these URLs: {urls}")
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
