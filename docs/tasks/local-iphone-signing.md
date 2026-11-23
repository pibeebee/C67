# Task: Run Travelants on an iPhone with a local development team

Status: Done

Branch: `fix/ui`

## Outcome

The C67 Debug scheme can use a developer-owned app identifier for iPhone runs. Release builds use the TestFlight identity and entitlements.

## Scope and dependencies

Use the ignored iOS development configuration for the local team and bundle identifier. An iPhone run requires a valid development certificate and provisioning profile for that team. The local configuration can omit Apple entitlements when the team cannot provision them.

## References

- [Development configuration example](../../apps/ios/Configuration/Development.example.xcconfig)
- [Native Sign in with Apple setup](../guides/apple-auth.md)
- [TestFlight release procedure](../operations/testflight.md)

## Acceptance criteria and verification

- [x] Xcode resolves the local team and bundle identifier for Debug on iOS.
- [x] Xcode resolves the TestFlight team, bundle identifier and entitlements for Release on iOS.
- [x] Xcode resolves the shared bundle identifier for Debug on Simulator.
- [x] Build the Debug app for Simulator, verify the iOS code signature and install the app on the paired iPhone.

## Result and handoff

The existing `C67.entitlements` file is assigned in the app’s base configuration. The optional development override can clear that assignment for Debug on iOS devices and select its own team and bundle identifier.

With Xcode 27.2, `xcodebuild -showBuildSettings -json` confirmed the build settings for Debug on iOS, Release on iOS and Debug on Simulator. The generic Debug builds passed for iOS and iOS Simulator. `codesign --verify --deep --strict` passed for the iOS app, and `xcrun devicectl device install app` installed it on the paired iPhone 17 with an existing development profile. iOS declined to launch the app while the phone was locked.
