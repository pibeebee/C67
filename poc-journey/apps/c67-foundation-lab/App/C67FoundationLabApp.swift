import SwiftUI
import TripIntelligence

@main struct C67FoundationLabApp: App {
    @State private var model = LabModel()
    @State private var selection = 2
    var body: some Scene {
        WindowGroup {
            TabView(selection: $selection) {
                Tab("01 · FM", systemImage: "sparkles", value: 1) {
                    RecommendationRootView(legacy: model).task { await model.load() }
                }
                Tab("02 · Minat", systemImage: "heart.text.clipboard", value: 2) {
                    PreferenceLabView()
                }
                Tab("03 · Waktu", systemImage: "clock.badge.checkmark", value: 3) {
                    VisitTimingLabView()
                }
                Tab("04 · Cocok", systemImage: "checkmark.seal", value: 4) {
                    QualityLabView()
                }
                Tab("05 · E5", systemImage: "text.magnifyingglass", value: 5) {
                    BenefitLabView()
                }
            }
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("--fixture-ui")
                    || ProcessInfo.processInfo.arguments.contains("--recommendation-smoke")
                    || ProcessInfo.processInfo.arguments.contains("--live-smoke")
                {
                    selection = 1
                }
                if ProcessInfo.processInfo.arguments.contains("--timing-ui")
                    || ProcessInfo.processInfo.arguments.contains("--timing-smoke")
                {
                    selection = 3
                }
                if ProcessInfo.processInfo.arguments.contains("--quality-ui")
                    || ProcessInfo.processInfo.arguments.contains("--quality-smoke")
                {
                    selection = 4
                }
                if ProcessInfo.processInfo.arguments.contains("--benefit-ui")
                    || ProcessInfo.processInfo.arguments.contains("--benefit-smoke")
                    || ProcessInfo.processInfo.arguments.contains("--benefit-suite")
                {
                    selection = 5
                }
            }
        }
    }
}
