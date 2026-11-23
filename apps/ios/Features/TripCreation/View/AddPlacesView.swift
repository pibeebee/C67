import SwiftUI
import MapKit
import C67Domain

/// The six ADD PLACES states share one search and selection surface.
struct AddPlacesView: View {
    @Binding var query: String
    let results: [RecommendedPlace]
    let selected: [RecommendedPlace]
    var isSearching = false
    var hasSearched = false
    var showsPreviousResults = false
    var error: String?
    var synthetic = false
    var initiallyFocused = false
    var maximumSelection: Int?
    var origin: PlanningPoint?
    let search: () async -> Void
    let toggle: (RecommendedPlace) -> Void
    let next: () -> Void
    @State private var showsSelected = false
    @State private var rejectedSelectionCount = 0
    @State private var mapPlace: RecommendedPlace?
    @State private var isSearchPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A specific-place trip can be planned around a single place.
    private let minimum = 1

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var displayed: [RecommendedPlace] { trimmedQuery.isEmpty ? (results.isEmpty ? selected : results) : results }
    private var selectedIDs: Set<UUID> { Set(selected.map(\.id)) }
    private var unpicked: [RecommendedPlace] { displayed.filter { !selectedIDs.contains($0.id) } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                statusContent
                placeList
                if synthetic {
                    Text("Synthetic place search · demonstration only")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.2), value: selected.map(\.id))
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColor.canvas)
        .searchable(text: $query, isPresented: $isSearchPresented,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Search a place, café or landmark"))
        .onSubmit(of: .search) { isSearchPresented = false }
        .bottomActionBar {
            VStack(alignment: .leading, spacing: 16) {
                if let limit = maximumSelection, selected.count > limit {
                    Button("Review My Places") { showsSelected = true }
                }
                QuestionPrimaryButton("Next") { isSearchPresented = false; next() }
                    .disabled(selected.count < minimum)
                    .accessibilityIdentifier("addPlacesNext")
            }
        }
        .navigationTitle("Add Specific Place")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsSelected) {
            PlacesSelectionSheet(places: selected, remove: toggle)
        }
        .sheet(item: $mapPlace) { item in mapSheet(item) }
        .task(id: query) {
            do {
                try await Task.sleep(for: .milliseconds(300))
                try Task.checkCancellation()
                await search()
            } catch { }
        }
        .task { if initiallyFocused { isSearchPresented = true } }
        .sensoryFeedback(.warning, trigger: rejectedSelectionCount)
    }

    // MARK: Status (searching, error, empty)

    @ViewBuilder private var statusContent: some View {
        if isSearching {
            ProgressView("Searching places…").frame(maxWidth: .infinity).padding()
        }
        if let error {
            RecoveryNotice(title: "Search unavailable", message: error, icon: "wifi.exclamationmark",
                           primary: .init(title: "Try again") { Task { await search() } })
        } else if displayed.isEmpty && !isSearching && trimmedQuery.isEmpty {
            emptySteps
        } else if displayed.isEmpty && !isSearching && hasSearched {
            ContentUnavailableView.search(text: trimmedQuery)
                .padding(.top, 24)
        }
    }

    // MARK: Empty state

    /// Before the first search: how the screen works, as three steps in one card.
    private var emptySteps: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Build your trip in three steps").font(AppFont.title3.bold()).padding(.horizontal, 4)
            VStack(spacing: 0) {
                stepRow(symbol: "magnifyingglass", title: "Search a place", detail: "A café, museum, landmark or area.")
                Divider().padding(.leading, 68)
                stepRow(symbol: "plus", title: "Add it to your picks", detail: "Tap + on each place you want to visit.")
                Divider().padding(.leading, 68)
                stepRow(symbol: "map", title: "Plan your trip", detail: "We order your stops and time each visit.")
            }
            .background(AppColor.surface, in: .rect(cornerRadius: 22, style: .continuous))
        }
        .padding(.top, 16)
    }

    private func stepRow(symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColor.onBrand)
                .frame(width: 40, height: 40)
                .background(AppColor.brand, in: .rect(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(AppColor.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var resultsTitle: LocalizedStringKey {
        trimmedQuery.isEmpty ? "Suggestions" : (showsPreviousResults ? "Previous results" : "Results")
    }

    // MARK: List — same cards and "Your picks" section as Recommendations.

    /// One ForEach with stable IDs, so a picked card slides into "Your picks" and redraws as selected.
    @ViewBuilder private var placeList: some View {
        ForEach(listItems) { entry in
            switch entry {
            case .picksHeader: picksHeader
            case .resultsHeader(let spaced): sectionTitle(resultsTitle).padding(.top, spaced ? 8 : 0)
            case .place(let item):
                AddPlaceCard(item: item, isSelected: selectedIDs.contains(item.id), isLocked: isLocked(item), origin: origin,
                             toggle: { tap(item) }, showMap: { mapPlace = item })
            }
        }
    }

    private enum ListItem: Identifiable {
        case picksHeader, resultsHeader(spaced: Bool), place(RecommendedPlace)

        var id: String {
            switch self {
            case .picksHeader: "header-picks"
            case .resultsHeader: "header-results"
            case .place(let item): item.id.uuidString
            }
        }
    }

    private var listItems: [ListItem] {
        var items: [ListItem] = []
        if !selected.isEmpty { items.append(.picksHeader); items += selected.map(ListItem.place) }
        if !unpicked.isEmpty { items.append(.resultsHeader(spaced: !selected.isEmpty)); items += unpicked.map(ListItem.place) }
        return items
    }

    private var picksHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Your picks").font(.headline).accessibilityAddTraits(.isHeader)
            Text(selected.count, format: .number)
                .font(.headline).foregroundStyle(AppColor.secondaryText)
                .contentTransition(.numericText(value: Double(selected.count)))
                .accessibilityLabel(Text("\(selected.count) places selected"))
            if let note = guidance {
                (Text(verbatim: "· ") + Text(note)).font(.subheadline.weight(.semibold)).foregroundStyle(AppColor.secondaryText)
            }
            Spacer(minLength: 8)
            Button { showsSelected = true } label: {
                Text("Manage").font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
            .accessibilityLabel(Text("My Places"))
            .accessibilityIdentifier("addPlacesSelection")
        }
        .padding(.horizontal, 4)
    }

    // MARK: Rows

    private func isLocked(_ item: RecommendedPlace) -> Bool {
        maximumSelection.map { !selectedIDs.contains(item.id) && selected.count >= $0 } ?? false
    }

    private func tap(_ item: RecommendedPlace) {
        if isLocked(item) { rejectedSelectionCount += 1 } else { toggle(item) }
    }

    private var guidance: LocalizedStringKey? {
        if selected.count < minimum { return "Pick at least \(minimum)" }
        if let maximumSelection, selected.count >= maximumSelection { return "Full" }
        return nil
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.headline).accessibilityAddTraits(.isHeader).padding(.horizontal, 4)
    }

    private func mapSheet(_ item: RecommendedPlace) -> some View {
        NavigationStack {
            Map(initialPosition: .region(.init(center: .init(latitude: item.place.location.latitude, longitude: item.place.location.longitude),
                                               latitudinalMeters: 1000, longitudinalMeters: 1000))) {
                Marker(item.place.name, coordinate: .init(latitude: item.place.location.latitude, longitude: item.place.location.longitude))
            }
            .navigationTitle(item.place.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { mapPlace = nil } } }
        }
    }
}

