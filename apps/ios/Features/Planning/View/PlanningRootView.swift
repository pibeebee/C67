import SwiftUI
import MapKit
import C67Domain

struct PlanningRootView: View {
    @State private var presenter: PlanningPresenter
    @State private var accountPresenter: AccountPresenter?
    @State private var showsAccount = false
    @State private var selectedTab: MainTab = .discover
    @State private var selectedJourneySection: JourneySection = .plan
    @State private var selectedCategory: SampleCategory?
    @State private var searchText = ""
    @Environment(\.scenePhase) private var scenePhase
    let mode: String

    init(presenter: PlanningPresenter, mode: String, accountPresenter: AccountPresenter?) {
        _presenter = State(initialValue: presenter); _accountPresenter = State(initialValue: accountPresenter); self.mode = mode
    }
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DiscoverSliceView(selectedCategory: $selectedCategory) { selectedTab = .search }
                    .toolbar { accountButton }
            }.tabItem { Label("Discover", systemImage: "house") }.tag(MainTab.discover)
            NavigationStack {
                VStack(spacing: 0) {
                    Picker("Journey section", selection: $selectedJourneySection) {
                        Text("Plan").tag(JourneySection.plan)
                        Text("My Trips").tag(JourneySection.trips)
                    }.pickerStyle(.segmented).padding()
                    if selectedJourneySection == .plan {
                        PlanningEditorView(presenter: presenter, mode: mode)
                    } else {
                        journeyTrips
                    }
                }
                .navigationTitle(selectedJourneySection == .plan ? "Plan your trip" : "My Trips")
                .toolbar { accountButton }
                .navigationDestination(item: $presenter.openTripID) { id in ActivePlanningTripView(tripID: id, presenter: presenter) }
            }.tabItem { Label("Journey", systemImage: "map") }.tag(MainTab.journey)
            NavigationStack {
                ContentUnavailableView("No bookmarks yet", systemImage: "bookmark", description: Text("Bookmarks will appear here."))
                    .navigationTitle("Bookmark")
            }.tabItem { Label("Bookmark", systemImage: "bookmark") }.tag(MainTab.bookmark)
            NavigationStack {
                SearchSliceView(query: $searchText, selectedCategory: $selectedCategory)
                    .toolbar { accountButton }
            }.tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(MainTab.search)
        }
        .sheet(isPresented: $showsAccount) {
            if let accountPresenter { AccountView(presenter: accountPresenter) }
            else {
                NavigationStack {
                    ContentUnavailableView("Sign-in needs live mode", systemImage: "person.crop.circle", description: Text("Mock mode uses synthetic data and memory-only trips."))
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsAccount = false } } }
                }
            }
        }
        .modifier(AppleCredentialRevocationModifier { Task { await accountPresenter?.restore() } })
        .task { await accountPresenter?.observe() }
        .task(id: accountPresenter?.deletionPending) { await accountPresenter?.pollPendingDeletion() }
        .task(id: scenePhase) {
            if scenePhase == .active { await accountPresenter?.restore(); await presenter.load() }
        }
        .onChange(of: accountPresenter?.account?.id) { _, _ in Task { await presenter.load() } }
        .onOpenURL { url in showsAccount = true; Task { await accountPresenter?.callback(url) } }
    }
    @ToolbarContentBuilder private var accountButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { Button("Account", systemImage: "person.crop.circle") { showsAccount = true } }
    }

    private var journeyTrips: some View {
        List {
            Section { Text(mode).font(.caption).foregroundStyle(.secondary) }
            if let error = presenter.tripListError {
                RecoveryNotice(title: "Couldn’t load trips", message: error,
                               primary: presenter.privateAccessBlocked
                                   ? .init(title: "Sign in") { showsAccount = true }
                                   : .init(title: "Try again") { Task { await presenter.load(resumesJobs: false) } })
            }
            ForEach(presenter.trips) { trip in
                NavigationLink {
                    ActivePlanningTripView(tripID: trip.id, presenter: presenter)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(trip.title).font(.headline)
                        Text("\(trip.plan.stops.count) stops · \(trip.status.rawValue)").font(.subheadline).foregroundStyle(.secondary)
                        if trip.synthetic { Text("Synthetic demonstration").font(.caption) }
                    }
                }
            }
            if presenter.trips.isEmpty, presenter.tripListError == nil {
                ContentUnavailableView("No personal trips", systemImage: "map", description: Text("Choose places, review a proposal, and save your trip."))
            }
        }.refreshable { await presenter.load(resumesJobs: false) }
    }
}

