import asyncio
import logging
import time
from typing import List, Optional

import requests
from retry import retry

LOG = logging.getLogger(__name__)
formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
ch = logging.StreamHandler()
ch.setFormatter(formatter)
LOG.addHandler(ch)

# Default timeout for HTTP requests.
DEFAULT_TIMEOUT = 180

# Rate limiting settings.
MIN_REQUEST_INTERVAL = 0.1  # Minimum seconds between requests.
_last_request_time = 0


def _rate_limit():
    """Simple rate limiting to avoid overwhelming the server."""
    global _last_request_time
    now = time.time()
    elapsed = now - _last_request_time
    if elapsed < MIN_REQUEST_INTERVAL:
        time.sleep(MIN_REQUEST_INTERVAL - elapsed)
    _last_request_time = time.time()


def check_video_url_exists(url: str, timeout: int = 30) -> bool:
    """
    Check if a video URL is valid by making an OPTIONS request.
    Returns True if the URL returns 200, False otherwise.
    """
    try:
        LOG.debug(f"Checking video URL with OPTIONS: {url}")
        _rate_limit()
        response = requests.options(url, timeout=timeout)
        if response.status_code == 200:
            return True
        else:
            LOG.warning(f"Video URL returned {response.status_code}, skipping: {url}")
            return False
    except requests.exceptions.Timeout:
        LOG.warning(f"Timeout validating video URL, skipping: {url}")
        return False
    except requests.exceptions.ConnectionError as e:
        LOG.warning(f"Connection error validating video URL, skipping: {url} - {e}")
        return False
    except Exception as e:
        LOG.warning(f"Unexpected error validating video URL, skipping: {url} - {e}")
        return False


async def validate_video_urls(executor, urls: List[str]) -> List[str]:
    """
    Validate a list of video URLs using OPTIONS requests.
    Returns only the URLs that return 200.
    """
    if not urls:
        return []

    loop = asyncio.get_running_loop()
    futures = [loop.run_in_executor(executor, check_video_url_exists, url) for url in urls]
    results = await asyncio.gather(*futures, return_exceptions=True)

    valid_urls = []
    for url, result in zip(urls, results):
        if isinstance(result, Exception):
            LOG.warning(f"Exception validating video URL, skipping: {url} - {result}")
            continue
        if result:
            valid_urls.append(url)

    return valid_urls


@retry(
    exceptions=(requests.exceptions.RequestException, RuntimeError),
    delay=2,
    backoff=2,
    tries=4,
    logger=LOG,
)
def load_url(url: str, timeout: int = DEFAULT_TIMEOUT) -> requests.Response:
    """
    Load a URL with retry logic.
    Raises RuntimeError on non-200 status codes after retries are exhausted.
    """
    LOG.debug(f"Getting HTML for URL: {url}")
    _rate_limit()
    response = requests.get(url, timeout=timeout)
    if response.status_code != 200:
        raise RuntimeError(f"Got status code {response.status_code} for {url}")
    return response


def load_url_safe(url: str, timeout: int = DEFAULT_TIMEOUT) -> Optional[requests.Response]:
    """
    Load a URL, returning None instead of raising on failure.
    Useful when you want to continue processing even if some URLs fail.
    """
    try:
        return load_url(url, timeout)
    except Exception as e:
        LOG.warning(f"Failed to load URL {url}: {e}")
        return None


async def get_pages_html(
    executor,
    urls: List[str],
    continue_on_error: bool = True,
) -> List[requests.Response]:
    """
    Get the HTML of a list of URLs concurrently.

    Args:
        executor: ThreadPoolExecutor for running requests.
        urls: List of URLs to fetch.
        continue_on_error: If True, continue processing even if some URLs fail.
                          If False, raise on first failure.

    Returns:
        List of successful responses. Failed URLs are logged as warnings.
    """
    loop = asyncio.get_running_loop()
    futures = [loop.run_in_executor(executor, load_url_safe if continue_on_error else load_url, url) for url in urls]
    results = await asyncio.gather(*futures, return_exceptions=True)

    htmls = []
    failed = []

    for url, result in zip(urls, results):
        if isinstance(result, Exception):
            LOG.warning(f"Failed to get page {url}: {result}")
            failed.append(url)
        elif result is None:
            # load_url_safe returned None.
            failed.append(url)
        else:
            htmls.append(result)

    if failed:
        LOG.info(f"Failed to fetch {len(failed)} out of {len(urls)} URLs")
        for url in failed[:10]:  # Only show first 10.
            LOG.debug(f"  Failed: {url}")
        if len(failed) > 10:
            LOG.debug(f"  ... and {len(failed) - 10} more")

    return htmls


async def get_pages_html_with_urls(
    executor,
    urls: List[str],
) -> List[tuple]:
    """
    Get the HTML of a list of URLs, returning tuples of (url, response).
    This is useful when you need to know which URL each response came from.

    Returns:
        List of (url, response) tuples for successful fetches.
    """
    loop = asyncio.get_running_loop()
    futures = [loop.run_in_executor(executor, load_url_safe, url) for url in urls]
    results = await asyncio.gather(*futures, return_exceptions=True)

    successful = []
    for url, result in zip(urls, results):
        if isinstance(result, Exception):
            LOG.warning(f"Failed to get page {url}: {result}")
        elif result is None:
            LOG.warning(f"Failed to get page {url}")
        else:
            successful.append((url, result))

    return successful