/// The recommendation card for a search result: photo or icon, name, one detail line, distance and
/// map link, and a 30pt add control that turns into a filled check with a blue outline when picked.
private struct AddPlaceCard: View {
    let item: RecommendedPlace
    let isSelected: Bool
    let isLocked: Bool
    let origin: PlanningPoint?
    let toggle: () -> Void
    let showMap: () -> Void

    private var detailLine: String {
        [item.poiPresentation?.label ?? item.category, item.shortAddress ?? item.address].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            PlaceThumbnail(imageName: item.previewImage, size: 76, systemImage: item.poiPresentation?.symbol ?? "mappin.and.ellipse")
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.place.name).font(.subheadline.weight(.semibold)).foregroundStyle(AppColor.primaryText)
                Text(verbatim: detailLine).font(.footnote).foregroundStyle(AppColor.secondaryText).lineLimit(2)
                HStack(spacing: 10) {
                    if item.straightLineDistance(from: origin) != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin").imageScale(.small)
                            Text(item.distanceDescription(from: origin))
                        }
                        .foregroundStyle(AppColor.secondaryText)
                    }
                    Button("View on map", action: showMap).fontWeight(.semibold)
                }
                .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: toggle) {
                ZStack {
                    Circle().fill(isSelected ? AppColor.brand : AppColor.tertiaryFill)
                    Image(systemName: isSelected ? "checkmark" : "plus")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(isSelected ? AppColor.onBrand : AppColor.accent)
                        .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer)))
                }
                .frame(width: 30, height: 30)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "Remove \(item.place.name)" : "Add \(item.place.name)")
            .accessibilityHint(isLocked ? Text("Remove a place to add this one.") : Text(""))
            .accessibilityIdentifier("placeToggle-\(item.id)")
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            shape.fill(AppColor.surface)
                .overlay { shape.strokeBorder(AppColor.accent, lineWidth: 1.5).opacity(isSelected ? 1 : 0) }
        }
        .opacity(isLocked ? 0.45 : 1)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}
