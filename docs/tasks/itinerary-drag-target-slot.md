# Show the target slot during itinerary reorder

Status: Ready for review

Branch: `fix/ui`

## Outcome

Option C gives the lifted stop a moving dashed connector and marks the destination with a blue dashed slot. The destination follows the existing reorder calculation.

## Verification

The focused Pocket integration scenario passed on iPhone 18 Pro Simulator (iOS 27.2) with synthetic data. It moved the last stop into the first slot and checked the new stop order. A screenshot captured during the held drag showed the blue dashed connector beside the lifted stop and the outline around the first slot.
