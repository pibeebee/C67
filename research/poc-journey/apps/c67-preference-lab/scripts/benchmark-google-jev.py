#!/usr/bin/env python3
"""Run the user-authorized Google Places to Jev experiment in a private directory.

This explicitly selected experiment is separate from the independently sourced
catalogue. It does not activate a catalogue generation or change its source guard.
"""

import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
from statistics import median
import threading
import time
from zoneinfo import ZoneInfo

from server import ROOT, credentials, curl_json

spec = importlib.util.spec_from_file_location('direct_jev', ROOT / 'scripts/label-catalog-jev.py')
jev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(jev)

FIELDS = [
    'id', 'displayName', 'primaryType', 'primaryTypeDisplayName', 'types',
    'businessStatus', 'regularOpeningHours', 'currentOpeningHours', 'rating',
    'userRatingCount', 'priceLevel', 'outdoorSeating', 'dineIn', 'servesCoffee',
    'servesBrunch', 'servesDessert', 'servesVegetarianFood', 'goodForGroups',
    'goodForChildren', 'liveMusic', 'reservable', 'allowsDogs', 'editorialSummary',
    'reviews', 'websiteUri', 'googleMapsUri',
]
FACTS = {
    'outdoorSeating': 'tempat duduk pengunjung di luar ruangan',
    'dineIn': 'layanan makan di tempat', 'servesCoffee': 'menyajikan kopi',
    'servesBrunch': 'menyajikan brunch', 'servesDessert': 'menyajikan dessert',
    'servesVegetarianFood': 'menyajikan makanan vegetarian',
    'goodForGroups': 'cocok untuk rombongan', 'goodForChildren': 'cocok untuk anak',
    'liveMusic': 'tersedia musik langsung', 'reservable': 'menerima reservasi',
    'allowsDogs': 'anjing diperbolehkan',
}
TYPE_LABELS = {
    'cafe': ['cafe'], 'coffee_shop': ['cafe'], 'restaurant': ['restaurant'],
    'bakery': ['bakery'], 'ice_cream_shop': ['dessert_shop'], 'dessert_shop': ['dessert_shop'],
    'tea_house': ['tea_house'], 'food_court': ['food_court'], 'park': ['park'],
    'botanical_garden': ['botanical_garden'], 'plaza': ['public_square'],
    'museum': ['museum'], 'art_museum': ['museum', 'art_museum'],
    'history_museum': ['museum', 'history_museum'], 'science_museum': ['museum', 'science_museum'],
    'art_gallery': ['art_gallery'], 'cultural_center': ['cultural_center'],
    'movie_theater': ['cinema'], 'performing_arts_theater': ['performance_venue'],
    'karaoke': ['karaoke'], 'library': ['library'], 'book_store': ['bookstore'],
    'coworking_space': ['coworking_space'], 'shopping_mall': ['shopping_mall'],
    'thrift_store': ['thrift_shop'], 'sports_complex': ['sports_center'],
    'swimming_pool': ['swimming_pool'], 'bowling_alley': ['bowling_alley'],
    'video_arcade': ['arcade'], 'playground': ['playground'],
    'japanese_restaurant': ['restaurant', 'japanese_cuisine'],
    'korean_restaurant': ['restaurant', 'korean_cuisine'],
    'indonesian_restaurant': ['restaurant', 'indonesian_cuisine'],
}
RETRYABLE = jev.RETRYABLE | {'transport_35', 'transport_56'}
CAPS = {'google': 550, 'jev': 800}


def fingerprint(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text())


def now():
    return datetime.now(ZoneInfo('Asia/Jakarta')).isoformat()


class Requests:
    def __init__(self, directory):
        self.directory = directory
        self.lock = threading.Lock()
        self.last_google = 0

    def reserve(self, provider):
        with self.lock:
            path = self.directory / 'usage.json'
            usage = load(path) if path.exists() else dict.fromkeys(CAPS, 0)
            if usage[provider] >= CAPS[provider]:
                raise RuntimeError(provider + '_campaign_limit')
            usage[provider] += 1
            jev.write_json(path, usage)

    def send(self, provider, url, body, headers, timeout, method='POST'):
        self.reserve(provider)
        if provider == 'google':
            with self.lock:
                pause = max(0, self.last_google + .2 - time.monotonic())
                if pause:
                    time.sleep(pause)
                self.last_google = time.monotonic()
        return curl_json(url, body, headers, timeout, method)


