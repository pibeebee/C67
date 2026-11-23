import SwiftUI
import UIKit
import C67Domain

struct PlacesRecommendationsView: View {
    let batch: RecommendationsBatch
    let selected: [RecommendedPlace]
    var isLoading = false
    var error: String?
    var usesDeviceLocation = true
    var previewLocation: PlanningPoint?
    var requiresOrigin = false
    var origin: PlanningPoint?
    var setOrigin: ((PlanningPlace) -> Void)?
    /// The most places this flow accepts; `nil` means no limit.
    var maximumSelection: Int?
    var minimumSelection = 1
    /// Names the selection in the primary button ("Plan with 4 places") once the minimum is met.
    var countsInNextButton = false
    let load: @MainActor () async -> Void
    let refresh: @MainActor () async -> Void
    let cancel: () -> Void
    let toggle: (RecommendedPlace) -> Void
    let findPlace: () -> Void
    let complete: () -> Void
    @State private var location = PlanningLocation()
    @Environment(\.openURL) private var openURL
    @State private var showsSelected = false
    @State private var retryTask: Task<Void, Never>?
    @State private var showsOriginSearch = false
    @State private var rejectedSelectionCount = 0
    @State private var showsFoundIntro = false
    @State private var foundIntroTask: Task<Void, Never>?

