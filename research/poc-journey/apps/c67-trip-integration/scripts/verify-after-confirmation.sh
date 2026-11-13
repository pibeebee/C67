#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
if [[ "${C67_P3_WEATHERKIT_CONFIRMED:-}" != "YES" ]]; then
  print -u2 'STOP: execution guard not set. Read docs/WEATHERKIT_CONFIRMATION.md and set C67_P3_WEATHERKIT_CONFIRMED=YES only under the recorded user authorization for this App ID.'
  exit 64
fi
mkdir -p artifacts
case "${1:-}" in
  build)
    xcodebuild -quiet -project C67TripIntegration.xcodeproj -scheme C67TripIntegration \
      -destination 'generic/platform=iOS' -derivedDataPath DerivedData -allowProvisioningUpdates build \
      2>&1 | tee artifacts/build.log
    ;;
  unit)
    swift test --package-path Packages/TripIntegration 2>&1 | tee artifacts/unit.log
    ;;
  ui)
    : "${P3_SIMULATOR_DESTINATION:?Set the destination to an installed iOS 26+ Simulator}"
    xcodebuild -quiet -project C67TripIntegration.xcodeproj -scheme C67TripIntegration \
      -destination "$P3_SIMULATOR_DESTINATION" -derivedDataPath DerivedData \
      -resultBundlePath "artifacts/ui-$(date +%Y%m%d-%H%M%S).xcresult" test \
      2>&1 | tee artifacts/ui.log
    ;;
  *) print -u2 'Usage: verify-after-confirmation.sh build|unit|ui'; exit 64 ;;
esac
