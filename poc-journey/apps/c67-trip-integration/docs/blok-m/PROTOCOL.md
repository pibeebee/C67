# Blok M end-to-end recommendation protocol

## Goal and frozen scope

Determine whether preferences improve sourced recommendation relevance, then exercise a reviewable itinerary through acceptance, revision, persistence and export. Use Trip Integration, Bundaran HI return trips by automobile, one future Jakarta day, 1–6 destinations and existing preference features. The catchment is 1,500 metres from the observed MRT Blok M BCA pin. A matched venue must also be within 150 metres of its researched branch anchor.

The 6 November 2026 catalog contains 13 candidate identities, including shared complexes such as the public park/library and M Bloc/cafe. Candidate count therefore overstates independent physical-site coverage. The public park and its library room have separate hours. A scripted library-hours test prevents transfer of the park's 24-hour schedule. Some older independent-directory publications remain the only available hours evidence. Fresh retrieval establishes what the publication says, while temporary access, queues, holiday exceptions and present-day accuracy remain uncertain.

A generic recommendation is insensitive to the profile. Popularity alone has no failure threshold. No popularity metric is manufactured from map order or editorial selection.

## Run the app

Open `C67TripIntegration.xcodeproj`, scheme `C67TripIntegration`. Add exactly one Debug launch argument in the scheme.

| Argument | Operation | Evidence and storage |
| --- | --- | --- |
| `--p3-blok-m` | Normal interactive app with the dated catalog | Real requested providers, separate `Application Support/C67BlokM-2026-11-06` session |
| `--p3-blok-m-replay` | Interactive three-stop engineering replay | Authored coordinates/search, 20-minute legs and weather, fresh temporary session |
| `--p3-blok-m-live-eval` | Explicit scripted iPhone provider evaluation | WeatherKit diagnosis, six profiles, 1/3/6-stop routing, three-stop revision, persistence/export in `Documents/P3BlokMEval/<run-ID>` |

The integrated flow is pre-trip. Record the actual device/OS, source dates and app revision for every new run. Before real WeatherKit use, configure the operator's own matching team, App ID, capability, App Services and provisioning. Keep fallback disabled for diagnosis. Review the new proposal before accepting it. A synthetic replay retains its frozen clock and label.

## Reproduce local evaluation

Run these commands from the repository root. Replace output directory names with fresh names for each run. All shell commands use the repository RTK convention.

```sh
rtk proxy python3 poc-journey/scripts/bootstrap.py
rtk proxy python3 poc-journey/scripts/verify_portability.py
rtk proxy bash poc-journey/scripts/verify.sh packages
rtk proxy bash poc-journey/scripts/verify.sh build
rtk proxy python3 -m unittest discover -s poc-journey/scripts -p 'test_evaluate_blok_m.py'

rtk proxy swift run --package-path poc-journey/apps/c67-trip-integration/Packages/TripIntegration \
  p3-blok-m-eval --out poc-journey/.verification/blok-m-development --replay

rtk proxy env P3_SIMULATOR_DESTINATION='platform=iOS Simulator,id=INSTALLED_SIMULATOR_ID' \
  bash poc-journey/scripts/verify.sh ui
```

The development evaluator excludes P4/P5. `--baseline` disables E5 and the cold/warm measurement. The default evaluation clock is one second after the newest catalog source check, preserving a reproducible snapshot. `--live-clock` uses the actual current time and existing seven-day expiry policy. Expired sources require a newly researched dated catalog.

After freezing catalog and ranking inputs, run the reserved profiles explicitly.

```sh
rtk proxy swift run --package-path poc-journey/apps/c67-trip-integration/Packages/TripIntegration \
  p3-blok-m-eval --include-held-out --live-clock \
  --out poc-journey/.verification/blok-m-final

rtk proxy python3 poc-journey/scripts/evaluate_blok_m.py \
  poc-journey/.verification/blok-m-final/series.json \
  --out poc-journey/.verification/blok-m-review --prepare-review
```

