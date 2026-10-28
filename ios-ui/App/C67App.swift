import SwiftUI

@main
struct C67App: App {
    var body: some Scene {
        WindowGroup { StarterRootView() }
    }
}

private struct StarterRootView: View {
    @State private var result = Result { try AppDependencies.make() }
    var body: some View {
        switch result {
        case .success(let dependencies):
            DiscoveryAssembly.make(repository: dependencies.repository, mode: dependencies.mode,
                                   authentication: dependencies.authentication)
        case .failure(let error):
            ContentUnavailableView("Configuration needed", systemImage: "gearshape",
                                   description: Text(error.localizedDescription))
        }
    }
}
