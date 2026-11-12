import SwiftUI
import C67Domain
#if DEBUG
    import C67Data
#endif

struct TripHomeRootView: View {
    @State private var presenter: PlanningPresenter
    let mode: String
    @State private var accountPresenter: AccountPresenter?
    @State private var selectedTab: TripHomeTab = .trip
    @State private var creation: TripCreationPresenter?
    @State private var sheet: TripHomeSheet?
    @State private var tripPath: [UUID] = []
    @State private var historyPath: [UUID] = []
    @State private var location = PlanningLocation()
    @Environment(\.scenePhase) private var scenePhase

    init(presenter: PlanningPresenter, mode: String, accountPresenter: AccountPresenter?) {
        _presenter = State(initialValue: presenter)
        _accountPresenter = State(initialValue: accountPresenter)
        self.mode = mode
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Trip", systemImage: "location", value: .trip) {
                NavigationStack(path: $tripPath) {
                    TripHomeContentView(presenter: presenter, mode: mode, showAccount: showAccount)
                        .safeAreaInset(edge: .top, spacing: 0) {
                            TripHomeHeader(locationTitle: presenter.originLabel,
                                           chooseLocation: chooseLocation, addTrip: addTrip, addSpecificPlace: addSpecificPlace,
                                           isBusy: presenter.isBusy,
                                           isLocating: location.isRequesting)
                        }
                        .task { locateWhenNeeded() }
                        .background(Color("TripCanvas"))
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: UUID.self) { id in
                            SavedTripView(tripID: id, presenter: presenter)
                                .toolbar(.visible, for: .navigationBar)
                        }
                }
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: .history) {
                NavigationStack(path: $historyPath) {
                    TripHomeContentView(presenter: presenter, isHistory: true, mode: mode, showAccount: showAccount)
                        .background(Color("TripCanvas"))
                        .navigationTitle("History")
                        .navigationDestination(for: UUID.self) { id in
                            SavedTripView(tripID: id, presenter: presenter)
                        }
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Account", systemImage: "person.crop.circle", action: showAccount)
                            }
                        }
                }
            }
        }
        .tint(.blue)
        .sheet(item: $sheet) { route in
            switch route {
            case .planning, .specificPlace:
                TripCreationSheet(presenter: $creation, dismiss: dismissSheet)
            case .location:
                PlanningSearchSheet(near: presenter.origin, title: "Starting point", select: selectLocation)
            case .account:
                if presenter.supportsOnDevicePlanning {
                    PocketConnectionView(presenter: presenter, dismiss: dismissSheet)
                } else if let accountPresenter {
                    AccountView(presenter: accountPresenter)
                } else {
                    NavigationStack {
                        ContentUnavailableView("Sign-in needs live mode", systemImage: "person.crop.circle",
                                               description: Text("Mock mode uses synthetic data and memory-only trips."))
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done", action: dismissSheet)
                                }
                            }
                    }
                }
            }
        }
        .modifier(AppleCredentialRevocationModifier { Task { await accountPresenter?.restore() } })
        .task { await accountPresenter?.observe() }
        .task(id: scenePhase) { await restoreWhenActive() }
        .onChange(of: accountPresenter?.account?.id) { _, _ in accountChanged() }
        .onChange(of: presenter.openTripID) { _, id in
            if let id {
                sheet = nil
                creation = nil
                selectedTab = .trip
                tripPath.append(id)
                presenter.openTripID = nil
            }
        }
        .onChange(of: location.point) { _, point in
            if let point {
                presenter.receivedLocation(point)
                presenter.draftChanged()
            }
        }
        .onOpenURL(perform: handleCallback)
    }

    private func addTrip() { beginCreation(specificPlace: false) }
    private func addSpecificPlace() { beginCreation(specificPlace: true) }

    private func beginCreation(specificPlace: Bool) {
        let root: TripCreationRoute = specificPlace ? .places : .question(.interests)
        if creation?.root != root {
            creation = TripCreationAssembly.makePresenter(planning: presenter, mode: mode, specificPlace: specificPlace)
        }
        sheet = specificPlace ? .specificPlace : .planning
    }
    private func chooseLocation() { sheet = .location }
    private func showAccount() { sheet = .account }
    private func dismissSheet() { sheet = nil }

    /// Sketch HI-FI `HOME LOCATION PERMIS`: with no starting point yet, Home asks for the
    /// device position. The system shows its own permission alert the first time; the location
    /// pill reads "Locating…" until a position or an error arrives.
    private func locateWhenNeeded() {
        guard presenter.origin == nil, !location.isRequesting else { return }
        location.request()
    }

    private func selectLocation(_ place: PlanningPlace) {
        location.cancel()
        presenter.origin = place.location
        presenter.originLabel = place.name
        presenter.draftChanged()
    }

    private func restoreWhenActive() async {
        guard scenePhase == .active else { return }
        await accountPresenter?.restore()
        await presenter.load()
    }

    private func reload() { Task { await presenter.load() } }

    private func accountChanged() {
        creation = nil
        sheet = nil
        tripPath = []
        historyPath = []
        reload()
    }

    private func handleCallback(_ url: URL) {
        sheet = .account
        Task { await accountPresenter?.callback(url) }
    }
}

#if DEBUG
    @MainActor private func homeEmptyPreview() -> some View {
        let presenter = PlanningPresenter(
            interactor: PlanningInteractor(repository: MockPlanningRepository()),
            initialInput: try? MockPlanningRepository.sampleInput()
        )
        return TripHomeRootView(presenter: presenter, mode: "Mock • memory only", accountPresenter: nil)
    }

    #Preview("HOME EMPTY · Light") {
        homeEmptyPreview()
            .preferredColorScheme(.light)
    }

    #Preview("HOME EMPTY · Dark") {
        homeEmptyPreview()
            .preferredColorScheme(.dark)
    }

    #Preview("HOME EMPTY ADD TRIP · Tap plus") {
        homeEmptyPreview()
            .preferredColorScheme(.light)
    }
#endif
