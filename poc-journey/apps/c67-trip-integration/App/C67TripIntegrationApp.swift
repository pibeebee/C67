import SwiftUI

@main struct C67TripIntegrationApp: App {
    @State private var model = IntegrationModel()
    var body: some Scene {
        WindowGroup {
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--p3-live-eval") {
                    LiveEvaluationView()
                } else {
                    IntegrationHome(model: model).task { await model.load() }
                }
            #else
                IntegrationHome(model: model).task { await model.load() }
            #endif
        }
    }
}
