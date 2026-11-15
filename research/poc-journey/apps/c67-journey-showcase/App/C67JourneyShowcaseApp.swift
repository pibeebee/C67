import SwiftUI

@main struct C67JourneyShowcaseApp: App {
    @State private var model = JourneyModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            JourneyHome(model: model)
                .task {
                    await model.load()
                    #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("--journey-live-check") { await model.runLiveCheck() }
                    #endif
                }
                .onChange(of: scenePhase) { _, value in
                    if value == .background { model.cancel(); model.roadRoutes.cancel(); model.persist() }
                }
        }
    }
}
