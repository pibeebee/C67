#!/usr/bin/env python3
"""Build a fresh isolated Pocket catalog through the existing reviewed-evidence store."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--identities', required=True, type=Path)
    parser.add_argument('--evidence', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    identity = json.loads(args.identities.read_text())
    evidence = json.loads(args.evidence.read_text())
    server_path = Path(__file__).resolve().parents[1] / 'Server/server.py'
    spec = importlib.util.spec_from_file_location('pocket_store', server_path)
    server = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(server)

    with tempfile.TemporaryDirectory(prefix='pocket-reviewed-') as work:
        folder = Path(work)
        seed = folder / 'empty.json'
        seed.write_text('{"venues":[]}')
        old_seed = os.environ.get('POCKET_SEED_CATALOG')
        os.environ['POCKET_SEED_CATALOG'] = str(seed)
        try:
            store = server.Store(folder / 'catalog.sqlite')
        finally:
            if old_seed is None:
                del os.environ['POCKET_SEED_CATALOG']
            else:
                os.environ['POCKET_SEED_CATALOG'] = old_seed
        print(json.dumps(store.import_identities(identity)))
        print(json.dumps(store.merge(evidence)))
        payload = json.dumps(store.catalog(), ensure_ascii=False, indent=2) + '\n'

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', dir=args.output.parent, delete=False) as output:
        try:
            output.write(payload)
            output.close()
            os.replace(output.name, args.output)
        finally:
            Path(output.name).unlink(missing_ok=True)


if __name__ == '__main__':
    main()
