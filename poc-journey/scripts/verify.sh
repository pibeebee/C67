#!/bin/bash
# Deterministic verification only. No signing account, hosted AI or live providers.
set -euo pipefail
journey_root="$(cd "$(dirname "$0")/.." && pwd)"
output_root="${POC_OUTPUT_DIR:-$journey_root/.verification/$(date +%Y%m%d-%H%M%S)-${1:-checks}}"
mkdir -p "$output_root"
case "${1:-}" in
  packages)
    for package in TripIntelligence PreferenceLearning VisitTiming PreferenceQuality; do
      swift test --package-path "$journey_root/apps/c67-foundation-lab/Packages/$package" > "$output_root/$package.log" 2>&1
      tail -n 4 "$output_root/$package.log"
    done
    swift test --package-path "$journey_root/apps/c67-trip-integration/Packages/TripIntegration" > "$output_root/TripIntegration.log" 2>&1
    tail -n 4 "$output_root/TripIntegration.log"
    ;;
  cli)
    cd "$journey_root/apps/ai-trip-planner"
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm ci --ignore-scripts > "$output_root/npm-install.log" 2>&1
    npm run check > "$output_root/cli-check.log" 2>&1
    npm test > "$output_root/cli-tests.log" 2>&1
    npm run format:check > "$output_root/cli-format.log" 2>&1
    tail -n 10 "$output_root/cli-tests.log"
    ;;
  native)
    cd "$journey_root/apps/native-routing-lab"
    bash scripts/test-weather-lab.sh "$output_root/native-weather" > "$output_root/native-weather.log" 2>&1
    bash scripts/test-native-trip-jakarta.sh "$output_root/native-jakarta" > "$output_root/native-jakarta.log" 2>&1
    tail -n 5 "$output_root/native-weather.log"
    tail -n 5 "$output_root/native-jakarta.log"
    ;;
  build)
    for definition in 'native-routing-lab:poc-c67' 'c67-foundation-lab:C67FoundationLab' 'c67-trip-integration:C67TripIntegration'; do
      app="${definition%%:*}"; scheme="${definition##*:}"
      xcodebuild -quiet -project "$journey_root/apps/$app/$scheme.xcodeproj" -scheme "$scheme" \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath "$output_root/DerivedData-$scheme" \
        CODE_SIGNING_ALLOWED=NO build > "$output_root/build-$scheme.log" 2>&1
      printf 'PASS: %s unsigned Simulator build\n' "$scheme"
    done
    ;;
  ui)
    : "${P3_SIMULATOR_DESTINATION:?Choose an installed iOS 26+ Simulator destination}"
    for definition in 'c67-foundation-lab:C67FoundationLab' 'c67-trip-integration:C67TripIntegration'; do
      app="${definition%%:*}"; scheme="${definition##*:}"
      xcodebuild -quiet -project "$journey_root/apps/$app/$scheme.xcodeproj" -scheme "$scheme" \
        -destination "$P3_SIMULATOR_DESTINATION" -derivedDataPath "$output_root/DerivedData-$scheme" \
        -resultBundlePath "$output_root/$scheme.xcresult" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
        -parallel-testing-enabled NO test > "$output_root/ui-$scheme.log" 2>&1
      printf 'PASS: %s fixture UI tests\n' "$scheme"
    done
    ;;
  *) printf 'Usage: verify.sh packages|cli|native|build|ui\n' >&2; exit 64 ;;
esac
printf 'Evidence directory: %s\n' "$output_root"
