# Privacy Policy release handoff

`index.html` is the policy published at [travelants.giovanc.com/privacy-policy/](https://travelants.giovanc.com/privacy-policy/). It names the operator and the hours endpoint verified on the production Pocket container. Retention durations for logs, backups, and support emails still need an operating record. The published policy describes their purpose and distinguishes live records from recovery copies.

Reconcile these data flows against the proposed release before answering App Privacy:

| Flow | Data and handling to verify |
| --- | --- |
| Supabase Auth | Account ID, contact email or relay address, provider identity and sessions. Email address and user ID are the relevant candidate types for app functionality. Confirm linkage and actual retention. |
| Itineraries and maps | Itineraries stay on the device in Pocket mode. MapKit receives inputs for searches and routes. Check whether this release sends precise or coarse location off device, the recipients, and whether any party keeps it beyond the live request. |
| Opening hours and weather | Authenticated Pocket hours checks use Apple place identifiers. Confirm retention in Pocket, its upstream service, and ingress logs. Confirm the active weather path for each shipping itinerary mode, including Apple Weather and whether any Open-Meteo path is reachable with external AI disabled. |
| External AI and earlier betas | Keep the AI recipient and disclosure version empty for 1.0. Confirm whether the operator retains any authenticated jobs, snapshots or provider copies from previous beta builds. Verify policy scope and retention for any data that remains. |
| Account deletion | Check real Apple access removal, Supabase account and journal cleanup, Pocket job and snapshot cleanup, and local cleanup. Check the deletion receipt retention, backups, and any older unlinked records. |
| Tracking and diagnostics | Review SDKs, production logs and integrations before declaring purpose, linkage or tracking. The bundled required-reason API manifest does not provide these App Store answers. |

For each flow, record whether the data leaves the device and is retained beyond processing the request, who receives it, the purpose, whether it is linked to the user, and whether it is used for tracking. Keep the label answers pending until the team verifies those facts. [Apple's App Privacy definitions](https://developer.apple.com/app-store/app-privacy-details/)

The [public support page](https://travelants.giovanc.com/support/) links to the policy. App Store Connect and the ignored `apps/ios/Configuration/Production.local.xcconfig` use the same address:

```xcconfig
TRAVELANTS_PRIVACY_POLICY_URL = https:/$()/travelants.giovanc.com/privacy-policy/
TRAVELANTS_AI_RECIPIENT =
TRAVELANTS_AI_DISCLOSURE_VERSION =
```

Verify the release bundle's `Info.plist`, open the policy before sign-in and from Account, and test that the itinerary goes straight to local planning. Earlier TestFlight binaries are outside this release configuration. If a future release enables external AI, verify the actual proxy and upstream recipients, their data terms, and retention. Update the policy and disclosure version when the shared data, purposes or recipients change, then verify that granting and withholding consent both work on device.
