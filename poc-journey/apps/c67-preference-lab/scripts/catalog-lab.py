#!/usr/bin/env python3
"""Prepare a real catalogue. Run in .local/label-venv, offline inference on Mac."""
import argparse
import fcntl
import json
import os
from pathlib import Path

from catalog_engine import ROOT, PIPELINE, config, digest, snapshot, store_generation, utcnow
from catalog_sources import fetch_osm, venues_from_source


def prepare(args):
    from catalog_models import AnyJevJudge, enrich
    from server import curl_json
    from catalog_llm import CatalogLLMClient
    cfg = config()
    source = json.loads(args.source.read_text())
    venues = venues_from_source(source)
    if source['config']['bbox'] != cfg['bbox'] or source['config']['categories'] != cfg['categories']:
        raise ValueError('source_scope_differs_from_config_fetch_again')
    client = CatalogLLMClient(curl_json)
    if not client.status()['configured']:
        raise SystemExit('API key is pending in .env.catalog.local. No provider calls were made.')
    judge = AnyJevJudge(cfg)
    rows = []
    for index, venue in enumerate(venues):
        row = enrich(venue, cfg, client.complete, judge, ROOT / '.local/catalog-cache')
        rows.append(row)
        print(json.dumps({'venue': index + 1, 'total': len(venues), 'name': row['name'],
                          'llm': row['inference']['llm']['mode'], 'cacheHit': row['cacheHit'],
                          'judgeSeconds': round(row['inference']['judgeSeconds'], 3),
                          'errorCode': row['inference']['errorCode']}, ensure_ascii=False), flush=True)
        if row['proposal'] is None:
            break
    failures = [r['id'] for r in rows if r['proposal'] is None]
    if len(rows) != len(venues):
        failures += [r['id'] for r in venues[len(rows):]]
    # A partially failed provider campaign is retained for diagnosis but never
    # replaces the last fully prepared generation.
    report = {'preparedAt': utcnow(), 'pipeline': PIPELINE, 'config': cfg,
              'llm': client.identity,
              'sourceHash': digest(source), 'sourceProvenance': source['provenance'],
              'attribution': source['attribution'], 'judge': judge.metadata,
              'failures': failures, 'venues': rows,
              'evaluationSplit': {'developmentIDs': [v['id'] for v in venues[:12]],
                                  'holdoutIDs': [v['id'] for v in venues[12:]]},
              'splitMeaning': 'Frozen venue split for future external assessment, not human-validated labels.'}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    if failures:
        raise SystemExit('Provider failures retained in report. Previous active catalogue preserved.')
    metadata = {k: v for k, v in report.items() if k != 'venues'}
    run_id = store_generation(rows, metadata)
    print(json.dumps({'activatedRunID': run_id, 'venues': len(rows), 'report': str(args.output)}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='action', required=True)
    fetch = commands.add_parser('fetch')
    fetch.add_argument('--output', type=Path, default=ROOT / 'catalog/osm-source.json')
    prep = commands.add_parser('prepare')
    prep.add_argument('--source', type=Path, default=ROOT / 'catalog/osm-source.json')
    prep.add_argument('--output', type=Path, default=ROOT / 'artifacts/catalog-2026-11-10/enrichment.json')
    commands.add_parser('status')
    args = parser.parse_args()
    if args.action == 'fetch':
        data = fetch_osm(args.output)
        print(json.dumps({'venues': len(data['elements']), 'source': str(args.output)}))
    elif args.action == 'prepare':
        lock_path = ROOT / '.local/catalog-build.lock'
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        with lock_path.open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            prepare(args)
    else:
        from catalog_llm import CatalogLLMClient
        from server import curl_json
        meta, rows = snapshot()
        print(json.dumps({'metadata': meta, 'places': len(rows), 'llm': CatalogLLMClient(curl_json).status()}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
