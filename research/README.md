# Research and experiments

The research tree preserves experiments, prompts, fixtures, and dated evidence that informed Travelant. Maintained app code lives in [apps/ios](../apps/ios/), shared Swift packages in [packages](../packages/), and the beta service in [server/pocket](../server/pocket/).

| Area | Status | Use |
| --- | --- | --- |
| [PoC journey](poc-journey/README.md) | Reference | Routing, preferences, venue collection, Context Lab, and Pocket experiments with recorded provenance |
| [TripSense PoC](tripsense-poc/README.md) | Reference | Standalone Foundation Models/MapKit feasibility and search-budget experiments |
| [Model evaluations](evaluations/) | Archived runs | Captured benchmark protocols, scripts, and frozen source snapshots |
| [Pocket Engine](../packages/PocketEngine/) | Active implementation | Extracted native recommendation and scheduling core |
| [Pocket service](../server/pocket/README.md) | Active implementation | Independently maintained catalog/advice service |

These statuses describe how each area is used by the product. The PoC subprojects retain their own statuses and verification instructions. Historical Google-provider experiments remain evidence of earlier work; the current Pocket product path uses Apple services and independent records.

## Verify a relocated checkout

```sh
python3 research/poc-journey/scripts/verify_portability.py
python3 research/poc-journey/scripts/verify_evidence.py
python3 -m unittest discover -s research/poc-journey/scripts -p 'test_*.py'
```

Run the package/build commands documented in [PoC setup](poc-journey/README.md) when changing an experiment. Model bootstrap downloads verified public assets and is a separate explicit step.

## Historical paths and evidence

The complete `poc-journey/`, `tripsense-poc/`, and `evaluations/` trees moved below `research/`. Relative paths inside each experiment stay together. Original imported reports, source manifests, and frozen evaluator files retain their bytes and historical commands. Apply the [path mapping](../docs/guides/repository-layout.md) when reproducing an older root-level command. No past run is counted as a new run because of this move.
