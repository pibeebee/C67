# Nearby place recommendations

## Outcome and scope

Use the trip starting point for recommendation search and displayed distances. Search MapKit in stages of 10, 20 and 30 km, stopping once there are at least ten unique candidates. Filter each result by straight-line distance, order candidates by distance within each preference group, and interleave the groups. Show the applied radius. Manual place search remains unrestricted by this radius.

When no starting point is available, request a device position or allow a manual starting point before finding recommendations. Preserve selected places during refresh and reject results belonging to an outdated starting point or session. Synthetic mode remains explicitly synthetic.

## Verification and limits

Check the app's trip-creation tests and mock home navigation on the Simulator, the shared Swift package tests, Swift formatting and the diff. The radius and minimum candidate count are initial product choices; validate coverage and relevance with real MapKit results across dense and sparse areas. A straight-line radius does not guarantee a short road journey. Physical-device GPS and live provider results require separate verification.
