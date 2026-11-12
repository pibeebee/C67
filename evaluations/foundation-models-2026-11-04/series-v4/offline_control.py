#!/usr/bin/env python3
"""Run two explicitly requested offline controls with Wi-Fi restored on exit."""
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

from run_evaluation import DEFAULT_PACKAGE, HERE, load_cases, run_case


def cmd(*args, timeout=5):
    return subprocess.run(args, text=True, capture_output=True, timeout=timeout, check=False)


def power():
    result = cmd('/usr/sbin/networksetup', '-getairportpower', 'en0')
    return result.stdout.strip()


def main():
    frozen = json.loads((HERE / 'freeze.json').read_text())
    for path, expected in frozen['sha256'].items():
        if hashlib.sha256(Path(path).read_bytes()).hexdigest() != expected:
            raise SystemExit(f'Frozen input changed: {path}')
    initial = power()
    networks = cmd('/usr/sbin/scutil', '--nwi').stdout
    if not initial.endswith('On') or 'Network interfaces: en0' not in networks:
        raise SystemExit('Offline control requires Wi-Fi on and en0 as the only active interface; no network settings changed.')
    watchdog_script = ('import subprocess,time;time.sleep(55);'
                       'subprocess.run(["/usr/sbin/networksetup","-setairportpower","en0","on"],'
                       'stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=8)')
    watchdog = subprocess.Popen([sys.executable, '-c', watchdog_script], start_new_session=True,
                                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    state = {'initialWiFiPower': initial, 'startedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
             'watchdogSeconds': 55, 'runs': []}
    try:
        changed = cmd('/usr/sbin/networksetup', '-setairportpower', 'en0', 'off')
        state['turnOffExitCode'] = changed.returncode
        state['turnOffError'] = changed.stderr.strip()
        state['offlineWiFiPower'] = power()
        if changed.returncode != 0 or not state['offlineWiFiPower'].endswith('Off'):
            state['status'] = 'blocked: could not turn Wi-Fi off'
            return
        time.sleep(2)
        remaining = cmd('/usr/sbin/scutil', '--nwi').stdout
        interface_line = next((line.strip() for line in remaining.splitlines()
                               if line.strip().startswith('Network interfaces:')), '')
        state['activeNetworkInterfaces'] = interface_line.partition(':')[2].strip() if interface_line else ''
        if state['activeNetworkInterfaces']:
            state['status'] = 'blocked: another active network interface remained'
            return
        schema = json.loads((DEFAULT_PACKAGE / 'output-contract.json').read_text())
        cases = {c['id']: c for c in load_cases(DEFAULT_PACKAGE)}
        for case_id in ('LANG-01', 'TOOL-01'):
            run = run_case(cases[case_id], 1, 'offline-control', DEFAULT_PACKAGE,
                           Path('/tmp/c67-foundation-model-evaluator-v4'), schema, 20)
            run['systemWiFiPowerAfterRun'] = power()
            state['runs'].append(run)
            if not run['systemWiFiPowerAfterRun'].endswith('Off'):
                state['status'] = 'inconclusive: Wi-Fi resumed before completion'
                return
        state['status'] = 'completed with Wi-Fi off; M2 Indonesian remains unsupported-locale diagnostic'
    finally:
        try:
            restored = cmd('/usr/sbin/networksetup', '-setairportpower', 'en0', 'on', timeout=8)
            state['restoreExitCode'] = restored.returncode
            state['restoredWiFiPower'] = power()
            if restored.returncode == 0 and state['restoredWiFiPower'].endswith('On'):
                watchdog.terminate()
                watchdog.wait(timeout=3)
        except Exception as exc:
            state['restoreError'] = repr(exc)
        (HERE / 'offline-control.json').write_text(json.dumps(state, ensure_ascii=False, indent=2) + '\n')
        print(state.get('status', 'interrupted'), 'restored:', state.get('restoredWiFiPower', 'watchdog pending'), flush=True)


if __name__ == '__main__':
    main()
