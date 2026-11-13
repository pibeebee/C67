# C67 PoC journey: GitHub packaging and teammate handoff plan

**Prepared:** 5 November 2026, Asia/Jakarta. **Status: proposal only.** No files have been imported into C67, no branch/PR/release has been created, and nothing has been uploaded.

## Outcome

Add one self-contained `poc-journey/` area to `https://github.com/pibeebee/C67`. A teammate should be able to understand the experiments and decisions, run the current integrated PoC from a fresh clone, and find historical source, tests, failures and evidence without the original Mac or Codex chats.

The handoff includes the itinerary/recommendation/routing/weather PoC journey. It does not silently turn the PoCs into the production C67 implementation or import unrelated aviation/homelab data from the surrounding document workspace.

## Observed repository and source state

These observations were made read-only; they are not migration/build results.

- Target C67 is **public**, default branch `main`, observed head `d2ce4ee753c36467683d78625193780aa73168a6`. Main currently has `ios-ui`, `ios-backend`, `server`, `contracts`, `docs`, `scripts` and `tools`; it has no PoC journey folder.
- The local C67 checkout is clean on `gi/native-discover-search`. Do not reuse or reset that branch for the import. Re-read remote main when execution begins.
- Root `AGENTS.md` requires English authored documentation/comments, explicit mock/live evidence, existing boundaries and relevant verification. `docs/ai/workflow.md` asks for a bounded task brief and teammate-readable handoff.
- Existing CI uses `macos-15` for its iOS/style jobs. Its formatter inventories **every tracked/unignored `.swift` file**, including a future PoC folder. The repo formatter uses four-space indentation; imported experiments need explicit handling before the PR can pass.
- Most recent P3 evidence is v0.1 build 3: 35 package tests, two Simulator UI tests and seven scripted physical-iPhone provider cases passed. This is source evidence from the original location, not proof that a relocated fresh clone has been verified.

### Source-to-destination mapping

| Source available now | Proposed destination | Include |
| --- | --- | --- |
| Workspace `poc/ai-trip-planner/` | `apps/ai-trip-planner/` | Hosted-AI/research experiments, later deterministic CLI, TypeScript source, tests, package lock, examples, evaluation reports, safe result artifacts |
| `<LOCAL_HOME>/Programming/software/ios/poc-c67/` | `apps/native-routing-lab/` | Full runnable Xcode app, native routing/adaptive search, active replanning, Weather Lab, legacy screens needed by the project, test harnesses, scripts, fixtures, documentation and safe evidence |
| Workspace `poc/c67-foundation-lab/` | `apps/c67-foundation-lab/` | Current five-screen app, four local packages, Mac runners, guided-generation prompts/contracts, preference/timing/quality/E5 experiments, tests, fixtures and reports |
| Workspace `poc/c67-trip-integration/` | `apps/c67-trip-integration/` | Integrated app and package, Mac probe, replay/live harnesses, tests, catalogs, source manifest, P3 reports and public-safe evidence |
| Workspace `CBL.md`, relevant `docs/poc`, `docs/research`, `docs/technology`, product/design context | `docs/` | Original dated source records plus an English navigation/synthesis layer; an explicit inclusion inventory defines the relevant scope |
| `docs/poc/foundation-models-evaluation-2026-11-04/` | `docs/evaluation-protocols/foundation-models-2026-11-04/` | Original instructions, inputs, tool fixtures, contracts, rubric/oracle and checksums, with evaluator-only data kept separate from model inputs |
| `<LOCAL_HOME>/Downloads/REPORT.md` | `docs/source-records/foundation-models-teammate-report.md` | The teammate's original evaluation report, attributed as an external contribution with its missing linked evidence recorded |

All destinations above are relative to `poc-journey/`. The native routing checkout has important **modified and untracked** work, so a plain `git archive HEAD` would omit part of the actual PoC. Import from an inventoried working-tree snapshot, recording HEAD plus dirty/untracked inclusion; do not claim that snapshot was an existing historical commit.

Approximate inventory outside build/dependency caches: CLI 4 MB, native lab 67.5 MB, Foundation Lab 224 MB and integration 85.5 MB. These include accumulated evidence and are not predicted final Git sizes. Foundation Lab includes a 118,346,824-byte ONNX model and 17,082,730-byte tokenizer; integration includes large `.xcresult` data. A publication allowlist is necessary.

## Proposed layout

