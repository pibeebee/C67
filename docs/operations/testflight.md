# TestFlight release procedure

Open `apps/ios/C67.xcodeproj` and use the C67 scheme. The app targets iOS 18+, uses bundle ID `io.pibeebee.c67.starter`, and is named Travelant. Signing requires the matching Apple Developer team. Apple account access, current review status, and live service health must be checked for each release.

## Prepare a build

1. Set `pocket-auth`, the intended Pocket HTTPS host and the Supabase HTTPS host with its publishable/anon client key in ignored `apps/ios/Configuration/Production.local.xcconfig`, using the [example](../../apps/ios/Configuration/Production.example.xcconfig). The client key is public; server read tokens, service-role credentials and provider keys stay out of the app bundle. Testers sign in with Apple and do not enter a server URL or token.
2. Enable WeatherKit in both App Capabilities and App Services for the app identifier. Refresh signing profiles after changes.
3. Choose a new build number, build a generic iOS device archive, validate it, and upload with the TestFlight & App Store method.
4. Answer export-compliance questions for the actual code in this build. The present app uses Apple platform cryptographic facilities. Reassess when its implementation changes.
5. Verify the uploaded build's processing/compliance status in App Store Connect.

## External beta

Create an internal group before the external group. Complete the beta description, feedback address, reviewer contact, and test instructions. The `pocket-auth` flow requires Sign in with Apple. The Pocket server must first be deployed and verified in `authenticated` mode against the same Supabase project; do not put a shared Pocket token in reviewer notes or the app. Existing unauthenticated local trip files are preserved but are not automatically assigned to an account.

Select the build in the external group, enter What to Test, and submit to Beta App Review. Review submission and actual tester availability are different states. After approval, start testing if automatic distribution is disabled, then verify the public link on a compatible device. The current beta group was prepared for up to 20 iPhone testers. Share the beta access code separately with invited testers.

## Release evidence

Record archive/build identifiers, the repository revision and any local differences, Xcode version, validation/upload results, and known device/provider gaps. Keep raw signing logs, provisioning profiles, IPA archives, and credentials outside Git. Folder restructuring does not alter an already uploaded build.

See [Apple's distribution guide](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases/) and [external tester setup](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers).
