import SwiftUI
import UIKit
import C67Domain

struct PlacesRecommendationsView: View {
    let batch: RecommendationsBatch
    let selected: [RecommendedPlace]
    var isLoading = false
    var error: String?
    var areaDescription: LocalizedStringResource?
    var usesDeviceLocation = true
    var previewLocation: PlanningPoint?
    var requiresOrigin = false
    var origin: PlanningPoint?
    var setOrigin: ((PlanningPlace) -> Void)?
    /// The older planning editor still follows its existing six-place contract.
    /// The recommendations-first creation flow leaves this nil.
    var maximumSelection: Int?
    let load: @MainActor () async -> Void
    let refresh: @MainActor () async -> Void
    let cancel: () -> Void
    let toggle: (RecommendedPlace) -> Void
    let findPlace: () -> Void
    let complete: () -> Void
    @State private var location = PlanningLocation()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var showsSelected = false
    @State private var searchAfterDismiss = false
    @State private var retryTask: Task<Void, Never>?
    @State private var showsOriginSearch = false

    private var selectedIDs: Set<UUID> { Set(selected.map(\.id)) }
    private var selectedPlaces: Binding<[PlanningPlace]> {
        Binding(get: { selected.map(\.place) }, set: { remaining in
            let ids = Set(remaining.map(\.id))
            for item in selected where !ids.contains(item.id) { toggle(item) }
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("List of \(Text("Places").foregroundStyle(AppColor.accent))")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    Text("Pull down to refresh recommendations").foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Refresh", systemImage: "arrow.clockwise", action: retry)
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                        .disabled(isLoading)
                        .accessibilityIdentifier("refreshRecommendations")
                }
                if let radius = batch.radiusKilometers, origin != nil {
                    Text("Showing places within \(radius) km of your starting point")
                        .font(.footnote).foregroundStyle(.secondary).padding(.bottom, 16)
                } else if let areaDescription, !requiresOrigin {
                    Text(areaDescription).font(.footnote).foregroundStyle(.secondary).padding(.bottom, 16)
                }

                if requiresOrigin && origin == nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose a starting point to find nearby places.")
                        if location.isRequesting { ProgressView("Finding your location…") }
                        else if location.permissionDenied {
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        } else { Button("Use my current location") { location.request() } }
                        Button("Choose starting point") { showsOriginSearch = true }
                    }.font(.footnote)
                } else if !requiresOrigin && usesDeviceLocation && location.point == nil {
                    if location.isRequesting {
                        Label("Finding your location…", systemImage: "location")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if location.permissionDenied {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable location access to see distances.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        }
                    } else if location.error != nil {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Couldn’t get your location. Try again to see distances.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Try location again") { location.request() }
                        }
                    }
                }

                if isLoading { ProgressView("Finding places…").frame(maxWidth: .infinity).padding() }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Try again", action: retry).disabled(isLoading)
                }
                ForEach(batch.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if batch.places.isEmpty && !isLoading && (!requiresOrigin || origin != nil) {
                    ContentUnavailableView {
                        Label("No recommendations yet", systemImage: "mappin.and.ellipse")
                    } description: {
                        Text("Try refreshing, adjust your preferences, or search for a place.")
                    } actions: {
                        Button("Try again", action: retry)
                        Button("Search for a place", action: findPlace)
                    }
                }
                LazyVStack(spacing: 10) {
                    ForEach(batch.places) { item in
                        RecommendationPlaceRow(item: item, userLocation: requiresOrigin ? origin : (usesDeviceLocation ? location.point : previewLocation), isSelected: selectedIDs.contains(item.id),
                                               isExisting: false,
                                               isDisabled: !selectedIDs.contains(item.id) && maximumSelection.map { selected.count >= $0 } == true) { toggle(item) }
                    }
                }
                if batch.synthetic {
                    Text("Synthetic recommendations for demonstration.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if !batch.places.isEmpty {
                    Text("Check opening hours and any facilities you need before visiting.")
                        .font(.footnote).foregroundStyle(.secondary)
                    TripRecommendationsMap(places: batch.places)
                        .frame(height: 180)
                        .clipShape(.rect(cornerRadius: 20))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .task(id: origin) {
            if usesDeviceLocation && (!requiresOrigin || origin == nil) && !location.isRequesting { location.request() }
            await load()
        }
        .onChange(of: location.point) { _, point in
            if requiresOrigin, origin == nil, let point {
                setOrigin?(.init(id: UUID(), name: "Current device position", location: point, visitSeconds: 2700))
            }
        }
        .overlay {
            if isLoading && batch.places.isEmpty {
                RecommendationsProcessingView()
            }
        }
        .refreshable {
            if usesDeviceLocation && (!requiresOrigin || origin == nil) { location.request() }
            await refresh()
        }
        .onDisappear { location.cancel(); retryTask?.cancel(); cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && usesDeviceLocation && location.permissionDenied {
                location.request()
            }
        }
        .background(AppColor.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("\(selected.count) places selected")
                        Spacer()
                        Button("My Places") { showsSelected = true }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(selected.count) places selected")
                        Button("My Places") { showsSelected = true }
                    }
                }
                if let maximumSelection {
                    Text("Choose up to \(maximumSelection) additional places.").font(.footnote).foregroundStyle(.secondary)
                }
                QuestionPrimaryButton("Next", action: complete)
                    .disabled(selected.isEmpty)
                    .accessibilityIdentifier("recommendationsNext")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(AppColor.surface)
        }
        .sheet(isPresented: $showsSelected, onDismiss: {
            if searchAfterDismiss {
                searchAfterDismiss = false
                findPlace()
            }
        }) {
            SelectedPlacesView(existing: [], selected: selectedPlaces,
                               details: Dictionary(selected.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
                               searchForPlace: { searchAfterDismiss = true; showsSelected = false })
        }
        .sheet(isPresented: $showsOriginSearch) {
            PlanningSearchSheet(near: origin, title: "Starting point") { place in
                location.cancel()
                setOrigin?(place)
            }
        }
        .navigationTitle("Recommendations")
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppColor.accent)
    }

    private func retry() {
        guard !isLoading else { return }
        if usesDeviceLocation && (!requiresOrigin || origin == nil) { location.request() }
        retryTask?.cancel()
        retryTask = Task { await refresh() }
    }
}

#if DEBUG
    #Preview("PLACES LISTS · Light") {
        RecommendationsDesignPreview(addedCount: 0)
    }

    #Preview("PLACES LIST ADDED · Light") {
        RecommendationsDesignPreview(addedCount: 3)
    }

    #Preview("PLACES LIST ADDED · Dark") {
        RecommendationsDesignPreview(addedCount: 3).preferredColorScheme(.dark)
    }
#endif