```text
poc-journey/
├── README.md
├── HANDOFF.md
├── JOURNEY.md
├── STATUS.md
├── AGENTS.md
├── THIRD_PARTY.md
├── apps/
│   ├── ai-trip-planner/
│   ├── native-routing-lab/
│   ├── c67-foundation-lab/
│   │   └── Packages/
│   │       ├── TripIntelligence/
│   │       ├── PreferenceLearning/
│   │       ├── VisitTiming/
│   │       └── PreferenceQuality/
│   └── c67-trip-integration/
│       └── Packages/TripIntegration/
├── docs/
│   ├── context/
│   ├── decisions/
│   ├── research/
│   ├── evaluation-protocols/
│   ├── source-records/
│   │   ├── CBL.md
│   │   └── foundation-models-teammate-report.md
│   └── missing-evidence.md
├── evidence/
│   ├── README.md
│   ├── index.json
│   └── publication-manifest.json
└── scripts/
    ├── bootstrap.py
    ├── verify-portability.py
    ├── verify-evidence.py
    └── verify.sh
```

The script names and new documents are proposed deliverables, not files already implemented. Existing per-app documentation and small evidence stay near their original paths wherever possible. `evidence/index.json` indexes them; it does not duplicate every run into a second directory.

### Why keep these app/package locations

Foundation Lab and Trip Integration remain siblings with their current folder names. This preserves `../c67-foundation-lab` Xcode references and `../../../c67-foundation-lab/Packages/...` SwiftPM references. Copying only the latest integration app would leave those dependencies missing.

The main C67 iOS app currently targets iOS 18; Foundation Lab and Trip Integration target iOS 26. Their separate project boundaries must remain explicit. Adding the PoC folder does not raise the main app deployment target or prove back-deployment to iOS 18.

Keep the shared packages inside Foundation Lab for this handoff. Moving them to a new root `Packages/` would create an unnecessary refactor. Also retain the integration app's documented `VendorRouting` snapshot; do not merge its provider/scheduling hooks into the older routing app during packaging.

Do not copy nested `.git` directories or use submodules requiring the teammate to access unrelated local repositories. Record source commits, included working-tree files and SHA256 values in a provenance manifest. Historical source snapshots already stored as `.swift.txt` remain frozen. Where no complete older source snapshot exists, retain the report/commit reference and label historical reproduction incomplete; do not invent old release tags or claim every past build can be reconstructed. Do not import entire nested Git histories without separately checking their publication scope.

## What the teammate reads first

| Document | Purpose |
| --- | --- |
| `README.md` | What is in the folder; start with Trip Integration; links to setup, status and journey |
| `HANDOFF.md` | Exact first-run steps, app/scheme selection, model setup, signing/WeatherKit, replay versus live runs, current boundaries and immediate next tasks |
| `STATUS.md` | Each capability and app version: implemented, build-verified, fixture-tested, live-tested, user-reported, failed or not tested |
| `JOURNEY.md` | Hypothesis → experiment → observed result → limitation/failure → decision → next experiment, with dates and evidence links |
| `AGENTS.md` | Read root C67 instructions first; PoC scope, historical-source rules, provider/test boundaries and where to continue |
| `docs/source-records/CBL.md` | Full existing source record, preserving earlier decisions and later corrections |
| `evidence/README.md` | Where actual evidence lives, which files are release assets, which fields were redacted and which artifacts were not provided |

New explanatory docs and code comments follow C67's English convention. Indonesian source notes, quoted prompts and user-facing text must not be silently translated and misrepresented as the original. Retain them as clearly attributed archival inputs; explain that archival distinction in the scoped instructions while keeping new summaries in English.

### Journey chapters

1. Initial hosted-AI/research-assisted itinerary experiments, audits and limitations.
2. Deterministic CLI using external place/routing providers; Japan/transit and schedule constraints.
3. Native MapKit routing, benchmark comparisons and the locked adaptive hybrid strategy.
4. Backend-independent local persistence and manual active-trip replanning; distinguish that app's active-trip work from P3's pre-trip revision.
5. Jakarta/place-identity corrections and the standalone Weather Lab.
6. Teammate's initial Foundation Models report, followed by our separate Foundation Lab; preserve differences in task, schema, locale and available evidence.
7. Local structured preferences, E5 and live MapKit; then sourced visit timing and extreme tests.
8. Preference-quality comparison and the follow-up E5-versus-BM25/category benefit study.
9. P3 integration, real Cikini localization failure/fix, actual WeatherKit/iPhone results and remaining questions.

Use dated stage IDs in the index. The earlier native-replanning roadmap's P0/P1/P2A/P2B and the later recommendation-feasibility priorities 1/2/3 are different sequences; do not merge them into one ambiguous P1/P2 label. In particular, native active-trip replanning and the integration app's pre-trip +30-minute revision are different capabilities.

