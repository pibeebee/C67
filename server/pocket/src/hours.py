"""Transient opening-hours lookup and conservative category hints for Pocket.

Provider output is never persisted here. Missing data is not an open/closed claim.
"""
import os
import re
import time
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from email.utils import parsedate_to_datetime
import logging
from threading import BoundedSemaphore, Lock
from urllib.parse import urlsplit
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
import httpx

PLACE_ID = re.compile(r'^I[0-9A-Fa-f]+$')
TEMPORARY_ERROR = {'status': 'temporary_error'}


def valid_place_id(value):
    return isinstance(value, str) and len(value) <= 64 and PLACE_ID.fullmatch(value) is not None
HINTS = {'mall': (36000, 79200), 'museum': (32400, 57600), 'cinema': (36000, 93600)}


def category_hint(category):
    """Only explicitly recognized categories; numeric interval is not venue hours."""
    categories = {'museum': 'museum', 'mkpoicategorymuseum': 'museum',
                  'movietheater': 'cinema', 'mkpoicategorymovietheater': 'cinema',
                  'cinema': 'cinema', 'shoppingmall': 'mall', 'mall': 'mall'}
    kind = categories.get(category.lower().replace('_', '').replace(' ', '')) if isinstance(category, str) else None
    if kind is None:
        return None
    start, end = HINTS[kind]
    return {'category': kind, 'startSeconds': start, 'endSecondsFromStartDay': end,
            'provenance': 'unverified_category_heuristic', 'venueHoursStatus': 'unknown'}


def validate_hours(data, place_id):
    if not isinstance(data, dict) or data.get('placeId') != place_id:
        raise ValueError('Place identity mismatch')
    if data.get('hoursType', 'NORMAL') != 'NORMAL':
        raise ValueError('Not regular weekly hours')
    tz = data.get('timezone')
    try:
        ZoneInfo(tz)
    except (ZoneInfoNotFoundError, TypeError, ValueError):
        raise ValueError('Invalid time zone') from None
    weekly = data.get('weekly')
    if not isinstance(weekly, list) or len(weekly) != 7:
        raise ValueError('Incomplete weekly hours')
    found = set()
    for row in weekly:
        if not isinstance(row, dict) or type(row.get('weekday')) is not int or row['weekday'] not in range(1, 8) or row['weekday'] in found:
            raise ValueError('Invalid weekday')
        found.add(row['weekday'])
        intervals = row.get('intervals')
        if not isinstance(intervals, list) or len(intervals) > 16:
            raise ValueError('Invalid intervals')
        for interval in intervals:
            if not isinstance(interval, dict):
                raise ValueError('Invalid interval')
            a, b = interval.get('startSeconds'), interval.get('endSeconds')
            if type(a) is not int or type(b) is not int or not 0 <= a < 86400 or not 0 <= b <= 86400 or a == b:
                raise ValueError('Invalid interval boundaries')
    return data


class HoursProvider:
    """No provider token is returned, logged or persisted; retries only one 502."""
    def __init__(self, base_url=None, token=None, get=None, sleep=time.sleep):
        self.base_url = (base_url if base_url is not None else os.environ.get('POCKET_HOURS_BASE_URL', '')).rstrip('/')
        self.token = token if token is not None else os.environ.get('POCKET_HOURS_TOKEN', '')
        self.get = get or httpx.get
        self.sleep = sleep
        self.cooldown_lock = Lock()
        self.retry_at = 0.0

    def lookup(self, place_id, *, deadline=None):
        if not valid_place_id(place_id):
            return {'status': 'invalid_place_id'}
        parts = urlsplit(self.base_url)
        if (parts.scheme != 'https' or not parts.hostname or parts.username or parts.password or parts.query or parts.fragment or not self.token):
            return {'status': 'not_configured'}
        for attempt in range(2):
            remaining = 8 if deadline is None else deadline - time.monotonic()
            if remaining <= 0:
                return TEMPORARY_ERROR
            if deadline is not None:
                with self.cooldown_lock:
                    if time.monotonic() < self.retry_at:
                        return {'status': 'rate_limited'}
            try:
                started = time.monotonic()
                response = self.get(self.base_url + '/api/v1/places/apple-hours', params={'placeId': place_id},
                                    headers={'Authorization': 'Bearer ' + self.token, 'Accept': 'application/json'},
                                    timeout=min(8, remaining), follow_redirects=False)
                logging.info("hours_upstream code=%d attempt=%d elapsed_ms=%d", response.status_code, attempt + 1,
                             (time.monotonic() - started) * 1000)
                if deadline is not None and time.monotonic() >= deadline:
                    return TEMPORARY_ERROR
                if response.status_code == 404:
                    return {'status': 'unavailable'}
                if response.status_code in (401, 403):
                    return {'status': 'configuration_error'}
                if response.status_code == 429 and deadline is not None:
                    value = response.headers.get('Retry-After', '')
                    try:
                        delay = int(value) if value.isdecimal() else parsedate_to_datetime(value).timestamp() - time.time()
                    except (ValueError, TypeError, OverflowError):
                        delay = 0
                    with self.cooldown_lock:
                        self.retry_at = max(self.retry_at, time.monotonic() + delay)
                    return {'status': 'rate_limited'}
                if response.status_code == 502 and attempt == 0 and remaining > 0.25:
                    self.sleep(0.25)
                    continue
                if response.status_code != 200 or len(response.content) > 100_000:
                    return {'status': 'temporary_error'}
                payload = response.json()
                if isinstance(payload, dict) and payload.get('error') == 'no business hours found':
                    return {'status': 'unavailable'}
                return {'status': 'available', 'hours': validate_hours(payload, place_id)}
            except (httpx.HTTPError, ValueError, KeyError, TypeError):
                return {'status': 'temporary_error'}
        return {'status': 'temporary_error'}


class HoursBatch:
    """Bound upstream work across authenticated requests, including work still winding down."""
    def __init__(self, provider, capacity=8):
        self.provider = provider
        self.slots = BoundedSemaphore(capacity)
        self.pool = ThreadPoolExecutor(max_workers=capacity, thread_name_prefix='pocket-hours')

    def lookup(self, ids, deadline):
        pending = {}
        results = {}
        remaining = iter(ids)
        while time.monotonic() < deadline:
            while len(pending) < 2 and (place_id := next(remaining, None)) is not None:
                queued = time.monotonic()
                if not self.slots.acquire(timeout=max(0, deadline - time.monotonic())):
                    break
                logging.info("hours_queue elapsed_ms=%d", (time.monotonic() - queued) * 1000)
                future = self.pool.submit(self.provider.lookup, place_id, deadline=deadline)
                future.add_done_callback(lambda _: self.slots.release())
                pending[future] = place_id
            if not pending:
                break
            ready, _ = wait(pending, timeout=max(0, deadline - time.monotonic()), return_when=FIRST_COMPLETED)
            for future in ready:
                results[pending.pop(future)] = future.result()
            if not ready:
                break
        for future, place_id in pending.items():
            if future.done():
                results[place_id] = future.result()
            else:
                future.cancel()
        return {place_id: results.get(place_id, TEMPORARY_ERROR) for place_id in ids}

    def lookup_single(self, place_id):
        if not self.slots.acquire(timeout=8):
            return TEMPORARY_ERROR
        try:
            return self.provider.lookup(place_id)
        finally:
            self.slots.release()
