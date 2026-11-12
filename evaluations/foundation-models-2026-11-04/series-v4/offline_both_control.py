#!/usr/bin/env python3
"""Attempt the requested offline sample with watchdog restoration of both interfaces."""
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

from run_evaluation import DEFAULT_PACKAGE, HERE, load_cases, run_case

NETWORK = '/usr/sbin/networksetup'
SCUTIL = '/usr/sbin/scutil'
ETHERNET = 'USB 10/100/1G/2.5G LAN'


def command(*args, timeout=6):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False)


def power():
    return command(NETWORK, '-getairportpower', 'en0').stdout.strip()


def interfaces():
    info = command(SCUTIL, '--nwi').stdout
    line = next((line.strip() for line in info.splitlines() if line.strip().startswith('Network interfaces:')), '')
    return line.partition(':')[2].strip().split() if line else []


def main():
    frozen = json.loads((HERE / 'freeze.json').read_text())
    for path, digest in frozen['sha256'].items():
        if hashlib.sha256(Path(path).read_bytes()).hexdigest() != digest:
            raise SystemExit(f'Frozen input changed: {path}')
    initial_power, initial_interfaces = power(), interfaces()
    service_lines = command(NETWORK, '-listallnetworkservices').stdout.splitlines()
    if not initial_power.endswith('On') or set(initial_interfaces) != {'en0', 'en7'} or ETHERNET not in service_lines:
        raise SystemExit('Expected Wi-Fi and one enabled Ethernet service; no network settings changed.')
    watchdog_script = ('import subprocess,time;time.sleep(55);'
        'subprocess.run(["/usr/sbin/networksetup","-setairportpower","en0","on"],capture_output=True,timeout=8);'
        'subprocess.run(["/usr/sbin/networksetup","-setnetworkserviceenabled","USB 10/100/1G/2.5G LAN","on"],capture_output=True,timeout=8)')
    watchdog = subprocess.Popen([sys.executable, '-c', watchdog_script], start_new_session=True,
                                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    record = {'startedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'initialWiFiPower': initial_power, 'initialInterfaces': initial_interfaces,
              'initialEthernetService': 'enabled', 'watchdogSeconds': 55, 'runs': []}
    try:
        ethernet = command(NETWORK, '-setnetworkserviceenabled', ETHERNET, 'off')
        record['disableEthernetExitCode'] = ethernet.returncode
        record['disableEthernetError'] = (ethernet.stderr + ethernet.stdout).strip()
        services_after_disable = command(NETWORK, '-listallnetworkservices').stdout.splitlines()
        ethernet_disabled = any(line.startswith('*') and line.lstrip('* ').strip() == ETHERNET
                                for line in services_after_disable)
        record['ethernetDisabledVerified'] = ethernet_disabled
        if ethernet.returncode or not ethernet_disabled:
            record['status'] = 'blocked: macOS rejected Ethernet service change'
            return
        wifi = command(NETWORK, '-setairportpower', 'en0', 'off')
        record['disableWiFiExitCode'] = wifi.returncode
        record['disableWiFiError'] = (wifi.stderr + wifi.stdout).strip()
        record['offlineWiFiPower'] = power()
        if wifi.returncode or not record['offlineWiFiPower'].endswith('Off'):
            record['status'] = 'blocked: macOS rejected Wi-Fi power change'
            return
        for _ in range(5):
            if not interfaces():
                break
            time.sleep(1)
        record['offlineInterfaces'] = interfaces()
        if record['offlineInterfaces']:
            record['status'] = 'blocked: active network interfaces remained'
            return
        schema = json.loads((DEFAULT_PACKAGE / 'output-contract.json').read_text())
        cases = {case['id']: case for case in load_cases(DEFAULT_PACKAGE)}
        for case_id in ('LANG-01', 'TOOL-01'):
            run = run_case(cases[case_id], 1, 'offline-control', DEFAULT_PACKAGE,
                           Path('/tmp/c67-foundation-model-evaluator-v4'), schema, 20)
            run['interfacesAfterRun'] = interfaces()
            run['wifiPowerAfterRun'] = power()
            record['runs'].append(run)
            if run['interfacesAfterRun'] or not run['wifiPowerAfterRun'].endswith('Off'):
                record['status'] = 'inconclusive: connectivity returned before the sample completed'
                return
        record['status'] = 'completed with both interfaces offline; Indonesian M2 remains diagnostic'
    except Exception as error:
        record['status'] = 'blocked: offline control raised an exception'
        record['error'] = repr(error)
    finally:
        try:
            wifi = command(NETWORK, '-setairportpower', 'en0', 'on', timeout=8)
            ethernet = command(NETWORK, '-setnetworkserviceenabled', ETHERNET, 'on', timeout=8)
            record['restoreWiFiExitCode'] = wifi.returncode
            record['restoreEthernetExitCode'] = ethernet.returncode
            record['restoredWiFiPower'] = power()
            services = command(NETWORK, '-listallnetworkservices').stdout.splitlines()
            record['restoredEthernetService'] = 'enabled' if ETHERNET in services else 'unverified'
            record['restoredInterfacesAtCheck'] = interfaces()
            if wifi.returncode == 0 and ethernet.returncode == 0 and record['restoredWiFiPower'].endswith('On') and record['restoredEthernetService'] == 'enabled':
                watchdog.terminate()
                watchdog.wait(timeout=3)
        except Exception as error:
            record['restoreError'] = repr(error)
        (HERE / 'offline-both-control.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
        print(record.get('status', 'interrupted'), 'restored:', record.get('restoredWiFiPower', 'watchdog pending'),
              record.get('restoredEthernetService', 'watchdog pending'), flush=True)


if __name__ == '__main__':
    main()