Older failed/partial reports stay intact. Add dated follow-up records instead of rewriting an old WeatherKit failure as if it had already passed. The separate Weather Lab chat contains Giovan's later success confirmation; label it **user-reported** unless its corresponding provider export is also available. P3 has separate direct-device JSON evidence.

## Completeness and evidence storage

“Complete” means every included stage has its source/entry point, relevant setup/config template, fixtures/tests, report, decision and evidence disposition. It does not mean committing caches, credentials, device backups or invented missing results.

### Commit to ordinary Git

- Source, tests, fixture inputs, catalogs, prompt versions, lockfiles, Xcode project/configuration, existing runners and bootstrap instructions.
- All relevant authored reports and original dated notes, including limitations, failed experiments and initial unsuccessful runs.
- Small sanitized JSON/JSONL metrics, JUnit/test summaries, source hashes, representative screenshots, attribution/source metadata and per-app evidence indexes.
- A source map from original location to publication location, original hash to published hash, and the reason for any packaging/redaction change.

### Restore rather than commit

- E5 model/tokenizer: retain the existing pinned Hugging Face download script and manifest. Model revision is `614241f622f53c4eeff9890bdc4f31cfecc418b3`; the model hash is `dd476dd0c2514e9b9be83aeb3853fac0763e0bdf4a71645407587d77c48a2d88`. `bootstrap.py` should delegate to the existing verifier/downloader rather than introduce another model variant. The [pinned model card](https://huggingface.co/intfloat/multilingual-e5-small/raw/614241f622f53c4eeff9890bdc4f31cfecc418b3/README.md) declares MIT; include its attribution/license references.
- The 118 MB model exceeds [GitHub's 100 MiB ordinary-Git file limit](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github). A fresh clone plus the pinned downloader is the recommended default; Git LFS is unnecessary for that route. A checksum-verified release mirror can be added later if needed.
- Large sanitized benchmark collections and full `.xcresult` bundles: publish a versioned, compressed release evidence archive with checksums when useful. Important summaries/screenshots remain readable without downloading it.
- Exclude regenerated dependencies/builds: `.build`, `DerivedData`, `node_modules`, virtual environments, binaries, app/IPA/archive products, local caches and Xcode user state.

Every large-asset reference must lead to an available archive/index or a working restore instruction. Do not leave broken relative links, create dummy evidence files or label a missing asset as tested.

### Public repository handling

The local CLI `.env` exists. Its values were not read or copied during this planning pass. Import only reviewed placeholder examples. Exclude credentials, real sessions/tokens, private keys, provisioning profiles and account/device exports. Sanitize unnecessary UDIDs, serials, private addresses, home-directory paths, private hostnames and identifying screenshot metadata from publishable evidence.

Use stable pseudonyms for run/place references when redaction is needed so related artifacts remain comparable. Keep original input/run/source checksums as historical identifiers, and record separate hashes for the redacted publication copies; do not pretend a redacted file still has the original bytes. Original sensitive logs remain local and are explicitly listed as withheld, not uploaded inside a release ZIP.

No raw chat/session dumps are needed. Extract attributed decisions and evidence references; a teammate should not need private Codex links to understand the handoff.

### Known missing evidence

The teammate's `REPORT.md` exists, but its ten relative references under `series-v4/` and `assessed-runs.jsonl` do not resolve beside that supplied report. The protocol ZIP in this workspace contains the evaluator package, not those result artifacts. Inventory other explicitly supplied locations during preparation; until located, mark these links **not provided at the report location**, preserving the report without claiming a complete reproduction bundle.

Preserve the distinction between authored fixture oracles, evaluator-only answers and model-visible inputs. Publishing the test package does not make it a fresh held-out evaluation for future experiments.

## Portability and configuration

1. Replace `<LOCAL_HOME>/...`, local thread links and cross-workspace references with repository-relative links or an explicit original-source mapping. Preserve original paths only in sanitized archival/provenance form when necessary.
2. Keep current sibling package topology; verify Xcode/SwiftPM references from an unrelated checkout location.
3. Make entry scripts derive paths from their own location, not the original Mac's working directory.
4. Provide local signing overrides/templates. Record the tested bundle IDs and toolchain as evidence, but do not assume another teammate can use Giovan's Apple team/profile. WeatherKit setup must match the teammate's chosen App ID/team.
5. Provide separate commands for fixture/replay, ordinary builds, optional model inference and live service tests. No provider or paid-service probe runs automatically after clone.
6. Native P3 should require no team AI backend/OpenRouter key. Legacy CLI Google/OpenRouter configurations remain optional, stage-specific requirements.
7. Preserve snapshot dates, timezone and source-check timestamps. Expired visit facts require a new dated source check for a new live run; do not move historical dates to make fixtures appear current.
8. Carry third-party attributions, including E5 and the Jakarta boundary provenance, and retain recorded package/runtime/model versions.

## CI and integration with the existing repository

Keep production `ios-ui`, `ios-backend`, contracts and server behavior unchanged. The root README/team starter can receive a link to the experimental journey; production ADRs must not be silently replaced by PoC conclusions.

The import must pass the existing root formatter, which sees all Swift files. Recommended handling: format the **imported runnable copies** using the repo's pinned rules, keep original evaluated-source archives/hashes separately, record formatting-only hash changes and rerun the relevant PoC checks after relocation. Do not reformat the original workspaces or rewrite old evidence hashes. If area-specific formatting is chosen instead, it needs an explicit, reviewable CI scope change, not an accidental exclusion hiding failed checks.

Proposed separate `.github/workflows/poc-journey.yml`:

- Path/link/provenance/secret-pattern and missing-asset checks, plus TypeScript CLI deterministic checks on Linux/Node 24.
- Swift package and unsigned Simulator build/replay checks on a compatible macOS 26+/Xcode image; pin/verify the actual toolchain. The current [GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) lists `macos-26` and `xcode-27`, but the exact Xcode/Simulator version must be confirmed during workflow implementation. Existing `macos-15` production jobs need not be changed to run these packages.
- Restore/cache model assets by revision/hash where the check requires actual E5. Report an intentional no-model/fallback check separately; do not let missing weights masquerade as successful E5 inference.
- Do not require Apple Intelligence generation, WeatherKit authentication, personal certificates or physical iPhone access in automatic PR CI. Those remain separately recorded, manually invoked live evaluations. A green fixture CI job is not live-provider evidence.

Keep existing required checks/branch protections. Import PR CI passing does not establish that the main C67 app has integrated P3.

## Execution sequence after this plan

1. Refresh target main, create an isolated worktree/branch **`gi/poc-journey-handoff`**, and add a bounded import task brief. Do not mutate the clean feature checkout or reset the dirty native-lab checkout.
2. Produce a complete file inventory/allowlist and provenance snapshot covering tracked, modified and untracked sources. Freeze the current stage/version map and known gaps.
3. Copy approved project files into the new folder, preserving sibling packages and historical evidence. Remove nested Git metadata from publication copies only.
4. Build the English handoff/journey/status/index layer; preserve archival originals, fix links/paths, apply public redactions and document all transformations.
5. Bootstrap the pinned model and packages from an unrelated clean-checkout path. Align runnable copies with repo conventions and record source-hash mappings.
6. Run per-project deterministic checks, package tests, builds and relevant Simulator journeys. Recheck that previous iPhone evidence still refers to its original tested snapshot; any new live run gets a new manifest/date instead of inheriting a pass count.
7. Review the complete diff, public file list, unresolved evidence and any release archive. Prepare a PR describing the final imported scope and proof. Do not push directly to main or change production behavior as part of this packaging.
8. At publication time, upload the reviewed branch/PR and any reviewed public-safe evidence assets; follow the repository's normal review/merge process. This planning request does not execute that step.

## Acceptance for the handoff

- All four project roots, their local packages/runners/tests and relevant documentation are accounted for, including important dirty/untracked native work.
- A teammate can find the current entry point in one README and see the next bounded task in `HANDOFF.md`.
- Trip Integration builds and its deterministic suite/replay run from a fresh location after documented bootstrap. Results after relocation are newly recorded, not assumed from today's original-location run.
- Small linked evidence is present; larger evidence has valid archive/restore links; missing/withheld data is explicit. No requirement for another person's private chat or original absolute path.
- No secrets, provisioning/device dumps, model weights over the ordinary-Git limit, dependency caches or generated builds are accidentally staged.
- Original experiment dates, failed/partial outcomes, attribution and limits remain visible. Technical feasibility is not mislabeled as proven personal relevance or user effort reduction.
- Existing C67 app/contracts/server behavior and unrelated local work remain intact; any root README/CI change is limited to the documented import integration.

## References inspected

- Current C67 repository metadata, main tree and root instructions/workflow via authenticated read-only GitHub calls and the local checkout.
- Local CBL, four PoC roots, their package/project references, evidence reports and pinned model downloader/manifest.
- Referenced itinerary/routing and Weather Lab chats, read as historical context; not a substitute for provider artifacts.
- [GitHub large-file limits](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github).
- [GitHub-hosted runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
- [Pinned E5 model card/license metadata](https://huggingface.co/intfloat/multilingual-e5-small/raw/614241f622f53c4eeff9890bdc4f31cfecc418b3/README.md).