    private var showsProcessing: Bool { isLoading && batch.places.isEmpty }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var canLoadRecommendations: Bool { !requiresOrigin || origin != nil }

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
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("List of \(Text("Places").foregroundStyle(AppColor.accent))")
                            .font(.title.bold())
                            .accessibilityAddTraits(.isHeader)
                        // Selection summary and what's still needed sit with the list; the footer keeps one action.
                        if canLoadRecommendations {
                            Text("Pull down to refresh recommendations")
                                .font(.footnote)
                                .foregroundStyle(AppColor.secondaryText)
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 8)
                }

                if requiresOrigin && origin == nil {
                    OriginPrompt(isRequesting: location.isRequesting,
                                 permissionDenied: usesDeviceLocation && location.permissionDenied,
                                 failed: usesDeviceLocation && location.error != nil,
                                 offersDeviceLocation: usesDeviceLocation,
                                 useCurrentLocation: { location.request() },
                                 openSettings: {
                                     if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                                 },
                                 chooseStartingPoint: {
                                     location.cancel()
                                     showsOriginSearch = true
                                 })
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
                    } else {
                        Button("Use current location") { location.request() }
                    }
                }

                if isLoading { ProgressView("Finding places…").frame(maxWidth: .infinity).padding() }
                if let error {
                    RecoveryNotice(title: "Couldn’t refresh recommendations", message: error,
                                   primary: isLoading ? nil : .init(title: "Try again", perform: retry),
                                   secondary: .init(title: "Search for a place", perform: findPlace))
                }
                if !batch.warnings.isEmpty {
                    DisclosureGroup(batch.places.isEmpty ? "Recommendation details" : "Some recommendations are unavailable") {
                        ForEach(batch.warnings, id: \.self) { warning in
                            Text(warning).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if batch.places.isEmpty && !isLoading && error == nil && (!requiresOrigin || origin != nil) {
                    ContentUnavailableView {
                        Label("No recommendations yet", systemImage: "mappin.and.ellipse")
                    } description: {
                        Text("Try refreshing, adjust your preferences, or search for a place.")
                    } actions: {
                        Button("Try again", action: retry)
                        Button("Search for a place", action: findPlace)
                    }
                }
                if !batch.places.isEmpty {
                    // Like the interests question: "Your picks" appears with the first pick, above the suggestions.
                    // One ForEach with stable IDs, so a picked card slides up instead of fading between sections.
                    LazyVStack(spacing: 10) {
                        ForEach(listItems) { entry in
                            switch entry {
                            case .picksHeader(let count): picksHeader(count: count)
                            case .suggestionsHeader(let spaced): suggestionsHeader.padding(.top, spaced ? 8 : 0)
                            case .place(let item): row(item)
                            }
                        }
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
            if canLoadRecommendations { await load() }
        }
        .onChange(of: location.point) { _, point in
            if requiresOrigin, origin == nil, let point {
                setOrigin?(.init(id: UUID(), name: "Current device position", location: point, visitSeconds: 2700))
            }
        }
        .overlay {
            if showsProcessing {
                RecommendationsProcessingView()
            } else if showsFoundIntro {
                RecommendationsFoundView()
                    .transition(reduceMotion ? .opacity
                        : .asymmetric(insertion: .opacity,
                                      removal: .opacity.combined(with: .scale(scale: 1.04)).combined(with: .offset(y: -16))))
            }
        }
        .onChange(of: showsProcessing) { wasProcessing, isProcessing in
            // Only the first search, shown full screen, hands off through "Here's what we found".
            guard wasProcessing, !isProcessing, error == nil, !batch.places.isEmpty else { return }
            foundIntroTask?.cancel()
            showsFoundIntro = true
            foundIntroTask = Task {
                try? await Task.sleep(for: .seconds(reduceMotion ? 1.2 : 1.8))
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.5)) { showsFoundIntro = false }
            }
        }
        .refreshable {
            if canLoadRecommendations { await refresh() }
        }
        .accessibilityAction(named: "Refresh recommendations") { retry() }
        .onDisappear { location.cancel(); retryTask?.cancel(); foundIntroTask?.cancel(); cancel() }
        .background(AppColor.canvas.ignoresSafeArea())
        .bottomActionBar {
            VStack(spacing: 10) {
                if let limit = maximumSelection, selected.count > limit {
                    Button("Review My Places") { showsSelected = true }
                }
                QuestionPrimaryButton(nextTitle, action: complete)
                    .disabled(selected.count < minimumSelection)
                    .accessibilityIdentifier("recommendationsNext")
            }
        }
        .sheet(isPresented: $showsSelected) {
            SelectedPlacesView(existing: [], selected: selectedPlaces,
                               details: Dictionary(selected.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }))
        }
        .fullScreenCover(isPresented: $showsOriginSearch) {
            PlanningSearchSheet(near: origin, title: "Starting point") { place in
                location.cancel()
                setOrigin?(place)
            }
        }
        .navigationTitle("Recommendations")
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppColor.accent)
    }

    private func row(_ item: RecommendedPlace) -> some View {
        RecommendationPlaceRow(item: item, userLocation: requiresOrigin ? origin : (usesDeviceLocation ? location.point : previewLocation),
                               isSelected: selectedIDs.contains(item.id), isExisting: false,
                               isDisabled: false, isLocked: isLocked(item)) {
            if isLocked(item) {
                rejectedSelectionCount += 1
            } else {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.2)) { toggle(item) }
            }
        }
    }

    /// "Your picks" with its count and what's still needed, and Manage for My Places.
    private func picksHeader(count: Int) -> some View {
        let note: LocalizedStringKey? = count < minimumSelection ? "\(minimumSelection - count) more"
            : (maximumSelection.map { count >= $0 } == true ? "Full" : nil)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Your picks").font(.headline).accessibilityAddTraits(.isHeader)
            Text(count, format: .number)
                .font(.headline)
                .foregroundStyle(AppColor.secondaryText)
                .contentTransition(.numericText(value: Double(count)))
                .accessibilityLabel(Text("\(count) places selected"))
                .accessibilityIdentifier("placesSelectedCount")
            if let note {
                (Text(verbatim: "· ") + Text(note))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.secondaryText)
                    .transition(.opacity)
                    .accessibilityIdentifier("placeSelectionStatus")
            }
            Spacer(minLength: 8)
            Button { showsSelected = true } label: {
                Text("Manage").font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
            .accessibilityLabel(Text("My Places"))
            .accessibilityIdentifier("recommendationsMyPlaces")
        }
        .padding(.horizontal, 4)
        .keyframeAnimator(initialValue: CGFloat.zero, trigger: rejectedSelectionCount) { header, offset in
            header.offset(x: reduceMotion ? 0 : offset)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(CGFloat(-5), duration: 0.07)
                SpringKeyframe(CGFloat(5), duration: 0.07)
                SpringKeyframe(CGFloat(-3), duration: 0.07)
                SpringKeyframe(CGFloat.zero, duration: 0.12)
            }
        }
        .sensoryFeedback(.warning, trigger: rejectedSelectionCount)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: count)
    }

    private var suggestionsHeader: some View {
        Text("Suggestions")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private enum ListItem: Identifiable {
        case picksHeader(Int), suggestionsHeader(spaced: Bool), place(RecommendedPlace)

        var id: String {
            switch self {
            case .picksHeader: "header-picks"
            case .suggestionsHeader: "header-suggestions"
            case .place(let item): item.id.uuidString
            }
        }
    }

    private var listItems: [ListItem] {
        let picked = orderedPlaces.filter { selectedIDs.contains($0.id) }
        let rest = orderedPlaces.filter { !selectedIDs.contains($0.id) }
        return (picked.isEmpty ? [] : [.picksHeader(picked.count)] + picked.map(ListItem.place))
            + [.suggestionsHeader(spaced: !picked.isEmpty)] + rest.map(ListItem.place)
    }

    /// Picked places rise to the top in the order they were picked; the rest keep the recommended order.
    private var orderedPlaces: [RecommendedPlace] {
        let picked = selected.compactMap { choice in batch.places.first { $0.id == choice.id } }
        return picked + batch.places.filter { !selectedIDs.contains($0.id) }
    }

    private var nextTitle: LocalizedStringKey {
        countsInNextButton && selected.count >= minimumSelection ? "Plan with \(selected.count) places" : "Next"
    }

    private func isLocked(_ item: RecommendedPlace) -> Bool {
        guard let limit = maximumSelection else { return false }
        return !selectedIDs.contains(item.id) && selected.count >= limit
    }

    private func retry() {
        guard !isLoading, canLoadRecommendations else { return }
        retryTask?.cancel()
        retryTask = Task { await refresh() }
    }
}

