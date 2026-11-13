# C67 Preference Lab

**10 November verified checkpoint, v0.3.** The real evidence catalogue, configured LLM, actual AnyJev, SQLite matching and Simulator flow completed verification. Twenty OSM entities were processed. Python regression passed 43 cases, Swift regression 13, and five distinct UI scenarios passed across focused runs. Source+LLM and source+LLM+AnyJev both matched 72/72 authored label statuses. Standalone AnyJev L0 performed poorly in this configuration. Real-user preference fit remains unmeasured. See [the full catalogue results](CATALOG_RESULTS_2026-11-10.md), [reproduction protocol](catalog/README.md), and [status](artifacts/catalog-2026-11-10/STATUS.md). The v0.2 results below remain historical evidence.

Separate SwiftUI PoC, built and exercised on iPhone 18 Pro Max Simulator / iOS 27.2 with Xcode 27.2 on 9 November 2026. Deployment target iOS 26. Bundle: `giovanchristoffel.c67-preference-lab`. Existing Context Lab and its backend are separate.

Version 0.2 uses live Google Places results in the main flow. Explicit preferences drive the search, and each card explains which needs have evidence. The local clarification experiment and E5 audit remain available with the launch argument `--illustrations`. The optional LLM advisor receives preference choices only.

## Result

On 18 authored paired probes, broad interests plus E5 matched the hidden brief in the first result in 8 cases. One local clarification matched in 15; one LLM-selected clarification also matched in 15, including two explicit budget fallbacks. Up to two local clarifications matched in 18. These are synthetic case outcomes, not participant satisfaction or an estimate of accuracy over real places. See [the full report](RESULTS_2026-11-09.md).

The recommended default is local clarification; LLM assistance remains an optional experimental mode. Keep E5 as a separately measured helper, not evidence of satisfying a requirement.

## Run the application

From this directory:

```bash
python3 scripts/server.py start
xcodegen generate --spec App/project.yml
open App/C67PreferenceLab.xcodeproj
```

Choose `C67PreferenceLab` and the intended Simulator. The independent backend listens on `127.0.0.1:8780`. This connection is for a Simulator on the same Mac; it is not an iPhone network setup.

The service reads Google configuration from the existing ignored `../c67-local-server-lab/.env.local`, and the active LLM configuration from ignored `.env.catalog.local`. The LLM endpoint is `https://luna-provider.example/v1`, model `cx/gpt-6-luna(max)`. Provider keys stay on the Mac. `.local/connection.json` and ignored `App/RunConfig.json` hold only a local bearer. Restarting the service rotates this bearer; rebuild the app afterward. Do not distribute debug builds containing it. A fresh checkout also needs catalogue preparation as described in [the protocol](catalog/README.md).

During the earlier OpenRouter development campaign, the ceiling was extended from 30 to 42 attempted model requests to correct the original-contract timeout comparison. Final observed use was 39. That historical counter is retained. The current configured provider uses its own persistent 72-attempt ceiling, shared by extraction and the advisor. Monetary cost is unknown unless the endpoint reports it.

Status/stop only affect the new service:

```bash
python3 scripts/server.py status
python3 scripts/server.py stop
```

## Try Google discovery

Choose **Pencarian Google** in the source control for these v0.2 steps. The v0.3 default is **Katalog kegiatan**, using the active preprocessed catalogue. Its cards expose evidence and unknown requirements without additional model calls.

1. Select **Membaca**, optionally **Kopi**, then **Temukan tempat**.
2. Choose **Membaca di tempat** or **Mencari atau membeli buku**. If you selected coffee, choose whether both activities should happen at the same place. You can also skip clarification and view results.
3. Open **Kecocokan dengan pilihan Anda** on a card to review the evidence. Save a place and use **Cari tempat lainnya** when another page is available.
4. In **Pilihan saya**, correct an answer, make it required, remember it, or undo. A new trip drops temporary needs and keeps explicitly remembered preferences. The most recent 20 undo snapshots survive relaunch.
5. Use **Perjelas sendiri** for further optional corrections after automatic questions finish. There is no forced typing.
6. Try **Bantu perjelas dengan AI** if an unresolved question remains. Its disclosure precedes sharing activity choices with OpenRouter/model providers. Local examples remain usable while it runs or if it fails.
7. In **Pilihan saya**, optionally set your visit date and time. Add a duration if you want the entire visit checked against the provider's dated opening sessions.

The app saves your preferences, visit settings and selected place IDs. Place details are fetched live. Reading permission, seating, quietness and conditions at a particular hour still require direct evidence. The live technical results are in [the place integration report](LIVE_PLACES_2026-11-09.md).

The Experiments sheet contains A/B/C modes and E5 diagnosis. For a fair manual comparison start a fresh trip/profile; a profile that already learned the answer is not a valid broad-interest baseline. Pace is retained but does not invent time/walking/waiting limits.

## Reproduce without provider calls

```bash
swift test --disable-sandbox --cache-path .local/swift-cache --scratch-path .build
python3 -m unittest discover -s scripts -p 'test_*.py' -v
swift run --skip-build preference-bench artifacts/replayed.json --replay
python3 scripts/report.py
```

Replay uses the stored live question decisions and the actual Simulator E5 scores. The audit rechecks fixture hashes, recomputes result metrics and compares replayed outcomes. It does not assert that historical latency was measured again.

`scripts/make-fixtures.py` regenerates the owned development probes. Do not change them after a campaign and keep presenting the old outputs as comparable. Expected answers are evaluator-only and never sent in advisor requests. These probes are designed around the implemented activity vocabulary; they are not an independent real-user holdout.

## Live verification and evidence

Live commands consume API quota and should not run repeatedly just to reproduce the report:

```bash
swift run --skip-build preference-bench artifacts/live.json --live
python3 scripts/control-current.py
```

The default run executes 18 advisor cases and six initial original-contract diagnostics. The corrected original-contract script uses 17 seconds and a separate output file. Do not overwrite the retained failed/short-budget diagnostic when reporting results.

The UI test scheme supports opt-in live checking through `PREFERENCE_LIVE_UI=1` / `TEST_RUNNER_PREFERENCE_LIVE_UI=1`. Ordinary UI tests skip that live case. `testE5Audit` exports `Documents/PreferenceLab/e5-audit.json` from the app container; copy it into `artifacts/` before a fresh E5-based comparison.

Run the real discovery checks with `python3 scripts/benchmark-live-places.py artifacts/my-live-run`. This writes counts and timings. The service defaults to 100 Google requests per UTC day in this lab. The preference and provider benchmarks use separate artifacts.

Shareable evidence: owned fixtures/manifest, sanitized observations, summary, replay audit, source hashes and screenshot of illustrative examples. Private `.xcresult` bundles and `.local` logs/configuration are ignored. No private keys or Google review corpus belong in the handoff.

## Limits

No real participant or field visit was completed. The original app's full live discovery, UI, routing and personal history were not replayed. The supplementary contract diagnostic reuses its prompt and diversity logic on owned synthetic candidates; it is not a full-app accuracy benchmark. Third-party endpoint availability, schema behavior and data policy must be checked for a new campaign. Physical iPhone behavior, unsupported activities and actual venue-level evidence remain separate work.
