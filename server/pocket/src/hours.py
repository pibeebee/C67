"""Transient opening-hours lookup and conservative category hints for Pocket.

Provider output is never persisted here. Missing data is not an open/closed claim.
"""
import os
import re
import time
from urllib.parse import urlsplit
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
import httpx

PLACE_ID = re.compile(r'^I[0-9A-Fa-f]+$')
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

    def lookup(self, place_id):
        if not isinstance(place_id, str) or not PLACE_ID.fullmatch(place_id) or len(place_id) > 64:
            return {'status': 'invalid_place_id'}
        parts = urlsplit(self.base_url)
        if (parts.scheme != 'https' or not parts.hostname or parts.username or parts.password or parts.query or parts.fragment or not self.token):
            return {'status': 'not_configured'}
        for attempt in range(2):
            try:
                response = self.get(self.base_url + '/api/v1/places/apple-hours', params={'placeId': place_id},
                                    headers={'Authorization': 'Bearer ' + self.token, 'Accept': 'application/json'},
                                    timeout=8, follow_redirects=False)
                if response.status_code == 404:
                    return {'status': 'unavailable'}
                if response.status_code in (401, 403):
                    return {'status': 'configuration_error'}
                if response.status_code == 502 and attempt == 0:
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