/// "N places selected", followed by what's still needed: the minimum until it's met, then nothing
/// (the enabled primary button says "ready"), and a note only once the selection is full.
/// Shakes with a warning haptic when a tap is refused because the selection is full.
struct PlaceSelectionStatus: View {
    let count: Int
    let minimum: Int
    let maximum: Int?
    var rejectedCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var guidance: Text? { Self.guidance(count: count, minimum: minimum, maximum: maximum) }

    static func guidance(count: Int, minimum: Int, maximum: Int?) -> Text? {
        if count < minimum {
            return count == 0 ? Text("Pick at least \(minimum)") : Text("Pick \(minimum - count) more")
        }
        if let maximum, count >= maximum { return Text("That's the max") }
        return nil
    }

    /// Changes only when the guidance line itself changes, so its fade runs once per state.
    private var guidanceState: Int {
        count < minimum ? count : (maximum.map { count >= $0 } == true ? -1 : -2)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("\(count) places selected")
                .foregroundStyle(AppColor.secondaryText)
                .contentTransition(.numericText())
                .accessibilityIdentifier("placesSelectedCount")
            if let guidance {
                Text(verbatim: "·").foregroundStyle(AppColor.secondaryText).accessibilityHidden(true)
                guidance
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.primaryText)
                    .contentTransition(.numericText())
                    .transition(.opacity)
                    .accessibilityIdentifier("placeSelectionStatus")
            }
        }
        .animation(.snappy, value: count)
        .animation(.snappy, value: guidanceState)
        .keyframeAnimator(initialValue: CGFloat.zero, trigger: rejectedCount) { line, offset in
            line.offset(x: reduceMotion ? 0 : offset)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(CGFloat(-6), duration: 0.07)
                SpringKeyframe(CGFloat(6), duration: 0.07)
                SpringKeyframe(CGFloat(-3), duration: 0.07)
                SpringKeyframe(CGFloat.zero, duration: 0.12)
            }
        }
        .sensoryFeedback(.warning, trigger: rejectedCount)
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