def description(place, rich):
    # Identity, address and author profiles are omitted from model input.
    lines = [
        'Data berikut menjelaskan satu tempat. Kolom yang tidak tersedia berarti belum diketahui.',
        'Kategori utama yang dicatat Google: ' + place.get('primaryTypeDisplayName', {}).get('text', 'belum diketahui') + '.',
        'Kode jenis tempat yang dicatat Google: ' + ', '.join(place.get('types', [])) + '.',
    ]
    for key, statement in FACTS.items():
        if key in place:
            lines.append('Fasilitas tercatat: ' + statement + ' = ' + ('ya' if place[key] else 'tidak') + '.')
    if 'businessStatus' in place:
        lines.append('Status usaha: ' + place['businessStatus'] + '.')
    if rich:
        summary = place.get('editorialSummary', {}).get('text')
        if summary:
            lines.append('Ringkasan editorial tentang tempat: ' + summary[:1200])
        for i, review in enumerate(place.get('reviews', [])[:5], 1):
            text = review.get('text', {}).get('text')
            if text:
                # A review is a report from one visitor, not a verified policy.
                lines.append(f'Ulasan pengunjung {i} (laporan individual, mungkin hanya area atau waktu tertentu): ' + text[:900])
    return '\n'.join(lines)


def structured_labels(place):
    labels = {label for t in place.get('types', []) for label in TYPE_LABELS.get(t, [])}
    if place.get('outdoorSeating') is True:
        labels.add('outdoor')
    return sorted(labels)


def fetch_place(pid, requests, directory, key):
    path = directory / 'google' / (pid + '.json')
    if path.exists():
        result = load(path)
        if result['place'].get('id') != pid:
            raise ValueError('Google checkpoint does not match requested ID')
        return result
    began = time.monotonic()
    errors = []
    for attempt in range(2):
        try:
            place = requests.send('google', 'https://places.googleapis.com/v1/places/' + pid + '?languageCode=id',
                                  {}, {'X-Goog-Api-Key': key, 'X-Goog-FieldMask': ','.join(FIELDS)}, 20, 'GET')
            if place.get('id') != pid or 'types' not in place:
                raise ValueError('Google returned an unexpected identity or no place types')
            result = {'fetchedAtWIB': now(), 'seconds': time.monotonic() - began,
                      'attempts': attempt + 1, 'errors': errors, 'fieldMask': FIELDS, 'place': place}
            jev.write_json(path, result)
            return result
        except RuntimeError as error:
            errors.append(str(error))
            if str(error) not in RETRYABLE or attempt:
                raise
            time.sleep(2)


def classify_place(pid, place, rich, requests, directory, key, definitions, parents, questions):
    variant = 'rich' if rich else 'structured'
    path = directory / variant / (pid + '.json')
    text = description(place, rich)
    input_hash = jev.digest(text)
    if path.exists():
        saved = load(path)
        if saved['inputHash'] != input_hash or set(saved['scores']) != set(definitions):
            raise ValueError('Jev checkpoint does not match this input or taxonomy')
        return saved
    began = time.monotonic()
    for attempt in range(3):
        try:
            response = requests.send('jev', jev.ENDPOINT,
                                    {'model': jev.MODEL, 'state': {'description': text}, 'questions': questions},
                                    {'Authorization': 'Bearer ' + key}, 25)
            break
        except RuntimeError as error:
            if str(error) not in RETRYABLE or attempt == 2:
                raise
            time.sleep(attempt + 1)
    if response.get('provider') != 'TypeSafe' or not response.get('model', '').startswith(jev.MODEL):
        raise ValueError('Unexpected Jev provider or model')
    scores, labels, inferred, suppressed = jev.select_labels(response.get('answers'), definitions, parents)
    usage = response.get('usage', {})
    result = {'id': pid, 'variant': variant, 'description': text, 'inputHash': input_hash,
              'labels': labels, 'scores': scores, 'inferredParentLabels': inferred,
              'suppressedSubtypes': suppressed, 'model': response['model'], 'provider': response['provider'],
              'seconds': time.monotonic() - began, 'attempts': attempt + 1,
              'inputTokens': usage.get('input_tokens'), 'costUSD': usage.get('cost')}
    jev.write_json(path, result)
    return result


def summarise(rows):
    counts = Counter(label for row in rows for label in row['labels'])
    return {'places': len(rows), 'placesWithLabels': sum(bool(r['labels']) for r in rows),
            'placesWithMultipleLabels': sum(len(r['labels']) > 1 for r in rows),
            'labelAssignments': sum(counts.values()), 'distinctLabels': len(counts),
            'labelFrequency': dict(counts.most_common()),
            'medianSeconds': round(median(r['seconds'] for r in rows), 3),
            'totalCostUSD': (sum(r['costUSD'] for r in rows)
                             if all(isinstance(r.get('costUSD'), (int, float)) for r in rows) else None),
            'modelVersions': sorted({r['model'] for r in rows})}