`series.json` contains 36 recommendation comparisons for six profiles, two time windows and three methods. The same general baseline is reused across persona comparisons. Its repeated elapsed time does not represent additional requests. `cold-warm-recommendations.json` uses a fresh pipeline/E5 actor followed by the identical request. The warm call includes cached vectors and must be described accordingly.

For explicit real Mac MapKit checks, run the probe below. The evaluator's optional `--live-routes` runs real Mac routing for 1/3/6 venues and records unavailable WeatherKit. These are separate host-specific provider observations.

```sh
rtk proxy swift run --package-path poc-journey/apps/c67-trip-integration/Packages/TripIntegration \
  p3-mapkit-probe --blok-m poc-journey/.verification/blok-m-mapkit-new.json

rtk proxy swift run --package-path poc-journey/apps/c67-trip-integration/Packages/TripIntegration \
  p3-blok-m-eval --include-held-out --live-clock --live-routes \
  --out poc-journey/.verification/blok-m-live-mac-new
```

## Personas and comparison rules

| Profile | Preferred features | Hard restriction | Evaluation partition |
| --- | --- | --- | --- |
| P0 | Unknown | None | General control |
| P1 | Coffee, Wi-Fi | None | Development |
| P2 | Reading, silent-zone policy | None | Development |
| P3 | Art, culture | None | Development |
| P4 | Outdoor, nature | None | Reserved until frozen final run |
| P5 | Coffee | Avoid smoking area | Reserved until frozen final run |

All methods share factual eligibility and time feasibility. General ranking retains the empty-profile ordering after applying the target persona's gates. Category and combined methods call the app's `recommend` entry point. Score the displayed, deduplicated, schedulable proposals. Keep earlier raw rankings for diagnosis. Unknown hard restrictions cannot qualify a candidate.

Review the coverage table before interpreting ranking differences. `factSupportedIDs` is an engineering count of eligible candidates with at least one desired sourced attribute. Human relevance remains a separate judgment. Three merely eligible alternatives do not establish three relevant options.

## Independent review and acceptance

Give two people separate copies of `review-template.json` and `review-materials.json`. These files contain profiles and candidate facts without method names or ranking. Reviewers supply their identity, grade 0/1/2, reason and candidate-specific source IDs for every pair. Grade 0 means irrelevant/conflicting, 1 means partially relevant and 2 means strongly relevant. Leave preferences with insufficient supporting evidence appropriately low. Do not infer a silent-zone rule from a quiet-sounding name or editorial ambience description.

Once each person finishes independently, reconcile disagreements in a complete consensus file with the same structure. Agreed grades must remain unchanged. Keep reviewer artifacts local unless the people agree to publication.

```sh
rtk proxy python3 poc-journey/scripts/evaluate_blok_m.py \
  poc-journey/.verification/blok-m-final/series.json \
  --reviewer-a /absolute/path/review-a.json --reviewer-b /absolute/path/review-b.json \
  --consensus /absolute/path/consensus.json \
  --out poc-journey/.verification/blok-m-scored
```

The scorer rejects incomplete, boolean, null and unsupported-source grades, duplicate identities, inconsistent candidate sets and displayed-set violations. Missing recommendations count against Precision@3. NDCG uses the actual displayed ordering and ideal eligible human grades. Existing pipeline tie ordering remains part of the observed app behavior.

The agreed initial thresholds are zero critical factual/hard-gate violations, Precision@3 at least 2/3 per adequately covered persona, mean NDCG@3 at least 0.80 and mean category improvement over general at least 0.10. At least three of four directed contrasts between coffee, culture and outdoor profiles must improve relevance for the new profile. The scorer reports coverage insufficient whenever fewer than three distinct eligible venues have positive human grades. Overall completion requires all five personalized profiles and both time windows. Pending human judgments, unresolved disagreements or incomplete coverage produce `insufficient_evidence`.