// MARK: - Starting point prompt

/// Shown before recommendations can load: the list needs a starting point to measure "nearby".
private struct OriginPrompt: View {
    let isRequesting: Bool
    let permissionDenied: Bool
    let failed: Bool
    let offersDeviceLocation: Bool
    let useCurrentLocation: () -> Void
    let openSettings: () -> Void
    let chooseStartingPoint: () -> Void

    private var statusText: LocalizedStringKey? {
        if permissionDenied { return "Location access is off. Turn it on in Settings or choose a starting point." }
        if failed { return "Couldn’t get your location. Try again or choose a starting point." }
        return nil
    }

    var body: some View {
        VStack(spacing: 18) {
            OriginEmblem(isRequesting: isRequesting, permissionDenied: permissionDenied)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Where does your trip start?").font(.title3.bold())
                Text(statusText ?? "Choose a starting point to find nearby places.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            VStack(spacing: 6) {
                if offersDeviceLocation { deviceLocationButton }
                Button("Choose starting point", action: chooseStartingPoint)
                    .font(.body.weight(.semibold))
                    .tint(AppColor.accent)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 56)
        .animation(.snappy, value: isRequesting)
        .animation(.snappy, value: permissionDenied)
    }

    /// While locating, the button keeps its size and colour: a small spinner takes the icon's fixed slot
    /// and taps are ignored instead of greying the button out.
    private var deviceLocationButton: some View {
        Button(action: permissionDenied ? openSettings : useCurrentLocation) {
            HStack(spacing: 8) {
                ZStack {
                    if isRequesting {
                        ProgressView().controlSize(.small).tint(AppColor.onBrand)
                            .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    } else {
                        Image(systemName: permissionDenied ? "gear" : "location.fill")
                            .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    }
                }
                .frame(width: 22, height: 22)
                Text(isRequesting ? "Finding your location…" : permissionDenied ? "Open Settings" : "Use current location")
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(AppColor.brand)
        .allowsHitTesting(!isRequesting)
        .accessibilityAddTraits(isRequesting ? .updatesFrequently : [])
    }
}

/// A pin floating over its shadow inside two soft discs; it bobs faster while locating.
/// Reduce Motion and denied access show it at rest.
private struct OriginEmblem: View {
    let isRequesting: Bool
    let permissionDenied: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(AppColor.accent.opacity(0.08)).frame(width: 132, height: 132)
            Circle().fill(AppColor.accent.opacity(0.12)).frame(width: 92, height: 92)
            if permissionDenied {
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
                    .transition(.scale.combined(with: .opacity))
            } else if reduceMotion {
                pin(lift: 0.5)
            } else {
                TimelineView(.animation) { context in
                    let speed = isRequesting ? 4.0 : 1.6
                    pin(lift: (sin(context.date.timeIntervalSinceReferenceDate * speed) + 1) / 2)
                }
            }
        }
        .frame(width: 200, height: 200)
    }

    /// `lift` runs 0 (resting) to 1 (highest); the shadow shrinks and fades as the pin rises.
    private func pin(lift: Double) -> some View {
        ZStack {
            Ellipse().fill(AppColor.accent.opacity(0.35 - 0.2 * lift))
                .frame(width: 28 - 12 * lift, height: 8 - 3 * lift)
                .offset(y: 22)
            Image(systemName: "mappin")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(AppColor.accent)
                .offset(y: -4 - 14 * lift)
        }
    }
}
