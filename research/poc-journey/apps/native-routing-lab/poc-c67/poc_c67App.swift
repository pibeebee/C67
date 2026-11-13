import SwiftUI

@main struct poc_c67App: App {
    @UIApplicationDelegateAdaptor(POCAppDelegate.self) private var delegate
    @State private var controller: POCController?
    @State private var bootError: String?
    var body: some Scene {
        WindowGroup {
            Group {
                if NativeTripLaunchRouting.usesNativePlanner(arguments: ProcessInfo.processInfo.arguments) {
                    if WeatherLabLaunchRouting.showsLab(arguments: ProcessInfo.processInfo.arguments) {
                        WeatherLabRootView()
                    } else { NativeTripPlannerView() }
                } else if let controller {
                    if ProcessInfo.processInfo.arguments.contains("--large-text") {
                        ContentView(app: controller).environment(\.dynamicTypeSize, .accessibility3)
                    } else { ContentView(app: controller) }
                }
                else {
                    ContentUnavailableView {
                        Label("POC C67", systemImage: "person.3")
                    } description: {
                        Text(bootError ?? "Membuka penyimpanan lokal…")
                    } actions: {
                        if bootError != nil { Button("Coba buka lagi — tanpa menghapus data") { bootstrap() } }
                    }.task { bootstrap() }
                }
            }
        }
    }
    private func bootstrap() {
        guard controller == nil else { return }
        do {
            let preview = ProcessInfo.processInfo.arguments.contains("--demo-preview")
            let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing") || preview
            controller = try POCController(container: SessionStore.container(inMemory: testing), testing: testing)
            if preview { try controller?.loadDemo(.regroup) }
            #if DEBUG
                if testing, ProcessInfo.processInfo.arguments.contains("--ui-itinerary-participant"), let app = controller {
                    try app.loadDemo(.regroup)
                    try app.store.commit { $0.joinedQR = JoinedJourney(journey: "Tur Jakarta", leader: "Budi", leaderRecord: "_fixture", participantID: "P01", participantName: "Ayu") }
                }
                if testing, ProcessInfo.processInfo.arguments.contains("--ui-real-map-fixture"), let app = controller {
                    try app.store.commit { $0.mode = .real }
                }
                if testing, ProcessInfo.processInfo.arguments.contains("--ui-resume-fixture"), let app = controller {
                    let ref = app.cloud.makeReference(runID: app.store.state.runID, participantID: UUID().uuidString)
                    try app.store.commit {
                        $0.mode = .real; $0.owner = ref
                        $0.joinedQR = JoinedJourney(journey: "Tur Jakarta", leader: "Budi", leaderRecord: "_uiFixture", participantID: ref.participantID, participantName: "Ayu")
                    }
                }
            #endif
            bootError = nil
        } catch { bootError = "Penyimpanan tidak dapat dibuka. Data tidak direset otomatis. \(error.localizedDescription)" }
    }
}
