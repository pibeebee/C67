#!/usr/bin/env python3
"""Compare public-source venue identities with a frozen list of Google Place IDs."""

import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import json
import threading
import time
from pathlib import Path
from server import credentials, curl_json

SEARCH = 'https://places.googleapis.com/v1/places:searchText'
TYPE_HINT = {
    'cafe': 'cafe', 'restaurant': 'restaurant', 'bakery': 'bakery', 'dessert_shop': 'ice_cream_shop',
    'tea_house': 'tea_house', 'food_court': 'food_court', 'park': 'park',
    'botanical_garden': 'botanical_garden', 'public_square': 'plaza', 'museum': 'museum',
    'art_gallery': 'art_gallery', 'cinema': 'movie_theater', 'performance_venue': 'performing_arts_theater',
    'karaoke': 'karaoke', 'library': 'library', 'bookstore': 'book_store', 'coworking_space': 'coworking_space',
    'shopping_mall': 'shopping_mall', 'traditional_market': 'market', 'thrift_shop': 'thrift_store',
    'sports_center': 'sports_complex', 'swimming_pool': 'swimming_pool', 'bowling_alley': 'bowling_alley',
    'arcade': 'video_arcade', 'playground': 'playground',
}


def rate_gate(requests_per_second):
    lock = threading.Lock()
    next_call = time.monotonic()

    def wait():
        nonlocal next_call
        with lock:
            now = time.monotonic()
            scheduled = max(next_call, now)
            next_call = scheduled + 1 / requests_per_second
        time.sleep(max(0, scheduled - time.monotonic()))

    return wait


def query(name, source, degrees, headers, wait, type_hint=None):
    y, x = source['latitude'], source['longitude']
    body = {'textQuery': name, 'pageSize': 2, 'regionCode': 'ID', 'languageCode': 'id',
            'locationRestriction': {'rectangle': {'low': {'latitude': y - degrees, 'longitude': x - degrees},
                                                  'high': {'latitude': y + degrees, 'longitude': x + degrees}}}}
    if type_hint:
        body.update(includedType=type_hint, strictTypeFiltering=True)
    for attempt in range(2):
        try:
            wait()
            result = curl_json(SEARCH, body, headers, 12)
            break
        except RuntimeError as error:
            if attempt or str(error) not in {'provider_http_429', 'provider_http_500', 'provider_http_503', 'provider_timeout'}:
                raise
            time.sleep(1)
    if set(result) - {'places'} or any(set(row) != {'id'} for row in result.get('places', [])):
        raise ValueError('Unexpected data in IDs Only response')
    return [row['id'] for row in result.get('places', [])]


def match(source, targets, headers, wait):
    name = source['name'].strip()
    result = {'sourceID': source['id'], 'status': 'no-match'}
    try:
        first = query(name, source, .0016, headers, wait)
        relevant = targets.intersection(first)
        if not relevant:
            return result
        result.update(status='ambiguous', candidatePlaceIDs=sorted(relevant))
        if len(first) != 1:
            return result
        anchor = source.get('addressHint') or 'Jakarta Selatan'
        hint = next((TYPE_HINT[label] for label in source['referenceLabels'] if label in TYPE_HINT), None)
        second = query(f'{name}, {anchor}', source, .0012, headers, wait, hint)
        if first == second:
            result.update(status='consistent-two-queries', placeID=first[0], typeHint=hint)
    except (RuntimeError, ValueError) as error:
        result.update(status='error', error=str(error))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--frozen', required=True, type=Path)
    parser.add_argument('--sources', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--workers', type=int, choices=range(1, 13), default=8)
    parser.add_argument('--requests-per-second', type=int, choices=range(1, 9), default=8)
    parser.add_argument('--limit', type=int, default=0, help='Bound each pass; resume against the same immutable source file')
    args = parser.parse_args()
    targets = set(json.loads(args.frozen.read_text())['placeIDs'])
    sources = json.loads(args.sources.read_text())
    if len({r['id'] for r in sources}) != len(sources):
        parser.error('Duplicate source identities')
    previous = {}
    if args.output.exists():
        for line in args.output.read_text().splitlines():
            row = json.loads(line)
            if row['status'] != 'error':
                previous[row['sourceID']] = row
    pending = [row for row in sources if row['id'] not in previous]
    if args.limit:
        pending = pending[:args.limit]
    key = credentials()['GOOGLE_PLACES_API_KEY']
    headers = {'X-Goog-Api-Key': key, 'X-Goog-FieldMask': 'places.id'}
    wait = rate_gate(args.requests_per_second)
    stats = Counter()
    print(json.dumps({'pendingThisPass': len(pending), 'completedEarlier': len(previous)}), flush=True)
    with args.output.open('a', buffering=1) as output, ThreadPoolExecutor(max_workers=args.workers) as executor:
        for i, row in enumerate(executor.map(lambda r: match(r, targets, headers, wait), pending), 1):
            output.write(json.dumps(row) + '\n')
            stats[row['status']] += 1
            if i % 100 == 0 or i == len(pending):
                print(json.dumps({'processedThisPass': i, 'statuses': stats}), flush=True)
            if i == 20 and stats['error'] == i:
                raise SystemExit('All first 20 requests failed; diagnose the provider before continuing')


if __name__ == '__main__':
    main()
