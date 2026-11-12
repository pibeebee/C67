#!/usr/bin/env python3
"""Convert independent OSM/Overture records into Pocket identity catalog; no model labels."""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path


def coordinate(row):
    point = row.get('center', row)
    return {'latitude': point['lat'], 'longitude': point['lon']}


def osm_venue(row):
    tags = row.get('tags', {})
    name = tags.get('name')
    if not name:
        return None
    mapping = {
        'amenity': {'restaurant': 'restaurant', 'cafe': 'cafe', 'library': 'library', 'food_court': 'food_court',
                    'cinema': 'cinema', 'theatre': 'performance_venue', 'karaoke_box': 'karaoke'},
        'shop': {'books': 'book_store', 'bakery': 'bakery', 'tea': 'tea_house', 'mall': 'shopping_mall',
                 'second_hand': 'thrift_shop', 'craft': 'craft_shop', 'records': 'record_store'},
        'leisure': {'park': 'park', 'garden': 'garden', 'sports_centre': 'sports_center',
                    'bowling_alley': 'bowling_alley', 'amusement_arcade': 'arcade', 'playground': 'playground'},
        'tourism': {'museum': 'museum', 'gallery': 'art_gallery', 'zoo': 'animal', 'aquarium': 'animal'},
    }
    categories = {values[tags[key]] for key, values in mapping.items() if tags.get(key) in values}
    if tags.get('leisure') == 'garden' and tags.get('garden:type') == 'botanical':
        categories.add('botanical_garden')
    cuisines = set(tags.get('cuisine', '').split(';'))
    if 'restaurant' in categories:
        for cuisine in ('japanese', 'korean', 'indonesian'):
            if cuisine in cuisines:
                categories.add(cuisine + '_cuisine')
        if 'sushi' in cuisines:
            categories.update(('sushi', 'japanese_cuisine'))
    if not categories:
        return None
    website = tags.get('website', tags.get('contact:website', ''))
    return dict(id=f'osm-{row["type"]}-{row["id"]}', name=name, branch=name,
                address=', '.join(tags.get(k, '') for k in ('addr:street', 'addr:housenumber', 'addr:city') if tags.get(k)),
                coordinate=coordinate(row), categories=sorted(set(categories)), aliases=[],
                sourceURLs=[f'https://www.openstreetmap.org/{row["type"]}/{row["id"]}'],
                operatorURLs=[website] if website.startswith('https://') else [],
                license='© OpenStreetMap contributors, ODbL', facts=[], hours=None)


LABELS = json.loads((Path(__file__).resolve().parents[1] / 'Sources/PocketEngine/Resources/preference-labels.json').read_text())
VENUE_LABELS = {label for section in ('types', 'subtypes') for group in LABELS[section].values() for label in group}


def overture_venue(row):
    props = row.get('properties', row)
    name = props.get('names', {}).get('primary')
    geometry = row.get('geometry', {})
    if not name or geometry.get('type') != 'Point':
        return None
    raw = props.get('categories') or {}
    taxonomy = props.get('taxonomy') or {}
    values = [raw.get('primary', ''), props.get('basic_category', ''), taxonomy.get('primary', '')] + (raw.get('alternate') or []) + (taxonomy.get('hierarchy') or [])
    mapping = {'restaurant': 'restaurant', 'japanese_restaurant': 'japanese_cuisine',
               'sushi_restaurant': 'sushi', 'cafe': 'cafe', 'coffee_shop': 'cafe', 'library': 'library',
               'bookstore': 'book_store', 'museum': 'museum', 'art_gallery': 'art_gallery',
               'art_museum': 'art_museum', 'park': 'park', 'garden': 'garden', 'zoo': 'animal',
               'aquarium': 'animal', 'shopping_mall': 'shopping_mall'}
    categories = sorted({mapping.get(key, key) for key in values if key in mapping or key in VENUE_LABELS})
    if not categories:
        return None
    lon, lat = geometry['coordinates'][:2]
    sources = props.get('sources') or []
    if not sources:
        return None
    addresses = props.get('addresses') or []
    address = ', '.join(str(addresses[0].get(key) or '') for key in ('freeform', 'locality', 'region', 'postcode') if addresses[0].get(key)) if addresses else ''
    return dict(id='overture-' + (props.get('id') or row['id']), name=name, branch=name, address=address,
                coordinate=dict(latitude=lat, longitude=lon), categories=categories, aliases=[],
                sourceURLs=['https://docs.overturemaps.org/guides/places/'],
                operatorURLs=[url for url in (props.get('websites') or []) if url.startswith('https://')],
                license='Overture Maps · ' + json.dumps([{k: source.get(k) for k in ('dataset', 'license', 'record_id', 'update_time')} for source in sources], ensure_ascii=False), facts=[], hours=None)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--osm', type=Path)
    parser.add_argument('--overture', type=Path, help='GeoJSON FeatureCollection or newline-delimited GeoJSON')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if not args.osm and not args.overture:
        parser.error('Supply --osm and/or --overture')
    venues = {}
    hashes = {}
    if args.osm:
        hashes['osm'] = hashlib.sha256(args.osm.read_bytes()).hexdigest()
        for row in json.loads(args.osm.read_text())['elements']:
            venue = osm_venue(row)
            if venue:
                venues[venue['id']] = venue
    if args.overture:
        hashes['overture'] = hashlib.sha256(args.overture.read_bytes()).hexdigest()
        with args.overture.open() as source:
            first = source.readline()
            source.seek(0)
            try:
                first_object = json.loads(first)
            except json.JSONDecodeError:
                first_object = None
            if first_object and first_object.get('type') == 'Feature':
                records = (json.loads(line) for line in source if line.strip())
            else:
                records = json.load(source)['features']
            for row in records:
                venue = overture_venue(row)
                if venue:
                    venues[venue['id']] = venue
    if len(venues) > 20_000:
        raise ValueError('Limit geographic extract to at most 20,000 relevant identities')
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')
    catalog = dict(schemaVersion=1, generatedAt=now, attribution='OpenStreetMap contributors (ODbL); Overture sources per record.', venues=list(venues.values()))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    args.output.with_suffix('.manifest.json').write_text(json.dumps(dict(inputHashes=hashes, count=len(venues), convertedAt=now, inputModifiedAt={key: dt.datetime.fromtimestamp(path.stat().st_mtime, dt.timezone.utc).isoformat() for key, path in [('osm', args.osm), ('overture', args.overture)] if path is not None}), indent=2) + '\n')
    print(json.dumps(dict(identities=len(venues), factsImported=0)))


if __name__ == '__main__':
    main()
