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


@retry(
    exceptions=(requests.exceptions.RequestException, RuntimeError),
    delay=1,
    backoff=2,
    max_delay=120,
    tries=10,
    logger=LOG,
)
def _check_video_url_request(url: str, timeout: int) -> int:
    """
    Make an OPTIONS request to check if a video URL exists.
    Returns the status code. Retries on network errors and unexpected status codes.
    Only 200 and 404 are considered final responses; other codes trigger a retry.
    """
    LOG.debug(f"Checking video URL with OPTIONS: {url}")
    _rate_limit()
    response = requests.options(url, timeout=timeout)
    status_code = response.status_code
    # 200 = exists, 404 = doesn't exist. Both are valid final states.
    # Any other status code should trigger a retry.
    if status_code not in (200, 404):
        raise RuntimeError(f"Got unexpected status code {status_code} for {url}")
    return status_code


def check_video_url_exists(url: str, timeout: int = 30) -> bool:
    """
    Check if a video URL is valid by making an OPTIONS request.
    Returns True if the URL returns 200, False if 404.
    Retries with exponential backoff on network errors or unexpected status codes.
    Raises an exception if retries are exhausted for non-404 errors.
    """
    status_code = _check_video_url_request(url, timeout)
    if status_code == 200:
        return True
    else:
        # Must be 404 since _check_video_url_request only returns 200 or 404.
        LOG.info(f"Video URL returned 404, skipping: {url}")
        return False


async def validate_video_urls(executor, urls: List[str]) -> List[str]:
    """
    Validate a list of video URLs using OPTIONS requests.
    Returns only the URLs that return 200.
    URLs that return 404 are considered invalid and skipped.
    Other errors will raise an exception after retries are exhausted.
    """
    if not urls:
        return []

    loop = asyncio.get_running_loop()
    futures = [loop.run_in_executor(executor, check_video_url_exists, url) for url in urls]
    results = await asyncio.gather(*futures, return_exceptions=True)

    valid_urls = []
    for url, result in zip(urls, results):
        if isinstance(result, Exception):
            raise RuntimeError(f"Failed to validate video URL {url} after retries: {result}") from result
        if result:
            valid_urls.append(url)

    return valid_urls


@retry(
    exceptions=(requests.exceptions.RequestException, RuntimeError),
    delay=1,
    backoff=2,
    max_delay=120,
    tries=10,
    logger=LOG,
)
def load_url(url: str, timeout: int = DEFAULT_TIMEOUT) -> requests.Response:
    """
    Load a URL with retry logic.
    Raises RuntimeError on non-200 status codes after retries are exhausted.
    Retries with exponential backoff: 1s, 2s, 4s, 8s, 16s, 32s, 64s, 120s, 120s...
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
    continue_on_error: bool = False,
) -> List[requests.Response]:
    """
    Get the HTML of a list of URLs concurrently.

    Args:
        executor: ThreadPoolExecutor for running requests.
        urls: List of URLs to fetch.
        continue_on_error: If True, continue processing even if some URLs fail.
                          If False (default), raise on first failure after retries exhausted.

    Returns:
        List of successful responses.

    Raises:
        Exception: If continue_on_error is False and any URL fails after retries.
    """
    loop = asyncio.get_running_loop()
    loader = load_url_safe if continue_on_error else load_url
    futures = [loop.run_in_executor(executor, loader, url) for url in urls]
    results = await asyncio.gather(*futures, return_exceptions=True)

    htmls = []
    failed = []

    for url, result in zip(urls, results):
        if isinstance(result, Exception):
            if continue_on_error:
                LOG.warning(f"Failed to get page {url}: {result}")
                failed.append(url)
            else:
                raise RuntimeError(f"Failed to fetch {url} after retries: {result}") from result
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
    continue_on_error: bool = False,
) -> List[tuple]:
    """
    Get the HTML of a list of URLs, returning tuples of (url, response).
    This is useful when you need to know which URL each response came from.

    Args:
        executor: ThreadPoolExecutor for running requests.
        urls: List of URLs to fetch.
        continue_on_error: If True, continue processing even if some URLs fail.
                          If False (default), raise on first failure after retries exhausted.

    Returns:
        List of (url, response) tuples for successful fetches.

    Raises:
        Exception: If continue_on_error is False and any URL fails after retries.
    """
    loop = asyncio.get_running_loop()
    loader = load_url_safe if continue_on_error else load_url
    futures = [loop.run_in_executor(executor, loader, url) for url in urls]
    results = await asyncio.gather(*futures, return_exceptions=True)

    successful = []
    for url, result in zip(urls, results):
        if isinstance(result, Exception):
            if continue_on_error:
                LOG.warning(f"Failed to get page {url}: {result}")
            else:
                raise RuntimeError(f"Failed to fetch {url} after retries: {result}") from result
        elif result is None:
            LOG.warning(f"Failed to get page {url}")
        else:
            successful.append((url, result))

    return successful
