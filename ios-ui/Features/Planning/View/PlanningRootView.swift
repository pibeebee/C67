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
            if let error = presenter.error { Text(error).foregroundStyle(.red) }
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
            if presenter.trips.isEmpty {
                ContentUnavailableView("No personal trips", systemImage: "map", description: Text("Choose places, review a proposal, and save your trip."))
            }
        }.refreshable { await presenter.load() }
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
        .sheet(item: $searchPurpose) { purpose in
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
        guard !Task.isCancelled, !presenter.privateAccessBlocked, presenter.error == nil,
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

struct PlanningSearchSheet: View {
    @State private var search = PlanningPlaceSearch()
    @Environment(\.dismiss) private var dismiss
    let near: PlanningPoint?
    let title: String
    let select: (PlanningPlace) -> Void
    var body: some View {
        NavigationStack {
            List {
                if search.isBusy { ProgressView("Searching places…") }
                if let error = search.error { Text(error) }
                ForEach(search.results) { place in
                    Button { select(place); dismiss() } label: {
                        VStack(alignment: .leading) {
                            Text(place.name)
                            Text("\(place.location.latitude, specifier: "%.4f"), \(place.location.longitude, specifier: "%.4f")").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if search.results.isEmpty && !search.isBusy { Text("Search for a place or address, then choose the correct result.").foregroundStyle(.secondary) }
            }.navigationTitle(title)
                .searchable(text: $search.query, prompt: "Place or address")
                .onSubmit(of: .search) { Task { await search.search(near: near) } }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
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
    var body: some View {
        if let progress = presenter.progress { ProgressView(progress) }
        if let error = presenter.error { Text(error).foregroundStyle(.red) }
        if !presenter.isBusy { Button("Refresh planning status") { Task { await presenter.load() } } }
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
            Button(presenter.job?.tripID == nil ? "Save this trip" : "Apply this proposal") { Task { await presenter.apply() } }
                .disabled(presenter.isBusy || !proposal.feasible)
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
                    Text("Weather data: Apple Weather. Forecasts and estimates can change.").font(.footnote)
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
            Text("\(PlanningTime.text(stop.arrivalAt, zone: zone)) – \(PlanningTime.text(stop.departureAt, zone: zone))").font(.subheadline)
            Text("Travel \(stop.travelSeconds / 60) min · visit \(stop.visitSeconds / 60) min").font(.caption).foregroundStyle(.secondary)
            ForEach(stop.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
        }
    }
}

struct ActivePlanningTripView: View {
    let tripID: UUID
    let presenter: PlanningPresenter
    @State private var location = PlanningLocation()
    var body: some View {
        if let trip = presenter.trips.first(where: { $0.id == tripID }) {
            Form {
                Section {
                    Text(trip.status.rawValue.capitalized)
                    if trip.synthetic { Text("Synthetic demonstration · memory only").font(.caption) }
                    Text("\(trip.completedStopIDs.count) of \(trip.plan.stops.count) visits complete")
                    PlanningFeedback(presenter: presenter)
                }
                if trip.status == .planned {
                    Section { Button("Start trip") { Task { await presenter.event(.start, trip: trip) } }.disabled(presenter.isBusy) }
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
        } else { ContentUnavailableView("Trip unavailable", systemImage: "map", description: Text("Refresh My Trips or sign in again.")) }
    }
}

private enum PlanningTime {
    static func text(_ value: Date, zone: String) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.timeZone = TimeZone(identifier: zone) ?? .current
        return value.formatted(style)
    }
}
