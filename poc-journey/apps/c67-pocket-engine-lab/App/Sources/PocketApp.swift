import SwiftUI
import SwiftData

@main
struct PocketApp: App {
    @State private var model = PocketModel()
    private let persistence: Result<ModelContainer, Error> = Result { try ModelContainer(for: SavedWorkspace.self) }
    var body: some Scene {
        WindowGroup {
            switch persistence {
            case .success(let container):
                RootView(model: model)
                    .modelContainer(container)
                    .task {
                        model.attach(container.mainContext)
                        #if DEBUG
                            await SimulatorAcceptance.runIfRequested(model: model)
                            await SimulatorRouting.runIfRequested(apple: model.apple)
                            await SimulatorVisitAdvice.runIfRequested()
                            await SimulatorFlow.runIfRequested(model: model)
                        #endif
                    }
            case .failure(let error):
                ContentUnavailableView("Penyimpanan belum tersedia", systemImage: "externaldrive.badge.exclamationmark", description: Text(error.localizedDescription))
            }
        }
    }
}

@Model
final class SavedWorkspace {
    @Attribute(.unique) var key: String
    var payload: Data
    init(key: String = "workspace", payload: Data) { self.key = key; self.payload = payload }
}

struct RootView: View {
    @Bindable var model: PocketModel
    var body: some View {
        TabView {
            Tab("Jelajah", systemImage: "sparkle.magnifyingglass") { DiscoverScreen(model: model) }
            Tab("Rencana", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { PlanScreen(model: model) }
            Tab("Pengaturan", systemImage: "slider.horizontal.3") { SettingsScreen(model: model) }
        }
        .tint(.teal)
        .alert("Pocket Engine", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("Tutup") { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
}
