import SwiftUI

/// The previous experiment is preserved in `LegacyPOCView.swift`.
struct ContentView: View {
    let app: POCController

    @ViewBuilder
    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("--legacy-poc") {
            LegacyPOCView(app: app)
        } else if ProcessInfo.processInfo.arguments.contains("--diary-demo")
            || ProcessInfo.processInfo.arguments.contains("--diary-ui-testing") {
            TravelDiaryView()
        } else {
            NativeTripPlannerView()
        }
    }
}
