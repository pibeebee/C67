# Travelants 1.0 App Store copy and review packet

## English (U.S.) listing draft

**Name** · Travelants\
**Subtitle** · Plan a day out\
**Primary category** · Travel\
**Keywords** · itinerary,trip planner,nearby places,opening hours,day trip,route,Jakarta

### Description

Plan a day out around the places you want to visit. Pick your interests to find places nearby, or add specific places you already have in mind.

Choose a place to spend more time at, or let Travelants decide. Travelants builds a schedule around travel estimates and opening hours, and can suggest tomorrow if the trip does not fit today. Review the proposed stops, adjust their order, and save the itinerary on your device.

When you are ready to leave, open your saved itinerary and see which stop is next. Open Apple Maps for directions. Check opening hours and travel estimates before you go.

### Fields to complete with the team

| App Store Connect field | Value or dependency |
| --- | --- |
| Support URL | [Travelants Support](https://travelants.giovanc.com/support/). Saved in the 1.0 draft. |
| Privacy Policy URL | [Travelants Privacy Policy](https://travelants.giovanc.com/privacy-policy/). Saved in App Store Connect and verified in the signed 1.0 archive. |
| Copyright | Year the rights were obtained, followed by the exact name of the rights holder. Confirm the name and year. |
| App Privacy | Confirm provider and retention facts in the [data inventory](privacy-policy/README.md) before publishing the answers. |
| App Review contact | Name, monitored email and phone number of the contact designated by the team. |
| Pricing, territories and release | Check the existing draft against the team's release decision. For the first listing, copy only confirmed choices. |

Use the submitted build's features to answer age rating, content rights and any export or territory questions. Review the exact answers on App Store Connect with the account holder.

## App Review Notes draft

Travelants helps people in Jakarta choose places to visit and turn those choices into a day itinerary. Version 1.0 uses local scheduling. Place search and routing use Apple Maps, weather uses Apple Weather when available, and account sign-in uses Sign in with Apple with Supabase Auth. Travelants uses its Pocket service for supported opening-hour checks and account deletion.

1. On the welcome screen, tap **App Review Sign-In** and enter the credentials in **Sign-In Information**.
2. On Home, set the starting point to **Blok M MRT, Jakarta** using manual place search. This lets you test the app from another region.
3. Open the trip creation menu and choose **Get Recommendations**. Pick an interest and proceed. Select **Taman Bendera Pusaka** from recommendations or add it through **My Places** using the place search.
4. Keep **Let Travelants decide** on the main spot screen and tap **Next**. Review the itinerary and save it. If today's travel or opening-hours window is too short, check the suggested alternative date.
5. Reopen the saved trip to inspect the itinerary. To review deletion, sign out and use the disposable account supplied in private Review Notes. Open **History → Account → Delete Account**, confirm the deletion, and wait for the app to return to the welcome screen. The standard Sign in with Apple account flow uses Apple verification when deleting an account.

Insert the disposable account credentials only in the private App Store Connect review form. Verify the example against the uploaded build before submission.

[Apple's metadata guide](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/) · [Apple's App Review guide](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review)
