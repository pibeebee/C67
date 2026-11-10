#!/bin/bash
# Deterministic verification only. No signing account, hosted AI or live providers.
set -euo pipefail
journey_root="$(cd "$(dirname "$0")/.." && pwd)"
output_root="${POC_OUTPUT_DIR:-$journey_root/.verification/$(date +%Y%m%d-%H%M%S)-${1:-checks}}"
mkdir -p "$output_root"
# Optional verified public dependency checkout cache; CI resolves normally when unset.
package_options=()
if [[ -n "${POC_SWIFT_PACKAGES_DIR:-}" ]]; then
  package_options=(-clonedSourcePackagesDirPath "$POC_SWIFT_PACKAGES_DIR" -disableAutomaticPackageResolution -skipPackageUpdates)
fi
run_logged() {
  local log_path="$1"
  shift
  if "$@" > "$log_path" 2>&1; then
    return 0
  else
    local command_status=$?
    printf 'FAILED (exit %s); final output from %s:\n' "$command_status" "$log_path" >&2
    tail -n 80 "$log_path" >&2
    return "$command_status"
  fi
}
case "${1:-}" in
  transjakarta)
    run_logged "$output_root/python-tests.log" python3 -m unittest discover -s "$journey_root/scripts" -p 'test_*.py'
    gtfs_options=()
    if [[ -n "${TJ_GTFS_ZIP:-}" ]]; then gtfs_options=(--gtfs-zip "$TJ_GTFS_ZIP"); fi
    run_logged "$output_root/transjakarta-capabilities.log" python3 \
      "$journey_root/scripts/evaluate_transjakarta_capabilities.py" \
      --output "$output_root/capabilities" ${gtfs_options[@]+"${gtfs_options[@]}"}
    cat "$output_root/transjakarta-capabilities.log"
    ;;
  context)
    run_logged "$output_root/context-lab-tests.log" swift test -j 4 -Xswiftc -parse-as-library --package-path "$journey_root/apps/c67-local-server-lab"
    tail -n 10 "$output_root/context-lab-tests.log"
    ;;
  packages)
    for package in TripIntelligence PreferenceLearning VisitTiming PreferenceQuality; do
      run_logged "$output_root/$package.log" swift test --package-path "$journey_root/apps/c67-foundation-lab/Packages/$package"
      tail -n 4 "$output_root/$package.log"
    done
    run_logged "$output_root/TripIntegration.log" swift test --package-path "$journey_root/apps/c67-trip-integration/Packages/TripIntegration"
    tail -n 4 "$output_root/TripIntegration.log"
    ;;
  cli)
    cd "$journey_root/apps/ai-trip-planner"
    run_logged "$output_root/npm-install.log" env PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm ci --ignore-scripts
    run_logged "$output_root/cli-check.log" npm run check
    run_logged "$output_root/cli-tests.log" npm test
    run_logged "$output_root/cli-format.log" npm run format:check
    tail -n 10 "$output_root/cli-tests.log"
    ;;
  native)
    cd "$journey_root/apps/native-routing-lab"
    run_logged "$output_root/native-weather.log" bash scripts/test-weather-lab.sh "$output_root/native-weather"
    run_logged "$output_root/native-jakarta.log" bash scripts/test-native-trip-jakarta.sh "$output_root/native-jakarta"
    tail -n 5 "$output_root/native-weather.log"
    tail -n 5 "$output_root/native-jakarta.log"
    ;;
  build)
    build_failures=0
    for definition in 'native-routing-lab:poc-c67' 'c67-foundation-lab:C67FoundationLab' 'c67-trip-integration:C67TripIntegration' 'c67-journey-showcase:C67JourneyShowcase'; do
      app="${definition%%:*}"; scheme="${definition##*:}"
      if run_logged "$output_root/build-$scheme.log" xcodebuild -quiet -project "$journey_root/apps/$app/$scheme.xcodeproj" -scheme "$scheme" \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath "$output_root/DerivedData-$scheme" \
        ${package_options[@]+"${package_options[@]}"} CODE_SIGNING_ALLOWED=NO build; then
        printf 'PASS: %s unsigned Simulator build\n' "$scheme"
      else
        build_failures=$((build_failures + 1))
      fi
    done
    if [[ "$build_failures" -gt 0 ]]; then exit 1; fi
    ;;
  journey-models)
    : "${P3_SIMULATOR_DESTINATION:?Choose an installed iOS 26+ Simulator destination}"
    run_logged "$output_root/journey-models.log" xcodebuild -quiet \
      -project "$journey_root/apps/c67-journey-showcase/C67JourneyShowcase.xcodeproj" -scheme C67JourneyShowcase \
      -destination "$P3_SIMULATOR_DESTINATION" -derivedDataPath "$output_root/DerivedData-C67JourneyShowcase" \
      -resultBundlePath "$output_root/C67JourneyShowcase.xcresult" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
      -only-testing:C67JourneyShowcaseTests ${package_options[@]+"${package_options[@]}"} -parallel-testing-enabled NO test
    printf 'PASS: Journey model and geometry regression tests\n'
    ;;
  ui)
    : "${P3_SIMULATOR_DESTINATION:?Choose an installed iOS 26+ Simulator destination}"
    for definition in 'c67-foundation-lab:C67FoundationLab' 'c67-trip-integration:C67TripIntegration' 'c67-journey-showcase:C67JourneyShowcase'; do
      app="${definition%%:*}"; scheme="${definition##*:}"
      run_logged "$output_root/ui-$scheme.log" xcodebuild -quiet -project "$journey_root/apps/$app/$scheme.xcodeproj" -scheme "$scheme" \
        -destination "$P3_SIMULATOR_DESTINATION" -derivedDataPath "$output_root/DerivedData-$scheme" \
        -resultBundlePath "$output_root/$scheme.xcresult" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
        ${package_options[@]+"${package_options[@]}"} -parallel-testing-enabled NO test
      printf 'PASS: %s fixture UI tests\n' "$scheme"
    done
    ;;
  native-ui)
    : "${P3_SIMULATOR_DESTINATION:?Choose an installed iOS 26+ Simulator destination}"
    run_logged "$output_root/ui-native-planner.log" xcodebuild -quiet \
      -project "$journey_root/apps/native-routing-lab/poc-c67.xcodeproj" -scheme poc-c67 \
      -destination "$P3_SIMULATOR_DESTINATION" -derivedDataPath "$output_root/DerivedData-poc-c67" \
      -resultBundlePath "$output_root/poc-c67.xcresult" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
      -only-testing:poc-c67UITests/NativePlannerPortabilityTests ${package_options[@]+"${package_options[@]}"} -parallel-testing-enabled NO test
    printf 'PASS: native planner fixture UI regression\n'
    ;;
  *) printf 'Usage: verify.sh context|packages|transjakarta|cli|native|build|journey-models|ui|native-ui\n' >&2; exit 64 ;;
esac
printf 'Evidence directory: %s\n' "$output_root"