The E5 contribution is reported separately against category. A changed order alone does not establish an improvement. Report top-three overlap and venue repetition as diagnostics. The catalog is curated and repetitions are correlated, so there is no population-level satisfaction claim.

## Test matrix

| ID | Scenario | Automated or observed evidence | Acceptance |
| --- | --- | --- | --- |
| BM01 | Empty versus coffee/Wi-Fi profile | New package tests and local evaluator | General label and sourced preference response |
| BM02 | Reading/quiet, art/culture, outdoor/nature, coffee/avoid smoking | Local evaluator and independent review | Coverage and relevance scored separately |
| BM03 | Add must Wi-Fi, add must quiet, exclude a candidate | New package tests | Same gates across methods, no unknown hard match |
| BM04 | Unconfirmed direction, contradictory must/avoid | New and existing contract tests | Review or invalid input before preparation |
| BM05 | Missing hours, library versus park, bookstore versus reading | New package tests | No borrowed schedule or unsupported reading permission |
| BM06 | Source expiry | New package tests | Needs recheck after seven days |
| BM07 | English park alias, duplicate/ambiguous pin, wrong branch, outside radius | New package tests and Mac lookup | Correct identity or explicit confirmation |
| BM08 | One, three and six venues | New package tests, replay exports, optional Mac routes | Selected set retained, correct timeline and request accounting |
| BM09 | Deadline too short, closing boundary and full-stay rules | New revision test and existing timing matrix | Infeasible proposal cannot apply |
| BM10 | Extend by 30 minutes, reject revision, preserve accepted plan | New and existing version tests | Version and acceptance guards hold |
| BM11 | Missing E5 model | New injected failure test | Category fallback explicit, factual gates unchanged |
| BM12 | Failed/missing weather, ETA, cancellation, stale input | Existing integrated fault tests | Explicit unknown/conflict and preserved accepted baseline |
| BM13 | Normal replay and Blok M replay through acceptance | Simulator UI tests | Real screen flow, visible synthetic label |
| BM14 | Save/load/export and corrupt storage | Existing storage tests, replay exports | Round-trip and cross-artifact consistency |
| BM15 | Actual WeatherKit diagnosis and signed iPhone cases | Explicit live-eval mode | Matching account setup, real attribution and actual provider data |
| BM16 | Physical network loss/recovery, backgrounding, input changes | Operator protocol | Observe on device, record input/output and recovery |
| BM17 | English paraphrase with identical structured profile | Manual paired live evaluation | Record rank/relevance difference with same hard gates |

For BM16, accept a baseline, disconnect connectivity before search, verify error and baseline preservation, restore connectivity and retry. Repeat while routing, then while editing the profile. For backgrounding, leave during processing and reopen. Confirm obsolete output cannot replace current input or accepted data. For BM17, use two English phrasings of the same desired features, confirm both through identical structured controls and obtain blinded reviewer grades.

Any invented fact, transferred branch/room permission, silently removed required stop, accepted infeasible/stale proposal or mislabeled provider evidence blocks correctness acceptance. Record pass, fail, blocked by external setup or not tested per layer. The final report records results actually obtained.

## Operator signing target

The user selected Hendra Irawan, Team `K39QVFTK2A`, Bundle ID `com.hendra.pocjourney`. Supply these as local Xcode build overrides. Keep personal profiles and credentials outside Git. The first attempt was blocked by Apple's pending Program License Agreement and a profile without WeatherKit. After the user activated WeatherKit, the subsequent signed build and iPhone diagnosis passed. Future operators still need their own matching account, capability and provisioning.

```sh
rtk proxy xcodebuild -project poc-journey/apps/c67-trip-integration/C67TripIntegration.xcodeproj \
  -scheme C67TripIntegration -configuration Debug -destination 'id=PAIRED_DEVICE_ID' \
  -derivedDataPath /tmp/c67-blok-m-device \
  DEVELOPMENT_TEAM=K39QVFTK2A PRODUCT_BUNDLE_IDENTIFIER=com.hendra.pocjourney \
  CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates build
```
