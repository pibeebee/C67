import SwiftUI
import UIKit
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
    @State private var showsCreation = false
    @State private var tripPath: [UUID] = []
    @State private var historyPath: [UUID] = []
    @State private var location = PlanningLocation()
    @State private var areaLookup: Task<Void, Never>?
    @State private var deviceAreaName: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(presenter: PlanningPresenter, mode: String, accountPresenter: AccountPresenter?) {
        _presenter = State(initialValue: presenter)
        _accountPresenter = State(initialValue: accountPresenter)
        self.mode = mode
    }

    var body: some View {
        Group {
            if showsCreation {
                TripCreationSheet(presenter: $creation, dismiss: dismissCreation, openPocketSettings: showAccount)
                    .transition(.move(edge: .trailing))
            } else {
                homeTabs
                    .transition(.move(edge: .leading))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: showsCreation)
        .tint(.blue)
        .fullScreenCover(item: $sheet.only(\.isFullScreen)) { _ in
            PlanningSearchSheet(near: presenter.origin, title: "Starting point", select: selectLocation)
        }
        .sheet(item: $sheet.only { !$0.isFullScreen }) { route in
            switch route {
            case .location:
                EmptyView()
            case .account:
                if let accountPresenter {
                    AccountView(presenter: accountPresenter, appleOnly: mode == "Pocket • authenticated",
                                withdrawAIConsent: presenter.requiresExternalAIConsent ? { try await presenter.withdrawExternalAIConsent() } : nil)
                } else if presenter.supportsOnDevicePlanning {
                    PocketConnectionView(presenter: presenter, dismiss: dismissSheet)
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
        .task(id: accountPresenter?.deletionPending) { await accountPresenter?.pollPendingDeletion() }
        .task(id: scenePhase) { await restoreWhenActive() }
        .onChange(of: accountPresenter?.account?.id) { _, _ in accountChanged() }
        .onChange(of: presenter.openTripID) { _, id in
            if let id {
                sheet = nil
                showsCreation = false
                creation = nil
                selectedTab = .trip
                tripPath = [id]
                presenter.openTripID = nil
            }
        }
        .onChange(of: location.point) { _, point in
            if let point, presenter.origin == nil, presenter.firstItineraryJob == nil {
                presenter.receivedLocation(point)
                presenter.draftChanged()
                areaLookup?.cancel()
                areaLookup = Task {
                    let name = await LocationAreaName.resolve(point)
                    guard !Task.isCancelled, presenter.origin == point, presenter.originLabel == "Current device position" else { return }
                    if let name { deviceAreaName = name; presenter.originLabel = name }
                }
            }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab != .trip { location.cancel() }
        }
        .onOpenURL(perform: handleCallback)
    }

    private var homeTabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Trip", systemImage: "location", value: .trip) {
                NavigationStack(path: $tripPath) {
                    TripHomeContentView(presenter: presenter, mode: mode, showAccount: showAccount, planTrip: addTrip, resumeDraft: resumeCreation)
                        .safeAreaInset(edge: .top, spacing: 0) {
                            VStack(alignment: .leading, spacing: 4) {
                                TripHomeHeader(locationTitle: locationTitle,
                                               chooseLocation: chooseLocation, addTrip: addTrip, addSpecificPlace: addSpecificPlace,
                                               isBusy: presenter.isBusy, isLocating: location.isRequesting,
                                               accessibilityLocationTitle: presenter.origin == nil ? nil : presenter.originLabel)
                                if presenter.origin == nil, !location.isRequesting {
                                    VStack(alignment: .leading, spacing: 6) {
                                        if location.permissionDenied {
                                            Text("Location access is off").foregroundStyle(.secondary)
                                            Button("Open Settings") {
                                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                                            }
                                        } else if location.error != nil {
                                            Text("Couldn’t get your location").foregroundStyle(.secondary)
                                        }
                                        Button("Use current location", systemImage: "location") { location.request() }
                                            .accessibilityIdentifier("homeUseCurrentLocation")
                                    }
                                    .font(.subheadline)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 8)
                                }
                            }
                        }
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
                        .safeAreaInset(edge: .top, spacing: 0) {
                            HStack {
                                Text("History")
                                    .font(.largeTitle.bold())
                                    .accessibilityAddTraits(.isHeader)
                                Spacer()
                                Button(action: showAccount) {
                                    Label("Account", systemImage: "person.crop.circle")
                                        .labelStyle(.iconOnly)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.tint)
                                        .padding(7)
                                        .background(.tint.opacity(0.18), in: .circle)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                        }
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: UUID.self) { id in
                            SavedTripView(tripID: id, presenter: presenter)
                                .toolbar(.visible, for: .navigationBar)
                        }
                }
            }
        }
    }

    private func addTrip() { beginCreation(specificPlace: false) }
    private func addSpecificPlace() { beginCreation(specificPlace: true) }

    private func beginCreation(specificPlace: Bool) {
        guard !presenter.isBusy else { return }
        location.cancel()
        Task {
            if let pending = await presenter.recoverPendingCreation() {
                resumeCreation(pending)
            } else {
                presenter.startNewTrip()
                creation = TripCreationAssembly.makePresenter(planning: presenter, mode: mode, specificPlace: specificPlace)
                showsCreation = true
            }
        }
    }
    private func resumeCreation(_ job: PlanningJob) {
        location.cancel()
        let draft = TripCreationAssembly.makePresenter(planning: presenter, mode: mode, specificPlace: true)
        draft.openFirstItinerary(job)
        creation = draft
        showsCreation = true
    }

    private func chooseLocation() {
        location.cancel()
        sheet = .location
    }
    private var locationTitle: String {
        if presenter.origin != nil {
            if presenter.originLabel == deviceAreaName, let name = deviceAreaName {
                return LocationAreaName.shortName(name)
            }
            return presenter.originLabel
        }
        return presenter.originLabel
    }
    private func showAccount() { sheet = .account }
    private func dismissSheet() { sheet = nil }
    private func dismissCreation() { showsCreation = false }

    private func selectLocation(_ place: PlanningPlace) {
        areaLookup?.cancel()
        deviceAreaName = nil
        location.cancel()
        presenter.origin = place.location
        presenter.originLabel = place.name
        presenter.draftChanged()
    }

    private func restoreWhenActive() async {
        guard scenePhase == .active else { return }
        await accountPresenter?.restore()
        await presenter.load(waitForFirstItinerary: false)
    }

    private func reload() { Task { await presenter.load() } }

    private func accountChanged() {
        location.cancel()
        areaLookup?.cancel()
        deviceAreaName = nil
        creation = nil
        sheet = nil
        showsCreation = false
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
