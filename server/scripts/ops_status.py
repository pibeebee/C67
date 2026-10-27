"""Read-only safe health report; keys/session/account records never reach stdout."""
import argparse
import json
from pathlib import Path
import sys
from test_local_api import LocalAPI, CheckFailure, require


def inspect(api):
    for name in ['list_rundowns', 'search_rundowns']:
        api.expect(api.request('POST', '/rest/v1/rpc/'+name, {}), 200)
    spec=api.expect(api.request('GET','/rest/v1/',admin=True),200)
    required=['get_trip_graph','create_trip_v3','preview_trip_change','apply_trip_change','begin_journal_upload','submit_journal_upload','list_trip_album']
    require(all('/rpc/'+name in spec.get('paths',{}) for name in required),'Required backend RPCs missing')
    print(json.dumps({'public_reads':'healthy','required_rpcs':'present','mode':'read-only','private_records_printed':False}))


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--homelab',action='store_true');args=parser.parse_args()
    try:
        if args.homelab:
            # This constructor performs only read-only origin/TLS/baseline/schema checks.
            from test_homelab_api import HomelabAPI
            inspect(HomelabAPI())
        else:inspect(LocalAPI())
    except Exception:
        print('Backend health check failed; sensitive diagnostics suppressed',file=sys.stderr);return 1
    return 0
if __name__=='__main__':raise SystemExit(main())
