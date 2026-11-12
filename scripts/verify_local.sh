#!/usr/bin/env bash
# Run local checks before a feature PR to dev; never deploy or reset a database.
set -euo pipefail
cd "$(dirname "$0")/.."
C67_VERIFY_MODE=${1:-quick}
case "$C67_VERIFY_MODE" in
  quick|ios-smoke|ios-full) ;;
  *) echo 'Usage: bash scripts/verify_local.sh [quick|ios-smoke|ios-full]' >&2; exit 2 ;;
esac
C67_CONTRACT_PYTHON=${C67_CONTRACT_PYTHON:-.venv/bin/python}
if [[ ! -x "$C67_CONTRACT_PYTHON" ]]; then
  echo 'Create .venv and install scripts/requirements.txt, or set C67_CONTRACT_PYTHON.' >&2
  exit 2
fi
C67_VERIFY_DIR=${C67_VERIFY_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/c67-verify.XXXXXX")}
mkdir -p "$C67_VERIFY_DIR"
exec > >(tee "$C67_VERIFY_DIR/verification.log") 2>&1
echo "Mode: $C67_VERIFY_MODE"
echo "Commit: $(git rev-parse HEAD)"
echo "Evidence: $C67_VERIFY_DIR"
git status --short
xcodebuild -version
python3 -m unittest discover -s scripts -p 'test_integration_policy.py'
python3 scripts/swift_format.py --check
"$C67_CONTRACT_PYTHON" scripts/check_contracts.py
npm ci --prefix server/planning --ignore-scripts
npm run check --prefix server/planning
npm run format:check --prefix server/planning
npm test --prefix server/planning
swift test --package-path ios-backend
git diff --check
if [[ "$C67_VERIFY_MODE" != quick ]]; then
  C67_VERIFY_DESTINATION=${C67_SIMULATOR_DESTINATION:-$(python3 scripts/simulator_destination.py)}
  C67_VERIFY_COMMAND=(xcodebuild -project ios-ui/C67.xcodeproj -scheme C67
    -destination "$C67_VERIFY_DESTINATION" -derivedDataPath "${C67_VERIFY_DERIVED_DATA:-/tmp/c67-local-checks}"
    -resultBundlePath "$C67_VERIFY_DIR/ios-tests.xcresult")
  if [[ "$C67_VERIFY_MODE" == ios-smoke ]]; then
    C67_VERIFY_COMMAND+=(
      -only-testing:C67AppTests
      -only-testing:C67UITests/TripHomeUITests/testEmptyHomeNavigationAndPlanningEntry
      -only-testing:C67UITests/TripHomeUITests/testSavingMockProposalOpensTripAndReturnsHome
    )
  fi
  echo "Simulator destination: $C67_VERIFY_DESTINATION"
  C67_VERIFY_COMMAND+=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- C67_DATA_MODE=mock test)
  "${C67_VERIFY_COMMAND[@]}"
fi
echo "Local $C67_VERIFY_MODE verification passed. This does not establish live-provider or device acceptance."
