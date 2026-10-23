import SwiftUI
import C67Domain

struct DiscoveryView: View {
    @State var presenter: DiscoveryPresenter
    let mode: String

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(mode, systemImage: "hammer")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if presenter.isLoading { ProgressView("Loading rundowns…") }
                if let error = presenter.error {
                    Text(error).foregroundStyle(.red)
                    Button("Retry") { Task { await presenter.load() } }
                }
                ForEach(presenter.rundowns) { rundown in
                    NavigationLink(value: DiscoveryRoute.rundown(rundown)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(rundown.title).font(.headline)
                            Text("\(rundown.area) · \(rundown.stops.count) stops")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                if !presenter.isLoading && presenter.rundowns.isEmpty && presenter.error == nil {
                    ContentUnavailableView("No rundowns yet", systemImage: "map")
                }
            }
            .navigationTitle("Discover")
            .navigationDestination(for: DiscoveryRoute.self) { route in
                switch route {
                case .rundown(let rundown): RundownDetailView(rundown: rundown, presenter: presenter)
                }
            }
            .task { await presenter.load() }
            .refreshable { await presenter.load() }
        }
    }
}

private struct RundownDetailView: View {
    let rundown: Rundown
    @Bindable var presenter: DiscoveryPresenter
    @State private var start = Date().addingTimeInterval(86_400)

    var body: some View {
        Form {
            Section("About this rundown") {
                Text(rundown.summary)
                Text(rundown.area).foregroundStyle(.secondary)
            }
            Section("Stops") {
                ForEach(rundown.stops.sorted(by: { $0.order < $1.order })) { stop in
                    Text("\(stop.order + 1). \(stop.title)")
                }
            }
            Section("Your trip") {
                DatePicker("Start", selection: $start)
                Button {
                    Task { await presenter.save(rundown, at: start) }
                } label: {
                    if presenter.isSaving { ProgressView("Saving…") }
                    else { Text("Save as my trip") }
                }
                .disabled(presenter.isSaving)
                if let error = presenter.error { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle(rundown.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Trip saved", isPresented: Binding(
            get: { presenter.savedTrip != nil },
            set: { if !$0 { presenter.dismissResult() } }
        )) {
            Button("OK") { presenter.dismissResult() }
        } message: {
            Text("A personal snapshot was created. In mock mode it lasts until the app closes.")
        }
    }
}