def report(directory, frozen, previous, links, records, inputs):
    old_by_id = {r['id']: r for r in previous['places']}
    paired = {link['placeID']: old_by_id[link['independentID']] for link in links['retainedIdentityLinks']}
    paired = {pid: row for pid, row in paired.items() if pid in records}
    google_rows = [records[pid]['rich'] for pid in frozen['placeIDs'] if pid in records]
    structured = [records[pid]['structured'] for pid in paired if 'structured' in records[pid]]
    rich_paired = [records[pid]['rich'] for pid in paired]
    legacy = [{'labels': sorted(set(r['jev']['confirmedSourceLabels']) | set(r['jev']['proposedLabelsForReview'])),
               'seconds': r['jev']['seconds'], 'model': r['jev']['model']} for r in previous['places']]
    old_subset = [{'labels': sorted(set(r['jev']['confirmedSourceLabels']) | set(r['jev']['proposedLabelsForReview'])),
                   'seconds': r['jev']['seconds'], 'model': r['jev']['model']} for r in paired.values()]
    additions = []
    for pid, old in paired.items():
        new = records[pid]['rich']
        old_labels = set(old['jev']['confirmedSourceLabels']) | set(old['jev']['proposedLabelsForReview'])
        additions.append({'id': pid, 'name': records[pid]['google']['place'].get('displayName', {}).get('text'),
                          'oldJevLabels': sorted(old_labels), 'oldSourceLabels': old['labels'],
                          'googleRichJevLabels': new['labels'],
                          'addedByJev': sorted(set(new['labels']) - old_labels),
                          'removedByJev': sorted(old_labels - set(new['labels']))})
    coverage = Counter()
    retrievals = [r['google'] for r in records.values()]
    for row in retrievals:
        place = row['place']
        coverage.update(f for f in FIELDS if f in place)
    evidence_agreement = {}
    for mode, rows in [('rich', google_rows), ('structured', structured)]:
        expected = confirmed = extras = 0
        for decision in rows:
            labels = set(structured_labels(records[decision['id']]['google']['place']))
            expected += len(labels)
            confirmed += len(labels.intersection(decision['labels']))
            extras += len(set(decision['labels']) - labels)
        evidence_agreement[mode] = {'explicitSourceLabelAssignments': expected,
                                    'recoveredExplicitSourceLabels': confirmed,
                                    'otherLabelAssignmentsNeedingEvidenceReview': extras}
    catalogue = {
        'generatedAtWIB': now(), 'schemaVersion': 1, 'source': 'Google Places API (New)',
        'taxonomyVersion': 1, 'threshold': jev.THRESHOLD,
        'inputHashes': inputs, 'labelPolicy': 'Jev output only, subtype-implies-parent-unless-conflicting-v1',
        'places': [{'id': pid, 'name': records[pid]['google']['place'].get('displayName', {}).get('text'),
                    'googleMapsUri': records[pid]['google']['place'].get('googleMapsUri'),
                    'businessStatus': records[pid]['google']['place'].get('businessStatus'),
                    'sourceStructuredLabels': structured_labels(records[pid]['google']['place']),
                    'labels': records[pid]['rich']['labels'], 'scores': records[pid]['rich']['scores'],
                    'model': records[pid]['rich']['model'], 'sourceFetchedAtWIB': records[pid]['google']['fetchedAtWIB']}
                   for pid in frozen['placeIDs'] if pid in records]}
    jev.write_json(directory / 'catalogue.json', catalogue)
    output = {
        'generatedAtWIB': now(), 'inputHashes': inputs,
        'comparisons': {'previous500JevOnly': summarise(legacy), 'google500RichJevOnly': summarise(google_rows),
                        'pairedOldJevOnly': summarise(old_subset), 'pairedGoogleRichJevOnly': summarise(rich_paired),
                        'pairedGoogleStructuredJevOnly': summarise(structured) if structured else None},
        'googleFieldCoverage': dict(coverage), 'explicitEvidenceAgreement': evidence_agreement,
        'googleRetrieval': {'completed': len(retrievals),
                            'medianSeconds': round(median(r['seconds'] for r in retrievals), 3),
                            'requestsReserved': load(directory / 'usage.json')['google'],
                            'listedRateUSDPer1000': 25,
                            'nominalCostBeforeMonthlyFreeAllowanceUSD': .025 * load(directory / 'usage.json')['google'],
                            'actualBilledCostUSD': None},
        'jevSuccessfulRequestCostUSD': sum(row[k]['costUSD'] or 0 for row in records.values()
                                         for k in ('rich','structured') if k in row),
        'pairedChanges': additions,
        'limitations': [
            'Only 86 place identities overlap. Overall 500-to-500 comparisons mix source and population effects.',
            'More accepted labels and agreement with provider categories do not measure human preference fit.',
            'Structured categories are incomplete. Extra labels are not automatically errors.',
            'Reviews are at most five returned visitor reports, clipped to 900 characters each. They are not a representative review sample.',
            'Google content storage and derivative-use permission for a permanent catalogue remains unconfirmed.',
            'Google billed cost depends on monthly allowances and discounts and was not returned by the API.',
        ],
    }
    jev.write_json(directory / 'comparison.json', output)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--limit', type=int, default=500, choices=range(1, 501))
    args = parser.parse_args()
    os.umask(0o077)
    directory = args.directory
    directory.mkdir(parents=True, exist_ok=True)
    for child in ('google', 'rich', 'structured'):
        (directory / child).mkdir(exist_ok=True)
    paths = {
        'frozen': ROOT / '.local/google-places-jakarta-selatan-2026-11-10.json',
        'previous': ROOT / '.local/jakarta-selatan-500-terlabel.json',
        'links': ROOT / '.local/jakarta-selatan-500-coverage.json',
        'taxonomy': ROOT / 'catalog/place-labels.json',
    }
    inputs = {name: fingerprint(path) for name, path in paths.items()}
    version, definitions, parents = jev.taxonomy()
    assert version == 1 and len(definitions) == 62
    questions = jev.make_questions(definitions)
    manifest = {'inputs': inputs, 'fields': FIELDS, 'model': jev.MODEL, 'threshold': jev.THRESHOLD,
                'questionsHash': jev.digest(questions), 'descriptionVersion': 1,
                'requestCaps': CAPS, 'scriptHash': fingerprint(Path(__file__))}
    frozen, previous, links = [load(paths[k]) for k in ('frozen', 'previous', 'links')]
    pids = frozen['placeIDs']
    assert len(pids) == len(set(pids)) == 500
    paired_ids = {r['placeID'] for r in links['retainedIdentityLinks']}
    assert len(paired_ids) == 86 and paired_ids.issubset(pids)
    keys = credentials()
    if not keys.get('GOOGLE_PLACES_API_KEY') or not keys.get('OPENROUTER_API_KEY'):
        parser.error('Google Places and OpenRouter keys are both required')
    with (directory / 'run.lock').open('a') as guard:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        manifest_path = directory / 'manifest.json'
        if manifest_path.exists() and load(manifest_path) != manifest:
            parser.error('Campaign configuration changed. Use a separate directory.')
        if not manifest_path.exists():
            jev.write_json(manifest_path, manifest)
        requests = Requests(directory)
        records = {}
        failures = {}
        began = time.monotonic()

        def process(pid):
            google = fetch_place(pid, requests, directory, keys['GOOGLE_PLACES_API_KEY'])
            result = {'google': google}
            result['rich'] = classify_place(pid, google['place'], True, requests, directory,
                                            keys['OPENROUTER_API_KEY'], definitions, parents, questions)
            if pid in paired_ids:
                result['structured'] = classify_place(pid, google['place'], False, requests, directory,
                                                      keys['OPENROUTER_API_KEY'], definitions, parents, questions)
            return result

        # Validate actual provider compatibility before scheduling the campaign.
        first = pids[0]
        records[first] = process(first)
        print(json.dumps({'preflight': 'passed', 'target': args.limit}), flush=True)
        with ThreadPoolExecutor(max_workers=6) as executor:
            futures = {executor.submit(process, pid): pid for pid in pids[1:args.limit]}
            for future in as_completed(futures):
                pid = futures[future]
                try:
                    records[pid] = future.result()
                except (RuntimeError, ValueError) as error:
                    failures[pid] = str(error)
                if (len(records) + len(failures)) % 25 == 0:
                    print(json.dumps({'completed': len(records), 'failed': len(failures),
                                      'wallSeconds': round(time.monotonic() - began, 1),
                                      'requests': load(directory / 'usage.json')}), flush=True)
        jev.write_json(directory / 'failures.json', failures)
        if failures:
            raise SystemExit(json.dumps({'completed': len(records), 'failures': dict(Counter(failures.values()))}))
        assert inputs == {name: fingerprint(path) for name, path in paths.items()}
        if args.limit == 500:
            output = report(directory, frozen, previous, links, records, inputs)
            print(json.dumps(output['comparisons'], ensure_ascii=False, indent=2))
        execution = {'completedAtWIB': now(), 'completed': len(records),
                     'wallSecondsThisInvocation': round(time.monotonic() - began, 3),
                     'requests': load(directory / 'usage.json')}
        jev.write_json(directory / 'execution.json', execution)
        print(json.dumps(execution), flush=True)


if __name__ == '__main__':
    main()