private enum JourneySection { case plan, trips }

private enum PlaceSearchPurpose: String, Identifiable { case origin, destination; var id: String { rawValue } }

struct PlanningEditorView: View {
    @Bindable var presenter: PlanningPresenter
    @State private var searchPurpose: PlaceSearchPurpose?
    @State private var location = PlanningLocation()
    @State private var reviewProposal: ItineraryReviewRoute?
    @State private var isProcessingRecommendations = false
    @State private var showsRecommendations = false
    @State private var recommendations: PlanningResult?
    @State private var recommendationsInput: PlanningInput?
    @State private var selectedRecommendations: [RecommendedPlace] = []
    @State private var recommendationError: String?
    @State private var didOpenPlaceSearch = false
    let mode: String
    var usesItineraryReview = false
    var opensPlaceSearch = false

    var body: some View {
        Form {
            Section {
                Label(mode, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                if mode.hasPrefix("Mock") { Text("All route, AI and weather results are synthetic. Trips last until the app closes.").font(.footnote) }
            }
            Section("Your starting point") {
                Text(presenter.originLabel)
                Button("Search starting point", systemImage: "magnifyingglass") { searchPurpose = .origin }
                Button("Use current location", systemImage: "location") { location.request() }
                if location.isRequesting { ProgressView("Getting your position…") }
                if let error = location.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
            }.disabled(presenter.isBusy)
            Section("Your places") {
                ForEach($presenter.places) { $place in PlanningPlaceEditor(place: $place, zone: presenter.timeZone, defaultStart: presenter.startsAt) }
                    .onDelete { presenter.places.remove(atOffsets: $0) }
                Button("Add a place", systemImage: "plus") { searchPurpose = .destination }
                    .disabled(presenter.places.count >= 6)
                Text("Choose one to six places. Visit durations and preferred windows can be adjusted.").font(.footnote).foregroundStyle(.secondary)
            }.disabled(presenter.isBusy)
            Section("Your time and preferences") {
                TextField("Trip title", text: $presenter.title)
                TextField("What would you enjoy?", text: $presenter.preferences, axis: .vertical).lineLimit(2 ... 5)
                DatePicker("Depart", selection: $presenter.startsAt)
                DatePicker("Finish by", selection: $presenter.finishBy)
                TextField("Destination time zone", text: $presenter.timeZone).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("Travel mode", selection: $presenter.mode) {
                    Text("Walking").tag(PlanningMode.walking)
                    Text("Driving").tag(PlanningMode.automobile)
                }
                Text("Finish by means the end of your final visit. No return-home leg is added automatically.").font(.footnote).foregroundStyle(.secondary)
            }.environment(\.timeZone, TimeZone(identifier: presenter.timeZone) ?? .current).disabled(presenter.isBusy)
            if !presenter.places.isEmpty { PlanningMapSection(places: presenter.places, origin: presenter.origin) }
            Section {
                Button("Suggest additional places", action: suggestPlaces)
                    .disabled(presenter.isBusy || isProcessingRecommendations || presenter.draftInput == nil || presenter.places.isEmpty || presenter.privateAccessBlocked)
                Button("Plan my trip") { Task { await presenter.request() } }
                    .disabled(presenter.isBusy || presenter.draftInput == nil || presenter.places.isEmpty || presenter.privateAccessBlocked)
                PlanningFeedback(presenter: presenter)
            }
            if let result = presenter.job?.result, presenter.job?.tripID == nil {
                if !usesItineraryReview && !result.candidates.isEmpty {
                    Section("Optional suggestions") {
                        ForEach(result.candidates) { place in
                            Button {
                                if presenter.places.count < 6 { presenter.places.append(place) }
                            } label: { Label("Add \(place.name)", systemImage: "plus.circle") }
                                .disabled(presenter.places.count >= 6)
                        }
                        ForEach(result.warnings, id: \.self) { Text($0).font(.footnote) }
                    }
                }
                if let proposal = result.proposal {
                    if usesItineraryReview {
                        Section {
                            Button("Review itinerary") { reviewProposal = .init(proposal: proposal) }
                        }
                    } else {
                        PlanningProposalSections(proposal: proposal, presenter: presenter)
                    }
                }
            }
        }
        .overlay {
            if isProcessingRecommendations {
                RecommendationsProcessingView()
            }
        }
        .toolbar(isProcessingRecommendations ? .hidden : .automatic, for: .navigationBar)
        .fullScreenCover(item: $searchPurpose) { purpose in
            PlanningSearchSheet(near: presenter.origin, title: purpose == .origin ? "Starting point" : "Add a place") { place in
                if purpose == .origin { location.cancel(); presenter.origin = place.location; presenter.originLabel = place.name }
                else if presenter.places.count < 6 { presenter.places.append(place) }
            }
        }
        .onChange(of: location.point) { _, point in if let point { presenter.receivedLocation(point) } }
        .onChange(of: presenter.draftInput) { _, input in
            presenter.draftChanged()
            if input == nil { reviewProposal = nil }
            if input != recommendationsInput {
                showsRecommendations = false
                recommendations = nil
                recommendationsInput = nil
            }
        }
        .onChange(of: presenter.job?.result?.proposal) { _, proposal in
            if usesItineraryReview, let proposal, reviewProposal == nil { reviewProposal = .init(proposal: proposal) }
        }
        .navigationDestination(item: $reviewProposal) { route in
            ItineraryReviewView(presenter: presenter, initialProposal: route.proposal)
        }
        .navigationDestination(isPresented: $showsRecommendations) {
            if let recommendations {
                PlacesRecommendationsView(batch: .init(result: recommendations), selected: selectedRecommendations,
                                          isLoading: isProcessingRecommendations, error: recommendationError,
                                          maximumSelection: max(0, 6 - presenter.places.count), load: {},
                                          refresh: { await refreshRecommendations() }, cancel: {},
                                          toggle: toggleRecommendation,
                                          findPlace: { searchPurpose = .destination },
                                          complete: { addRecommendations(selectedRecommendations.map(\.place)) })
            }
        }
        .task {
            if opensPlaceSearch && !didOpenPlaceSearch {
                didOpenPlaceSearch = true
                searchPurpose = .destination
            }
        }
    }

    private func suggestPlaces() {
        guard !presenter.isBusy, !isProcessingRecommendations else { return }
        if !usesItineraryReview {
            Task { await presenter.request(.suggest) }
            return
        }
        isProcessingRecommendations = true
        Task {
            await presenter.request(.suggest)
            isProcessingRecommendations = false
            guard let result = currentRecommendations(), let input = presenter.draftInput else { return }
            recommendations = result
            selectedRecommendations = []
            recommendationError = nil
            recommendationsInput = input
            showsRecommendations = true
        }
    }

    private func currentRecommendations() -> PlanningResult? {
        guard !Task.isCancelled, !presenter.privateAccessBlocked, presenter.creationIssue == nil,
              let job = presenter.job, job.purpose == .suggest, job.status == .succeeded,
              job.input == presenter.draftInput else { return nil }
        return job.result
    }

    private func refreshRecommendations() async {
        guard !presenter.isBusy, !isProcessingRecommendations, presenter.draftInput == recommendationsInput else { return }
        isProcessingRecommendations = true
        defer { isProcessingRecommendations = false }
        await presenter.request(.suggest)
        guard presenter.draftInput == recommendationsInput, let result = currentRecommendations() else {
            if !Task.isCancelled { recommendationError = "Recommendations could not be refreshed. Your selection is kept." }
            return
        }
        recommendations = result
        recommendationError = nil
    }

    private func toggleRecommendation(_ item: RecommendedPlace) {
        if selectedRecommendations.contains(where: { $0.id == item.id }) {
            selectedRecommendations.removeAll { $0.id == item.id }
        } else if !presenter.places.contains(where: { $0.id == item.id }), selectedRecommendations.count < max(0, 6 - presenter.places.count) {
            selectedRecommendations.append(item)
        }
    }

    private func addRecommendations(_ places: [PlanningPlace]) {
        guard !presenter.isBusy, presenter.draftInput == recommendationsInput else { return }
        let knownIDs = Set(presenter.places.map(\.id))
        let additions = places.filter { !knownIDs.contains($0.id) }
        guard !additions.isEmpty, presenter.places.count + additions.count <= 6 else { return }
        presenter.places.append(contentsOf: additions)
        presenter.draftChanged()
        showsRecommendations = false
        recommendations = nil
        recommendationsInput = nil
        Task { await presenter.request() }
    }
}

struct PlanningPlaceEditor: View {
    @Binding var place: PlanningPlace
    let zone: String
    let defaultStart: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(place.name).font(.headline)
            Stepper("Visit: \(place.visitSeconds / 60) minutes", value: $place.visitSeconds, in: 0 ... 86400, step: 900)
            Toggle("Preferred arrival window", isOn: Binding(
                get: { place.preferredAfter != nil || place.preferredBefore != nil },
                set: { enabled in place.preferredAfter = enabled ? defaultStart : nil; place.preferredBefore = enabled ? defaultStart.addingTimeInterval(3600) : nil }
            ))
            if place.preferredAfter != nil {
                DatePicker("From", selection: Binding(get: { place.preferredAfter ?? Date() }, set: { place.preferredAfter = $0 }))
                DatePicker("Until", selection: Binding(get: { place.preferredBefore ?? Date() }, set: { place.preferredBefore = $0 }))
                Text("A preference, not a rule that removes this place if you arrive later.").font(.caption).foregroundStyle(.secondary)
            }
        }.environment(\.timeZone, TimeZone(identifier: zone) ?? .current)
    }
}

