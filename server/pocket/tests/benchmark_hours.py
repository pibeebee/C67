"""Compare the real Pocket HTTP handlers against deterministic loopback upstreams."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager, ExitStack
from functools import partial
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import math
import os
from pathlib import Path
import socket
from statistics import median
import sys
import threading
import time
from urllib.parse import parse_qs, urlsplit
from unittest.mock import patch

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from hours import HoursBatch, HoursProvider
from server import Handler, pooled_client


class Upstream(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def setup(self):
        super().setup()
        self.connection.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)

    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path == '/auth/v1/user':
            ident = int(self.headers['Authorization'].split()[-1])
            time.sleep(0.010)
            status, result = 200, {'id': f'00000000-0000-4000-8000-{ident:012d}'}
        else:
            place_id = parse_qs(urlsplit(self.path).query)['placeId'][0]
            time.sleep(0.020)
            opens, closes = (0, 86400) if self.server.all_day else (28800, 64800)
            status, result = (404, {}) if place_id == 'I2' else (200, {
                'placeId': place_id, 'timezone': 'Asia/Jakarta',
                'weekly': [{'weekday': i, 'intervals': [{'startSeconds': opens, 'endSeconds': closes}]}
                           for i in range(1, 8)],
            })
        encoded = json.dumps(result).encode()
        self.send_response(status)
        self.send_header('Content-Length', str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


class LoopbackServer(ThreadingHTTPServer):
    request_queue_size = 32
    all_day = False


@contextmanager
def serve(handler, port=0):
    with LoopbackServer(('127.0.0.1', port), handler) as server:
        thread = threading.Thread(target=server.serve_forever, kwargs={'poll_interval': .01}, daemon=True)
        thread.start()
        try:
            yield server, f'http://127.0.0.1:{server.server_port}'
        finally:
            server.shutdown()
            thread.join()


class Arm:
    def __init__(self, mode, users, auth_origin, hours_origin, port=0):
        self.mode, self.users = mode, users
        self.counts = [0, 0, 0]
        self.lock = threading.Lock()
        self.origins = auth_origin, hours_origin
        self.stack = ExitStack()
        self.port = port

    def __enter__(self):
        pocket, self.url = self.stack.enter_context(serve(Handler, self.port))
        self.client = self.stack.enter_context(pooled_client())
        self.auth_client = self.stack.enter_context(pooled_client())
        self.hours_client = self.stack.enter_context(pooled_client())
        self.workers = self.stack.enter_context(ThreadPoolExecutor(max_workers=8))
        provider = HoursProvider(get=partial(self.upstream, 1))
        pocket.hours_batch = HoursBatch(provider)
        self.stack.callback(pocket.hours_batch.pool.shutdown)
        if self.mode != 'A':
            pocket.auth_http = self.auth_client
            self.original_auth_get = self.auth_client.get
            self.auth_client.get = partial(self.upstream, 0)
        else:
            # A uses a fresh upstream HTTP client for each request, as before pooling.
            self.stack.enter_context(patch.object(httpx, 'get', partial(self.upstream, 0)))
        return self

    def __exit__(self, *exc):
        self.stack.__exit__(*exc)

    def upstream(self, index, url, **kwargs):
        with self.lock:
            self.counts[index + 1] += 1
        real_url = self.origins[index] + urlsplit(url).path
        if self.mode == 'A':
            with httpx.Client() as client:
                return client.get(real_url, **kwargs)
        get = self.original_auth_get if index == 0 else self.hours_client.get
        return get(real_url, **kwargs)

    def post(self, path, payload, user):
        with self.lock:
            self.counts[0] += 1
        headers = {'Authorization': f'Bearer {user}'}
        if self.mode == 'A':
            with httpx.Client() as client:
                return client.post(self.url + path, json=payload, headers=headers).raise_for_status().json()
        return self.client.post(self.url + path, json=payload, headers=headers).raise_for_status().json()

    def run(self, ids):
        self.counts = [0, 0, 0]
        started = time.perf_counter()
        if self.mode == 'C':
            work = [self.workers.submit(self.post, '/v1/hours/batch', {'placeIds': ids}, user)
                    for user in range(self.users)]
            results = [future.result()['results'] for future in work]
        else:
            results = [{} for _ in range(self.users)]
            # Two lookups per user. Fixture latencies are equal within a wave.
            for start in range(0, len(ids), 2):
                work = [(user, place, self.workers.submit(self.post, '/v1/hours/lookup', {'placeId': place}, user))
                        for user in range(self.users) for place in ids[start:start + 2]]
                for user, place, future in work:
                    results[user][place] = future.result()
        elapsed = (time.perf_counter() - started) * 1000
        expected_calls = self.users * (1 if self.mode == 'C' else len(ids))
        assert self.counts == [expected_calls, expected_calls, self.users * len(ids)], self.counts
        assert all(all(row[id]['status'] == ('unavailable' if id == 'I2' else 'available') for id in ids)
                   for row in results)
        return elapsed, results


def main():
    with patch.dict(os.environ, {'POCKET_AUTH_MODE': 'authenticated', 'SUPABASE_URL': 'https://auth.invalid',
                                 'SUPABASE_CLIENT_KEY': 'synthetic', 'POCKET_HOURS_BASE_URL': 'https://hours.invalid',
                                 'POCKET_HOURS_TOKEN': 'synthetic'}):
        with serve(Upstream) as (_, auth), serve(Upstream) as (hours_server, hours):
            if sys.argv[1:] == ['--serve-simulator']:
                hours_server.all_day = True
                with ExitStack() as stack:
                    for mode, port in zip('ABC', (18791, 18792, 18793)):
                        stack.enter_context(Arm(mode, 1, auth, hours, port))
                    print('Simulator fixtures ready', flush=True)
                    threading.Event().wait()
                return
            for users in (int(sys.argv[1]),) if len(sys.argv) == 2 else (1, 4):
                for count in (1, 3, 6):
                    ids = [f'I{i}' for i in range(1, count + 1)]
                    for temperature in ('cold', 'warm'):
                        with ExitStack() as stack:
                            arms = {mode: stack.enter_context(Arm(mode, users, auth, hours)) for mode in 'BC'} if temperature == 'warm' else {}
                            for arm in arms.values():
                                arm.run(ids)
                            samples = {mode: [] for mode in 'ABC'}
                            for repeat in range(30):
                                matched = []
                                for mode in 'ABC'[repeat % 3:] + 'ABC'[:repeat % 3]:
                                    if mode in arms:
                                        elapsed, results = arms[mode].run(ids)
                                    else:
                                        with Arm(mode, users, auth, hours) as arm:
                                            elapsed, results = arm.run(ids)
                                    samples[mode].append(elapsed)
                                    matched.append(results)
                                assert matched[0] == matched[1] == matched[2]
                            for mode, values in samples.items():
                                p95 = sorted(values)[math.ceil(len(values) * .95) - 1]
                                print(f'users={users} places={count} {temperature} {mode} '
                                      f'median={median(values):.2f}ms p95={p95:.2f}ms', flush=True)


if __name__ == '__main__':
    main()
