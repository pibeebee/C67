"""Bounded ODbL source ingestion. Source payloads retain attribution and provenance."""
import json
import subprocess
from pathlib import Path

from catalog_engine import ROOT, config, digest, utcnow

ATTRIBUTION = '© OpenStreetMap contributors · ODbL 1.0'
LICENSE_URL = 'https://www.openstreetmap.org/copyright'


def fetch_osm(output):
    cfg = config()
    south, west, north, east = cfg['bbox']
    box = ','.join(str(x) for x in (south, west, north, east))
    selectors = {'cafe': '[amenity=cafe]', 'library': '[amenity=library]', 'book_store': '[shop=books]'}
    query = '[out:json][timeout:30];(' + ''.join(
        'nwr' + selectors[c] + '[name](' + box + ');' for c in cfg['categories']) + ');out center tags;'
    errors = []
    for endpoint in ['https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter',
                     'https://overpass.private.coffee/api/interpreter']:
        try:
            result = subprocess.run(['/usr/bin/curl', '--silent', '--show-error', '--fail', '--max-time', '45',
                '--user-agent', 'C67PreferenceLab/0.3 bounded-source-pilot', endpoint,
                '--data-urlencode', 'data=' + query], capture_output=True, timeout=47)
            if result.returncode:
                errors.append('source_transport_' + str(result.returncode))
                continue
            raw = json.loads(result.stdout)
            if not isinstance(raw.get('elements'), list):
                raise ValueError('missing_elements')
            sources = select_osm(raw, cfg)
            document = {'provenance': 'openstreetmap-odbl-v1', 'licenseURL': LICENSE_URL,
                        'attribution': ATTRIBUTION, 'fetchedAt': utcnow(), 'endpoint': endpoint,
                        'sourceTimestamp': raw.get('osm3s', {}).get('timestamp_osm_base'),
                        'query': query, 'config': cfg, 'elements': sources}
            Path(output).parent.mkdir(parents=True, exist_ok=True)
            Path(output).write_text(json.dumps(document, ensure_ascii=False, indent=2))
            return document
        except (ValueError, subprocess.TimeoutExpired):
            errors.append('source_invalid_or_timeout')
    raise RuntimeError(','.join(errors))


def category(tags):
    if tags.get('tourism') == 'hotel' or tags.get('shop') == 'convenience':
        return None
    if tags.get('access') in ['private', 'no'] or tags.get('disused') == 'yes':
        return None
    if tags.get('shop') == 'books':
        return 'book_store'
    return {'cafe': 'cafe', 'library': 'library'}.get(tags.get('amenity'))


def select_osm(raw, cfg):
    groups = {c: [] for c in cfg['categories']}
    south, west, north, east = cfg['bbox']
    for element in raw['elements']:
        tags = element.get('tags', {})
        kind = category(tags)
        point = element.get('center', element)
        if kind not in groups or not tags.get('name') or not south <= point.get('lat', 99) <= north or not west <= point.get('lon', 999) <= east:
            continue
        groups[kind].append(element)
    for rows in groups.values():
        rows.sort(key=lambda e: (e['type'], e['id']))
    chosen = []
    # Deterministic category rounds keep libraries/bookshops represented.
    while len(chosen) < cfg['maxPlaces']:
        before = len(chosen)
        for rows in groups.values():
            if rows and len(chosen) < cfg['maxPlaces']:
                chosen.append(rows.pop(0))
        if before == len(chosen):
            break
    return chosen


def venues_from_source(document):
    if document.get('provenance') != 'openstreetmap-odbl-v1' or document.get('licenseURL') != LICENSE_URL:
        raise ValueError('unsupported_source_provenance')
    venues = []
    for element in select_osm(document, document['config']):
        tags = element['tags']
        kind = category(tags)
        ident = 'osm-' + element['type'] + '-' + str(element['id'])
        point = element.get('center', element)
        facts = []
        # Exact source tags remain inspectable. Only specific tags are assertions.
        predicates = {'outdoor_seating': 'outdoor_seating', 'wheelchair': 'wheelchair'}
        for key, value in sorted(tags.items()):
            if key.startswith(('contact:', 'addr:')) or key in ['phone', 'email', 'name', 'website']:
                continue
            fact = {'id': ident + ':' + key, 'text': key + '=' + value}
            if key in predicates and value in ['yes', 'no']:
                fact.update(predicate=predicates[key], value=value == 'yes')
            if key == 'shop' and value == 'books':
                fact.update(predicate='buy_books', value=True)
            if key == 'takeaway' and value == 'only':
                fact.update(predicate='coffee_onsite', value=False)
            facts.append(fact)
        street = ' '.join(filter(None, [tags.get('addr:street'), tags.get('addr:housenumber')]))
        venues.append({'id': ident, 'name': tags['name'], 'category': kind,
                       'interests': ['coffee'] if kind == 'cafe' else ['reading'],
                       'address': street or document['config']['scopeLabel'],
                       'latitude': point['lat'], 'longitude': point['lon'],
                       'sourceURL': 'https://www.openstreetmap.org/' + element['type'] + '/' + str(element['id']),
                       'sourceLicense': document['licenseURL'], 'provenance': document['provenance'],
                       'checkedAt': document['fetchedAt'], 'regularHours': tags.get('opening_hours'),
                       'facts': facts, 'sourceHash': digest(element)})
    if not venues:
        raise ValueError('empty_source_sample')
    return venues