/// Map-backed place picker: search with suggestions in a draggable panel, or move the map under a centre pin.
struct PlanningSearchSheet: View {
    private enum Panel { case expanded, collapsed }

    @State private var search = PlanningPlaceSearch()
    @State private var completer = PlanningPlaceCompleter()
    @State private var pinned = PlanningPinnedLocation()
    @State private var location = PlanningLocation()
    @State private var camera: MapCameraPosition
    @State private var panel = Panel.expanded
    @State private var isMapMoving = false
    @State private var resolvingCompletion: MKLocalSearchCompletion?
    @State private var completionFailed = false
    @State private var dragOffset: CGFloat = 0
    @State private var mapCenter: CLLocationCoordinate2D?
    @State private var listHeight: CGFloat = 0
    @State private var recents: [PlanningPlace] = []
    @State private var isSearchFocused = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let near: PlanningPoint?
    let title: String
    let select: (PlanningPlace) -> Void

    init(near: PlanningPoint?, title: String, select: @escaping (PlanningPlace) -> Void) {
        self.near = near
        self.title = title
        self.select = select
        _camera = State(initialValue: near.map {
            .region(MKCoordinateRegion(center: .init(latitude: $0.latitude, longitude: $0.longitude),
                                       latitudinalMeters: 1500, longitudinalMeters: 1500))
        } ?? .userLocation(fallback: .automatic))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    map
                    if panel == .collapsed { centerPin }
                    searchPanel(maxHeight: proxy.size.height * 0.68)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onAppear {
            recents = PlanningRecentPlaces.load()
            isSearchFocused = true
        }
        .onChange(of: search.query) { _, query in
            completionFailed = false
            completer.update(query, near: near)
        }
        .onChange(of: location.point) { _, point in
            guard let point else { return }
            move(to: point, meters: 500)
            setPanel(.collapsed)
        }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $camera) { UserAnnotation() }
            .mapControls { MapCompass() }
            .onMapCameraChange(frequency: .continuous) { _ in
                guard panel == .collapsed else { return }
                isMapMoving = true
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                isMapMoving = false
                mapCenter = context.region.center
                guard panel == .collapsed else { return }
                Task { await pinned.resolve(context.region.center) }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in
                guard panel == .expanded else { return }
                setPanel(.collapsed)
            })
            .accessibilityLabel("Map")
    }

    /// The pin marks the map centre; it lifts while the map moves so the landing point stays readable.
    private var centerPin: some View {
        Image(systemName: "mappin")
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(.red)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            .offset(y: isMapMoving && !reduceMotion ? -28 : -17)
            .animation(reduceMotion ? nil : .spring(duration: 0.25), value: isMapMoving)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Panel

    private func searchPanel(maxHeight: CGFloat) -> some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(AppColor.tertiaryFill)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, minHeight: 20)
                .contentShape(.rect)
                .onTapGesture { setPanel(panel == .expanded ? .collapsed : .expanded) }
                .accessibilityElement()
                .accessibilityLabel(panel == .expanded ? "Show map" : "Show search")
                .accessibilityAddTraits(.isButton)
            searchField
            if panel == .expanded {
                ScrollView {
                    expandedContent
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(max(listHeight, 1), maxHeight))
            } else {
                pinnedCard
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, panel == .collapsed ? 8 : 0)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                .fill(AppColor.surface)
                .shadow(color: .black.opacity(0.12), radius: 16, y: -2)
                .ignoresSafeArea(edges: .bottom)
        }
        .offset(y: dragOffset)
        .gesture(panelDrag)
        .tint(AppColor.brand)
    }

    private var panelDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in dragOffset = min(max(value.translation.height * 0.5, -40), 240) }
            .onEnded { value in
                let distance = value.predictedEndTranslation.height
                if distance > 80 { setPanel(.collapsed) } else if distance < -80 { setPanel(.expanded) }
                withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { dragOffset = 0 }
            }
    }

    private var searchField: some View {
        NativeSearchBar(text: $search.query, prompt: String(localized: "Search place or address"),
                        accessibilityIdentifier: "placeSearchField", isFocused: $isSearchFocused) {
            Task { await search.search(near: near) }
        }
        .padding(.horizontal, -8)
        .simultaneousGesture(TapGesture().onEnded { if panel == .collapsed { setPanel(.expanded) } })
        .onChange(of: isSearchFocused) { _, focused in
            if focused, panel == .collapsed { setPanel(.expanded) }
        }
    }

    @ViewBuilder private var expandedContent: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            PlaceRow(title: Text("Use current location"), systemImage: "location.fill", tint: AppColor.brand,
                     isBusy: location.isRequesting) { location.request() }
                .accessibilityIdentifier("placeUseCurrentLocation")
            if let error = location.error {
                Text(error).font(.footnote).foregroundStyle(AppColor.secondaryText).padding(.leading, 52).padding(.bottom, 8)
            }
            Divider().padding(.leading, 52)
            PlaceRow(title: Text("Choose on map"), systemImage: "map") { setPanel(.collapsed) }
                .accessibilityIdentifier("placeChooseOnMap")

            if search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                recentPlaces
            } else if search.hasSearched {
                searchResults
            } else if !completer.completions.isEmpty {
                sectionHeader("Suggestions")
                if completionFailed {
                    Text("That suggestion couldn't be opened. Try another one or press Search.")
                        .font(.footnote).foregroundStyle(AppColor.secondaryText).padding(.bottom, 8)
                }
                ForEach(completer.completions, id: \.self) { completion in
                    PlaceRow(title: Text(completion.title), subtitle: completion.subtitle.isEmpty ? nil : completion.subtitle,
                             systemImage: "mappin", isBusy: resolvingCompletion == completion) {
                        choose(completion)
                    }
                    .disabled(resolvingCompletion != nil)
                }
            }
        }
        .padding(.bottom, 24)
    }

    @ViewBuilder private var searchResults: some View {
        sectionHeader("Results")
        if search.isBusy { ProgressView("Searching places…").padding(.vertical, 12) }
        if let error = search.error {
            RecoveryNotice(title: "Search unavailable", message: error,
                           primary: .init(title: "Try again") { Task { await search.search(near: near) } })
        }
        ForEach(search.results) { place in
            let address = place.address?.trimmingCharacters(in: .whitespacesAndNewlines)
            PlaceRow(title: Text(place.name), subtitle: address?.isEmpty == false ? address : String(localized: "Address unavailable"),
                     systemImage: "mappin") { finish(with: place) }
        }
        if search.results.isEmpty, !search.isBusy, search.error == nil {
            Text("No places found. Try another name or address, or choose on the map.")
                .font(.subheadline).foregroundStyle(AppColor.secondaryText).padding(.vertical, 12)
        }
    }

    @ViewBuilder private var recentPlaces: some View {
        if !recents.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                sectionHeader("Recent")
                Spacer()
                Button("Clear") {
                    PlanningRecentPlaces.clear()
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { recents = [] }
                }
                .font(.footnote.weight(.semibold))
                .accessibilityLabel("Clear recent places")
                .accessibilityIdentifier("placeClearRecents")
            }
            ForEach(recents) { place in
                PlaceRow(title: Text(place.name), subtitle: place.address, systemImage: "clock.arrow.circlepath") {
                    // A reused place still needs its own identity in the trip it joins.
                    var fresh = place
                    fresh.id = UUID()
                    finish(with: fresh)
                }
                .contextMenu {
                    Button("Remove from recent", systemImage: "trash", role: .destructive) {
                        PlanningRecentPlaces.remove(place)
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { recents.removeAll { $0.id == place.id } }
                    }
                }
                .accessibilityIdentifier("placeRecent")
            }
        }
    }

    private func sectionHeader(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppColor.secondaryText)
            .padding(.top, 20)
            .padding(.bottom, 4)
    }

    private var pinnedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    if isMapMoving || pinned.isResolving || pinned.point == nil {
                        Text("Finding address…").font(.headline).foregroundStyle(AppColor.secondaryText)
                        Text("Move the map to place the pin").font(.subheadline).foregroundStyle(AppColor.secondaryText)
                    } else {
                        Text(pinned.name ?? String(localized: "Pinned location")).font(.headline).lineLimit(2)
                        if let address = pinned.address {
                            Text(address).font(.subheadline).foregroundStyle(AppColor.secondaryText).lineLimit(2)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            Button {
                guard let place = pinned.place else { return }
                finish(with: place)
            } label: {
                Text("Use this location").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(isMapMoving || pinned.place == nil)
            .accessibilityIdentifier("placeConfirmPin")
        }
        .padding(.top, 4)
    }

    // MARK: Actions

    private func setPanel(_ next: Panel) {
        guard next != panel else { return }
        if next == .collapsed { isSearchFocused = false }
        withAnimation(reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.12)) { panel = next }
        if next == .collapsed, pinned.point == nil, let center = currentCenter {
            Task { await pinned.resolve(center) }
        }
    }

    private var currentCenter: CLLocationCoordinate2D? {
        mapCenter ?? camera.region?.center ?? near.map { .init(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private func move(to point: PlanningPoint, meters: CLLocationDistance) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
            camera = .region(MKCoordinateRegion(center: .init(latitude: point.latitude, longitude: point.longitude),
                                                latitudinalMeters: meters, longitudinalMeters: meters))
        }
    }

    private func choose(_ completion: MKLocalSearchCompletion) {
        resolvingCompletion = completion
        completionFailed = false
        Task {
            defer { resolvingCompletion = nil }
            guard let place = try? await search.resolve(completion) else {
                completionFailed = true
                return
            }
            finish(with: place)
        }
    }

    private func finish(with place: PlanningPlace) {
        PlanningRecentPlaces.record(place)
        select(place)
        dismiss()
    }
}

