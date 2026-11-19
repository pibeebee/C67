# Task: Prepare Travelants 1.0 for App Review

Status: In progress\
Branch: `gi/travelant-p1`

## Outcome

Prepare a signed 1.0 candidate with published Support and Privacy Policy URLs, iPhone and 13-inch iPad screenshots, and a dedicated App Review sign-in. Keep Sign in with Apple as the standard sign-in. Hand over the completed App Store Connect draft to the team before submission.

## Scope and dependencies

- Use the existing authenticated Pocket service, local itinerary scheduling, and account deletion. External AI is disabled for this candidate.
- Reviewers open **App Review Sign-In** and use the private Sign-In Information in App Store Connect. Keep the primary account available for itinerary testing. Put the disposable account in private Review Notes so permanent deletion can be checked separately. Configure only the account emails in the release bundle. Store passwords in Keychain and the private App Review form.
- [Listing copy and review notes](../product/app-store-1-0.md), [Support page](../product/support/index.html) and [Privacy Policy](../product/privacy-policy/index.html) are maintained in the workspace.
- Prepare the draft for the existing Travelants app record. Submission remains a separate action.

## Acceptance

- [ ] Support and Privacy Policy open on public HTTPS URLs without authentication. The app and App Store Connect use the same Privacy Policy URL.
- [ ] App Privacy answers match the release build and verified provider practices. Copyright and review contact use approved names.
- [ ] iPhone and 13-inch iPad assets show the current app with public example locations and no personal information.
- [ ] The signed candidate reports version 1.0, an unused build number, an HTTPS privacy link and no configured external AI recipient or disclosure version.
- [ ] Simulator regressions pass. On a physical iPhone, test sign-in, a real route, save/reopen, and account deletion using an authorized disposable account.
- [ ] App Store Connect shows the processed 1.0 build attached to the version draft with its listing, review access, compliance and device assets.

## Verification

Check document links and placeholders, inspect the signed bundle's public configuration, record simulator versus physical-device evidence in [verification](../testing/verification.md), and confirm the exact uploaded build in App Store Connect.

## Current handoff

- Build `1.0 (202611192232)` supersedes `202611192215`. App Store Connect shows Ready for Review after the new build passed export compliance and both demo accounts were configured in the private review form. The account holder reported submitting for review on 20 November 2026. China mainland is excluded.
- The production sign-in and disposable-account deletion API checks passed. The new build is installed on Giovan’s iPhone, but the device was locked, so the physical itinerary walkthrough remains pending.

- The [Support](https://travelants.giovanc.com/support/) and [Privacy Policy](https://travelants.giovanc.com/privacy-policy/) pages are served by the Travelants Worker. Both URLs returned HTTP 200 and are saved in App Store Connect.
- Build `1.0 (202611192215)` was uploaded, cleared export compliance and is attached to the 1.0 draft. The archive includes the public Privacy Policy URL and leaves external AI disabled.
- Three iPhone screenshots are attached in order Slide 2, Slide 1, Slide 3. One iPad 13-inch Preferences screenshot is attached from the Simulator capture.
- Production retention and reviewer sign-in confirmation are pending. Reserve the physical-device walkthrough for the configured candidate. Check compact-device reorder during that walkthrough.

## Submission settings

- App Store Connect saved free pricing, all 175 storefronts as the intended availability, Copyright `2026 Giovan Christoffel Sihombing`, and the calculated age rating of 13+. The rating includes infrequent alcohol references from venue categories. Availability remains subject to territory compliance and release.
- App Review contact and phone are saved. The [sign-in question for Apple](../product/app-review-sign-in-request.md) is ready for the team to send. Content Rights and DSA Non-trader were saved after the account holder confirmed both.
- App Privacy responses and an end-to-end physical-device check of this build are pending. All 157 C67Backend tests passed. The signed build installed on Giovan’s iPhone 17, and iOS denied launch while the phone was locked. The version remains in Prepare for Submission.
