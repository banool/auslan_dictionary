import asyncio
import logging
import time
from email.utils import parsedate_to_datetime
from typing import List, Optional

import requests
from retry import retry

LOG = logging.getLogger(__name__)
formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
ch = logging.StreamHandler()
ch.setFormatter(formatter)
LOG.addHandler(ch)

# Base every Auslan media URL is served from. data-v2.json (read by current app
# builds) stores only the path *after* this base; the app re-prepends it (see
# AUSLAN_MEDIA_BASE_URL in lib/main.dart). Keeping the host out of the data — and
# out of a saved video's identity — means the content can move hosts without
# invalidating saved videos. If Signbank ever serves a video from a different
# base, strip_media_base() raises so we notice and update both sides.
MEDIA_BASE_URL = (
    "https://object-store.rc.nectar.org.au/v1/"
    "AUTH_92e2f9b70316412697cddc6f3ac0ee4e/staticauslanorgau"
)


def strip_media_base(url: str) -> str:
    """Return the path of [url] after MEDIA_BASE_URL, raising if it isn't
    under that base — that would mean Auslan media moved hosts, which needs a
    coordinated change to MEDIA_BASE_URL here and AUSLAN_MEDIA_BASE_URL in the
    app (plus a client data-version bump)."""
    if not url.startswith(MEDIA_BASE_URL):
        raise ValueError(
            f"Video URL is not under the expected media base "
            f"{MEDIA_BASE_URL!r}: {url!r}. If Auslan media moved hosts, update "
            f"MEDIA_BASE_URL here and AUSLAN_MEDIA_BASE_URL in the app."
        )
    return url[len(MEDIA_BASE_URL) :]


# The fallback media host: a Cloudflare R2 bucket (auslan-mirror) that
# sync_media_to_r2.py keeps populated. The app lists it after MEDIA_BASE_URL in
# mediaBaseUrls (AUSLAN_MEDIA_MIRROR_BASE_URL in lib/main.dart), so keys are the
# same strip_media_base() paths.
MIRROR_BASE_URL = "https://cdn.auslandictionary.org"

# Identify ourselves to the hosts we hit. Scripts that make many requests
# should use make_session() so they also get connection reuse.
USER_AGENT = (
    "auslan-dictionary-scripts/1.0 (+https://github.com/banool/auslan_dictionary)"
)


def make_session() -> requests.Session:
    """A requests Session with our User-Agent set."""
    session = requests.Session()
    session.headers["User-Agent"] = USER_AGENT
    return session


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


# Cap on how long we'll honor a server's Retry-After header (seconds), so a
# pathological value can't stall a worker indefinitely.
RETRY_AFTER_CAP = 120


def _respect_retry_after(response):
    """
    If the server sent a Retry-After header (typically with a 429 or 503),
    sleep for the requested duration (capped) so we back off politely. Supports
    both the integer-seconds and HTTP-date forms of the header.
    """
    header = response.headers.get("Retry-After")
    if not header:
        return
    delay = None
    try:
        delay = float(header)
    except ValueError:
        try:
            delay = parsedate_to_datetime(header).timestamp() - time.time()
        except (TypeError, ValueError):
            delay = None
    if delay and delay > 0:
        delay = min(delay, RETRY_AFTER_CAP)
        LOG.warning(f"Server asked us to back off; sleeping {delay:.0f}s (Retry-After)")
        time.sleep(delay)


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
        # Include enough detail to tell a blocked scraper (WAF / captcha /
        # rate limiting) apart from the site just being down.
        raise RuntimeError(
            f"Got status code {response.status_code} for {url}. "
            f"Response headers: {dict(response.headers)}. "
            f"Our user agent: {response.request.headers.get('User-Agent')!r}. "
            f"Start of body: {response.text[:500]!r}"
        )
    return response


def load_url_safe(
    url: str, timeout: int = DEFAULT_TIMEOUT
) -> Optional[requests.Response]:
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
                raise RuntimeError(
                    f"Failed to fetch {url} after retries: {result}"
                ) from result
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
                raise RuntimeError(
                    f"Failed to fetch {url} after retries: {result}"
                ) from result
        elif result is None:
            LOG.warning(f"Failed to get page {url}")
        else:
            successful.append((url, result))

    return successful