/// One tappable row in the place picker: icon, title and optional detail.
private struct PlaceRow: View {
    let title: Text
    var subtitle: String?
    let systemImage: String
    var tint: Color = AppColor.secondaryText
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(AppColor.tertiaryFill)
                    if isBusy { ProgressView().controlSize(.small) } else { Image(systemName: systemImage).foregroundStyle(tint) }
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    title.foregroundStyle(AppColor.primaryText).lineLimit(2)
                    if let subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(AppColor.secondaryText).lineLimit(2)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct PlanningMapSection: View {
    let places: [PlanningPlace]
    let origin: PlanningPoint?
    var body: some View {
        Section("Places on the map") {
            Map {
                if let origin { Marker("Start", systemImage: "location", coordinate: .init(latitude: origin.latitude, longitude: origin.longitude)) }
                ForEach(places) { place in Marker(place.name, coordinate: .init(latitude: place.location.latitude, longitude: place.location.longitude)) }
            }.frame(height: 240).accessibilityLabel("Starting point and selected destinations")
        }
    }
}

private struct PlanningFeedback: View {
    let presenter: PlanningPresenter
    var tripID: UUID?
    var body: some View {
        let scope = PresentationIssue.Scope.planning(tripID)
        if let progress = presenter.progress { ProgressView(progress) }
        if let issue = presenter.issues[scope] {
            RecoveryNotice(title: "Planning needs attention", message: issue.message,
                           primary: recovery(issue, scope: scope))
        }
        if !presenter.isBusy, presenter.job?.tripID == tripID,
           presenter.job?.status == .running || presenter.job?.status == .queued,
           presenter.issues[scope]?.recovery != .checkStatus {
            Button("Check status") { Task { await presenter.checkStatus(scope: scope) } }
        }
    }

