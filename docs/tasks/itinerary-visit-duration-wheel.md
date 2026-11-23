# Adopt the native duration picker in Edit visit

Status: Ready for review

Branch: `fix/ui`

## Outcome

The duration-only itinerary sheet follows the approved option C. It shows the place name, a native wheel picker and a blue Update itinerary action at the bottom.

## Scope and verification

The existing timed itinerary editor keeps its schedule fields. The duration-only wheel includes the current duration and standard five-minute choices within the existing bounds. The focused Simulator integration scenario checks the wheel, button placement and the duration after updating and reopening the sheet.

The selected integration test passed on iPhone 18 Pro Simulator (iOS 27.2) with the synthetic Pocket fixture. It checked the place name, moved the native wheel from 45 to 50 minutes, confirmed the action below the wheel, and reopened the editor at 50 minutes after the itinerary refreshed.
