# Deploy Pocket ordering and update the itinerary review

Status: Homelab and focused Simulator checks passed on 15 November 2026.

Branch: `gi/pocket-ui`

## Scope and observed design

The supplied iPhone image shows an editable title and departure, compact
numbered stop cards, travel legs, a map with a disclosure, and distinct start and
save actions. The implementation keeps native navigation. It uses real place
metadata for category and imagery when available and a pin placeholder
otherwise. The photo, temperature and distance values in the supplied design
are illustrative. Consulted Apple's [button](https://developer.apple.com/design/human-interface-guidelines/buttons)
and [layout](https://developer.apple.com/design/human-interface-guidelines/layout)
references on 15 November 2026. This implementation is not a HIG audit.

The device derives the visible times from a default 08:00 departure, six
minutes per leg, and a 30-minute visit only when duration is unknown. The
visit estimates otherwise use the chosen duration or Luna's midpoint. Map
distances measure straight lines. Editing the departure persists the display
preference without another provider call. Behind the scenes shows assumptions
and available evidence without Luna prose.

## Homelab deployment

The target was the existing external Compose project `c67-pocket-beta` at
`/home/giovan/apps/c67-pocket-beta/release/server/pocket/compose.homelab.yml`.
It was serving the catalog v1. The ordering v3 container retains the 8792
origin port, service alias, existing credentials, and `c67-pocket-beta_pocket_data`
volume. Its Nginx allowlist now forwards authenticated order submission and
job polling. The catalog route was retired. Older catalog clients need the
new build. The public hostname and tunnel ingress were reused.

The image was tested separately before the replacement. Staging caught
root-only source permissions, incorrect root-directory resolution in the
container, and an origin port mismatch. The old image is tagged
`c67-pocket-beta-pocket:before-order-20261115`. Rollback Compose and Nginx
configuration, an integrity-checked SQLite catalog backup, and `rollback.sh`
are under `/home/giovan/apps/c67-pocket-beta/rollback-order-20261115`.
The volume stayed mounted. HTTPS briefly returned 502 during container
replacement and recovered once both services started.

## Verification

- Public HTTPS health reported version 3. An unauthenticated order request
  returned 401.
- An authenticated live order over the public HTTPS endpoint returned all
  three public test places. Repeat submission of the same ID reused the job.
  End-to-end response took 78.8 s. Provider reported
  `gpt-6-luna`, `max`, `responses`.
- Three focused synthetic UI scenarios passed on iPhone 18 Pro Max Simulator
  with iOS 27.2. They cover the compact itinerary, edit menu, default
  estimates, exact rename, save for later, and start now.
- 65 Swift package and 39 Python server tests passed. SwiftFormat and
  whitespace checks passed. The iOS 18 deployment target was preserved.
- Release build settings resolve the HTTPS hostname. There is no physical
  iPhone or TestFlight execution evidence for this change.

[Verification summary](../evidence/pocket-homelab-itinerary-hifi-2026-11-15/summary.json) ·
[HTTPS smoke](../evidence/pocket-homelab-itinerary-hifi-2026-11-15/https-order.log) ·
[Itinerary review](../evidence/pocket-homelab-itinerary-hifi-2026-11-15/itinerary-review.png) ·
[Start flow](../evidence/pocket-homelab-itinerary-hifi-2026-11-15/start-from-review.png)