    private func recovery(_ issue: PresentationIssue, scope: PresentationIssue.Scope) -> RecoveryNotice.Action? {
        if issue.recovery == .checkStatus {
            return .init(title: "Check status") { Task { await presenter.checkStatus(scope: scope) } }
        }
        guard issue.recovery != .signIn else { return nil }
        let trip = presenter.trips.first { $0.id == tripID }
        switch issue.operation {
        case .save where issue.recovery == .regenerate, .save where issue.recovery == .refreshTrip:
            return .init(title: "Request a fresh plan") {
                Task {
                    if tripID != nil { await presenter.load(resumesJobs: false) }
                    if tripID == nil { await presenter.request() }
                    else if let refreshed = presenter.trips.first(where: { $0.id == tripID }) {
                        await presenter.request(.replan, trip: refreshed)
                    }
                }
            }
        case .save:
            return .init(title: "Retry saving") { Task { await presenter.apply(scope: scope) } }
        case .plan where issue.recovery == .refreshTrip:
            return .init(title: "Refresh trip") { Task { await presenter.load(resumesJobs: false) } }
        case .plan(let purpose):
            let title: LocalizedStringKey = issue.recovery == .wait ? "Try again later" : "Try again"
            return .init(title: title) { Task { await presenter.request(purpose, trip: trip) } }
        default: return nil
        }
    }
}

private struct PlanningProposalSections: View {
    let proposal: PlanProposal
    let presenter: PlanningPresenter
    var body: some View {
        Section(proposal.feasible ? "Proposed trip" : "Your choices need adjustment") {
            if proposal.synthetic { Label("Synthetic demonstration", systemImage: "hammer").font(.caption) }
            Text(proposal.explanation)
            Text("Estimated finish: \(PlanningTime.text(proposal.finishesAt, zone: proposal.input.timeZone))")
            ForEach(proposal.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
            Button(presenter.job?.tripID == nil ? "Save this trip" : "Apply this proposal") {
                let scope = PresentationIssue.Scope.planning(presenter.job?.tripID)
                Task { await presenter.apply(scope: scope) }
            }
            .disabled(presenter.isBusy || !proposal.feasible || presenter.needsFreshProposal)
        }
        Section("Suggested order") {
            ForEach(proposal.stops) { stop in PlanningStopRow(stop: stop, zone: proposal.input.timeZone) }
        }
        if !proposal.evidence.isEmpty {
            Section("Sources and context") {
                ForEach(proposal.evidence) { source in
                    DisclosureGroup(source.label) {
                        if let logo = source.attributionLogoURL, logo.scheme == "https", logo.host == "weatherkit.apple.com" {
                            AsyncImage(url: logo) { image in image.resizable().scaledToFit() }
                                placeholder: { Text("Apple Weather") }
                                .frame(width: 120, height: 28).padding(6).background(.white)
                                .accessibilityLabel("Apple Weather")
                        }
                        Text(source.summary).font(.footnote)
                        Text("Checked \(source.checkedAt.formatted())").font(.caption).foregroundStyle(.secondary)
                        if let url = source.url, url.scheme == "https" { Link("Open source", destination: url) }
                    }
                }
                if proposal.evidence.contains(where: { $0.kind == "weather" }) {
                    Text("Forecast sources are listed with the plan. Forecasts and estimates can change.").font(.footnote)
                }
            }
        }
    }
}

private struct PlanningStopRow: View {
    let stop: ScheduledPlanningStop
    let zone: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stop.name).font(.headline)
            if stop.arrivalAt != nil {
                Text("\(PlanningTime.text(stop.arrivalAt, zone: zone)) – \(PlanningTime.text(stop.departureAt, zone: zone))").font(.subheadline)
                Text("Travel \(stop.travelSeconds / 60) min · visit \(stop.visitSeconds / 60) min").font(.caption).foregroundStyle(.secondary)
            } else { Text("Experience order · arrival time not scheduled").font(.caption).foregroundStyle(.secondary) }
            ForEach(stop.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
        }
    }
}

