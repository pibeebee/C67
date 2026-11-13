#!/usr/bin/env python3
"""Read compact benchmark status; never relaunch or change device state."""
import json
import subprocess
import sys
import time
from pathlib import Path

device, run, destination = sys.argv[1:]
destination = Path(destination)
previous = None
for attempt in range(100):
    command = ['xcrun', 'devicectl', 'device', 'copy', 'from', '--device', device,
        '--domain-type', 'appDataContainer', '--domain-identifier', 'giovanchristoffel.c67-trip-integration',
        '--source', f'Documents/C67Performance/{run}/status.json',
        '--destination', str(destination), '--timeout', '15']
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode == 0:
        status = json.loads(destination.read_text())
        summary = (status['progress'], len(status['results']))
        if summary != previous:
            print(status['updatedAt'], status['progress'], flush=True)
            if status['results']:
                row = status['results'][-1]
                print(row['id'], round(row['seconds'], 3), row['observed'], row['passed'], flush=True)
            previous = summary
        if status['complete']:
            sys.exit(0)
    else:
        print('Status-copy retry', attempt + 1, flush=True)
    time.sleep(20)
print('Monitor observation limit reached; device result may still be running.', flush=True)
sys.exit(2)
