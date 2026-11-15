#!/usr/bin/env python3
"""Export derived observations from the current Simulator container, never a stale UUID."""
import argparse,json,shutil,subprocess
from pathlib import Path
LAB=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--simulator',default='A548563C-F35D-45E9-92C8-C323A38033D1');a=p.parse_args()
root=Path(subprocess.check_output(['xcrun','simctl','get_app_container',a.simulator,'giovanchristoffel.c67-context-lab','data'],text=True).strip())
out=LAB/'artifacts/personal-recommendation-2026-11-08'
for src,dest in [(root/'Documents/PersonalBenchmark/recommendations.json',out/'simulator-recommendations.json'),
 (root/'Documents/PersonalBenchmark/personal-plan-latest.json',out/'personal-plan-latest.json'),
 (root/'Library/Application Support/personal-state-ui-test.json',out/'synthetic-profile-state.json')]:
 if not src.exists():raise SystemExit('Missing expected derived output: '+src.name)
 shutil.copy2(src,dest);print('Exported '+dest.name)