struct ActivePlanningTripView: View {
    let tripID: UUID
    let presenter: PlanningPresenter
    var startTrip: (() -> Void)? = nil
    @State private var location = PlanningLocation()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        if let trip = presenter.trips.first(where: { $0.id == tripID }) {
            Form {
                Section {
                    Text(trip.status.rawValue.capitalized)
                    if trip.synthetic { Text("Synthetic demonstration · memory only").font(.caption) }
                    Text("\(trip.completedStopIDs.count) of \(trip.plan.stops.count) visits complete")
                    PlanningFeedback(presenter: presenter, tripID: tripID)
                    if let issue = presenter.issues[.activity(tripID)] {
                        RecoveryNotice(title: "Trip update needs attention", message: issue.message,
                                       primary: tripRecovery(issue, trip: trip))
                    }
                }
                if trip.status == .planned {
                    Section { Button("Start trip") {
                        if let startTrip { startTrip() }
                        else { Task { await presenter.event(.start, trip: trip) } }
                    }.disabled(presenter.isBusy) }
                }
                if trip.status == .active, let next = trip.nextStop {
                    Section(trip.currentStopID == next.id ? "Current visit" : "Next place") {
                        Text(next.name).font(.headline)
                        Button("Open directions in Maps", systemImage: "arrow.triangle.turn.up.right.diamond") { PlanningDirections.open(next, mode: trip.input.mode) }
                        if trip.currentStopID == nil {
                            Button("I'm here") { Task { await presenter.event(.arrive, trip: trip) } }
                            Text("Arrival is your manual confirmation, not verified GPS presence.").font(.footnote).foregroundStyle(.secondary)
                            Button("Refresh my current position", systemImage: "location") { location.request() }
                            if location.isRequesting { ProgressView("Getting your position…") }
                            if let error = location.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                            Text("Recalculation uses a fresh position when available, or your last completed place. At a confirmed visit it starts from that place.").font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Button("Stay 30 minutes longer") { Task { await presenter.event(.extendStay, trip: trip, extraSeconds: 1800) } }
                            Button("Finish this visit") { Task { await presenter.event(.completeStop, trip: trip) } }
                        }
                        Button("Recalculate remaining trip") { Task { await presenter.request(.replan, trip: trip) } }
                        Text("After extending a visit, recalculate to see the impact on later places and your finish time.").font(.footnote).foregroundStyle(.secondary)
                    }.disabled(presenter.isBusy)
                }
                if trip.pendingEndpoint != nil {
                    Section {
                        Button("Recalculate route to endpoint") { Task { await presenter.request(.replan, trip: trip) } }
                        Button("I’ve arrived at the endpoint") { Task { await presenter.event(.arriveAtEndpoint, trip: trip) } }
                    }.disabled(presenter.isBusy)
                }
                if presenter.job?.tripID == trip.id, let proposal = presenter.job?.result?.proposal {
                    PlanningProposalSections(proposal: proposal, presenter: presenter)
                }
                Section("Accepted schedule") {
                    ForEach(trip.plan.stops) { stop in
                        HStack(alignment: .top) {
                            if trip.completedStopIDs.contains(stop.id) { Image(systemName: "checkmark.circle.fill").accessibilityLabel("Visit completed") }
                            PlanningStopRow(stop: stop, zone: trip.input.timeZone)
                        }
                    }
                }
            }.navigationTitle(trip.title).refreshable { await presenter.load() }
                .onChange(of: location.point) { _, point in if let point { presenter.receivedReplanningLocation(point) } }
        } else {
            ContentUnavailableView {
                Label("Trip unavailable", systemImage: "map")
            } description: {
                Text("Go back to your trips to refresh the list.")
            } actions: {
                Button("Go back") { dismiss() }
            }
        }
    }

    private func tripRecovery(_ issue: PresentationIssue, trip: PersonalPlanningTrip) -> RecoveryNotice.Action? {
        if issue.recovery == .refreshTrip {
            return .init(title: "Refresh trip") { Task { await presenter.load(resumesJobs: false) } }
        }
        guard issue.recovery == .retry, case .event(let kind, let seconds) = issue.operation else { return nil }
        return .init(title: "Try again") { Task { await presenter.event(kind, trip: trip, extraSeconds: seconds) } }
    }
}

private enum PlanningTime {
    static func text(_ value: Date?, zone: String) -> String {
        guard let value else { return String(localized: "Not scheduled") }
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.timeZone = TimeZone(identifier: zone) ?? .current
        return value.formatted(style)
    }
}

extension Binding {
    /// Narrows an optional route binding to the routes `include` accepts, so one route can drive
    /// a full-screen page while its siblings stay in a sheet. Dismissing clears only an owned route.
    func only<Route: Sendable>(_ include: @escaping @Sendable (Route) -> Bool) -> Binding<Route?> where Value == Route? {
        Binding<Route?>(
            get: { wrappedValue.flatMap { include($0) ? $0 : nil } },
            set: { next in
                if let next { wrappedValue = next } else if let current = wrappedValue, include(current) { wrappedValue = nil }
            }
        )
    }
}
