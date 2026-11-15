#!/usr/bin/env python3
"""Run one bounded luna-provider.example arm for the Simulator visit-advice fixtures."""
import argparse
import json
import os
from pathlib import Path
import shlex
import time
import urllib.error
import urllib.parse
import urllib.request


def settings(path):
    values = {}
    if path:
        for line in path.read_text().splitlines():
            key, sep, value = line.strip().removeprefix('export ').partition('=')
            if sep and key in ('GIOVANC_API_KEY', 'GIOVANC_MODEL', 'CATALOG_LLM_BASE_URL',
                               'CATALOG_LLM_API_KEY', 'CATALOG_LLM_MODEL'):
                values[key] = ' '.join(shlex.split(value, comments=True))
    url = urllib.parse.urlsplit(values.get('CATALOG_LLM_BASE_URL', ''))
    if url.scheme == 'https' and url.hostname == 'luna-provider.example' and not (url.username or url.password or url.port):
        values.setdefault('GIOVANC_API_KEY', values.get('CATALOG_LLM_API_KEY'))
        values.setdefault('GIOVANC_MODEL', values.get('CATALOG_LLM_MODEL'))
    return {key: os.getenv(key) or values.get(key) for key in ('GIOVANC_API_KEY', 'GIOVANC_MODEL')}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--env-file', type=Path)
    args = parser.parse_args()
    spec = json.loads(args.input.read_text())
    if not 1 <= len(spec['cases']) <= 12:
        parser.error('Expected 1–12 frozen cases')
    env = settings(args.env_file)
    model = env['GIOVANC_MODEL']
    key = env['GIOVANC_API_KEY']
    if not model or not key:
        parser.error('GIOVANC_MODEL and GIOVANC_API_KEY are required')
    rows = []
    opener = urllib.request.build_opener(NoRedirect())
    for case in spec['cases']:
        request = urllib.request.Request(
            'https://luna-provider.example/v1/chat/completions',
            data=json.dumps({'model': model, 'max_tokens': 500, 'stream': False, 'messages': [
                {'role': 'system', 'content': spec['instructions']},
                {'role': 'user', 'content': case['prompt']}
            ]}).encode(),
            headers={'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'})
        row = {'id': case['id']}
        start = time.monotonic()
        try:
            with opener.open(request, timeout=60) as reply:
                body = json.loads(reply.read(1_000_000))
            row['model'] = body.get('model')
            row['usage'] = body.get('usage')
            choices = body['choices']
            if len(choices) != 1 or choices[0]['finish_reason'] != 'stop':
                raise ValueError('incomplete completion')
            answer = json.loads(choices[0]['message']['content'])
            if not isinstance(answer, dict) or set(answer) != {'slotID'} or not isinstance(answer['slotID'], str):
                raise ValueError('invalid slot schema')
            row['slotID'] = answer['slotID']
        except urllib.error.HTTPError as error:
            row['error'] = f'HTTP {error.code}'
        except (KeyError, TypeError, ValueError, OSError) as error:
            row['error'] = type(error).__name__
        row['elapsedMs'] = (time.monotonic() - start) * 1_000
        rows.append(row)
        args.output.write_text(json.dumps(rows, indent=2) + '\n')


if __name__ == '__main__':
    main()
