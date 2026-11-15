#!/usr/bin/env python3
"""Wait briefly for an already-authorized device unlock, then launch once."""
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path

device = sys.argv[1]
folder = Path(sys.argv[2])
folder.mkdir(parents=True, exist_ok=True)
for attempt in range(36):
    lockfile = folder / 'lock-current.json'
    check = subprocess.run(['xcrun', 'devicectl', 'device', 'info', 'lockState',
        '--device', device, '--timeout', '10', '--json-output', str(lockfile)], capture_output=True, text=True)
    state = json.loads(lockfile.read_text()).get('result', {}) if check.returncode == 0 else {}
    if state.get('passcodeRequired') is False:
        launch = subprocess.run(['xcrun', 'devicectl', 'device', 'process', 'launch',
            '--device', device, '--terminate-existing', 'giovanchristoffel.c67-trip-integration',
            '--timeout', '30'], capture_output=True, text=True)
        (folder / 'launch-after-unlock.log').write_text(launch.stdout + launch.stderr)
        print('Launch exit:', launch.returncode, flush=True)
        sys.exit(launch.returncode)
    if attempt % 6 == 0:
        print('Waiting for device unlock; check', attempt + 1, flush=True)
    time.sleep(5)
print('Device remains locked; no benchmark launched.', flush=True)
sys.exit(2)
