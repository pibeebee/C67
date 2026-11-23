import SwiftUI
import C67Domain

struct ItineraryListView: View {
    private struct StopDrag {
        let source: UUID
        let originalIndex: Int
        let frames: [CGRect]
        let cardHeight: CGFloat
        let startY: CGFloat
        let startTimelineY: CGFloat
        var finger: CGPoint
        var targetIndex: Int

        func translation(timelineY: CGFloat) -> CGFloat {
            finger.y - startY + startTimelineY - timelineY
        }

        func position(of index: Int) -> Int {
            if index == originalIndex { return targetIndex }
            if originalIndex < index, index <= targetIndex { return index - 1 }
            if targetIndex <= index, index < originalIndex { return index + 1 }
            return index
        }

        var slotY: CGFloat {
            let destination = frames[targetIndex]
            if targetIndex > originalIndex { return destination.maxY - frames[originalIndex].height }
            return destination.minY
        }
    }

    private struct ScrollRange: Equatable {
        let offset: CGFloat
        let maximum: CGFloat
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var timelineMarkerSize = 24
    let proposal: PlanProposal
    var excludedPlaces: [String] = []
    var editEndpoints: ((ItineraryEditRoute) -> Void)?
    var details: [UUID: ItineraryStopDetails] = [:]
    var departureWeather: String?
    var isDesignPreview = false
    var isSaving = false
    var error: String?
    var retryTitle: LocalizedStringKey = "Try again"
    var canSave = true
    var heading: String?
    var editTitle: (() -> Void)?
    var editDeparture: (() -> Void)?
    var startNow: (() -> Void)?
    var showsSaveAction = true
    var actionTitle = "Save Itinerary"
    var completionMessage: LocalizedStringKey?
    var showsPreparation = true
    var allowsEditing = true
    var navigationTitle = "Itinerary"
    var retry: (() -> Void)?
    var refreshRoute: (() -> Void)?
    var lookupHours: ((String) async -> PlanningHoursLookup)? = nil
    let edit: (UUID?) -> Void
    let save: () -> Void
    var move: (@MainActor (UUID, UUID) async -> Void)? = nil
    @State private var drag: StopDrag?
    @State private var pendingOrder: [UUID]?
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var cardHeights: [UUID: CGFloat] = [:]
    @State private var timelineFrame = CGRect.zero
    @State private var viewport = CGRect.zero
    @State private var scrollPosition = ScrollPosition()
    @State private var scrollRange = ScrollRange(offset: 0, maximum: 0)
    @State private var isRetryingHours = false
    @State private var hoursByPlace: [String: PlanningHoursLookup] = [:]
    @State private var departureForecast = DepartureWeatherLoader()

    var body: some View {
        let stops = proposal.stopsWithExperienceEstimates
        let isExperience = proposal.usesExperienceFlow
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isExperience {
                    HStack(spacing: 4) {
                        // The trip name is the page title: Large Title, as in a navigation bar's large title.
                        Text(heading ?? proposal.input.title)
                            .font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        if let editTitle {
                            Button(action: editTitle) {
                                Image(systemName: "pencil").font(.title3).frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit trip name")
                            .accessibilityIdentifier("itineraryEditTitle")
                        }
                    }
                    .padding(.horizontal, 4)
                } else {
                    Text(heading ?? (!excludedPlaces.isEmpty ? "Your itinerary is partly ready" : proposal.feasible ? "Here’s your itinerary" : "Your choices need adjustment"))
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 4)
                }

                if let error {
                    RecoveryNotice(title: "Itinerary needs attention", message: error,
                                   primary: retry.map { .init(title: retryTitle, perform: $0) })
                }
                // Planner diagnostics (review, opening hours, trip details, return leg) show in developer builds only.
                if AppMode.current.showsPlanningDiagnostics, let assessment = proposal.scheduleAssessment, proposal.feasible {
                    let needsReview = !assessment.unresolved.isEmpty || proposal.hasExperienceTravelFallback ||
                        !proposal.warnings.isEmpty || !excludedPlaces.isEmpty
                    ItineraryReviewNotice(needsReview: needsReview,
                                          issues: assessment.unresolved.map { $0.message(in: proposal.input) })
                }

                ItineraryDepartureCard(proposal: proposal, departureForecast: departureForecast,
                                       weatherAdvice: departureWeather, isDesignPreview: isDesignPreview,
                                       editDeparture: editDeparture, editEndpoints: isExperience ? editEndpoints : nil)

                if showsPreparation, proposal.feasible, !stops.isEmpty {
                    ItineraryPreparationCard(
                        forecast: departureForecast.forecast(for: proposal.input.origin, departure: proposal.estimatedExperienceDeparture),
                        hoursConflicts: hoursConflicts(in: stops),
                        hasDefaultTravelTime: proposal.hasExperienceTravelFallback
                    )
                }

                if AppMode.current.showsPlanningDiagnostics, allowsEditing, isExperience, lookupHours != nil {
                    DisclosureGroup("Opening hours") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Regular hours may differ on holidays or for individual activities. Travel and visit times are estimates.")
                            ForEach(stops) { stop in
                                if let place = proposal.input.places.first(where: { $0.id == stop.id }) {
                                    Text("\(stop.name): \(hoursLabel(place: place, stop: stop))")
                                }
                            }
                            if hoursByPlace.values.contains(where: { $0.status == "available" }) {
                                Text("Hours from Apple Maps")
                            }
                            if let lookupHours, hoursByPlace.values.contains(where: { ["temporary_error", "rate_limited"].contains($0.status) }) {
                                if hoursByPlace.values.contains(where: { $0.status == "rate_limited" }) {
                                    Text("Opening hours are temporarily limited. Wait before trying again.")
                                }
                                Button("Try checking hours again") {
                                    guard !isRetryingHours else { return }
                                    isRetryingHours = true
                                    Task {
                                        defer { isRetryingHours = false }
                                        let failedIDs = hoursByPlace.filter { ["temporary_error", "rate_limited"].contains($0.value.status) }.map(\.key)
                                        for id in failedIDs {
                                            let result = await lookupHours(id)
                                            guard !Task.isCancelled else { return }
                                            hoursByPlace[id] = result
                                        }
                                    }
                                }
                                .disabled(isRetryingHours)
                            }
                        }.font(.footnote)
                    }
                    .padding(12)
                    .background(Color("ItinerarySurface"), in: .rect(cornerRadius: 14))
                    .accessibilityIdentifier("itineraryOpeningHours")
                }

                if let editEndpoints, !isExperience {
                    ViewThatFits(in: .horizontal) {
                        HStack { tripEdits(editEndpoints) }
                        VStack(alignment: .leading) { tripEdits(editEndpoints) }
                    }
                    .buttonStyle(.bordered)
                }
                if !excludedPlaces.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Places not in this plan").font(.headline)
                        ForEach(excludedPlaces.indices, id: \.self) { index in
                            Text(excludedPlaces[index]).font(.footnote)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("itineraryUnscheduled")
                }

                Text("Your step-by-step itinerary")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.leading, timelineIndent)
                    .padding(.top, 4)

                if let refreshRoute {
                    Button("Refresh driving estimates", systemImage: "arrow.clockwise", action: refreshRoute)
                        .font(.footnote)
                        .disabled(isSaving)
                }

                if proposal.stops.isEmpty {
                    ContentUnavailableView("No places in this itinerary", systemImage: "map",
                                           description: Text("Add a place and plan your trip again."))
                } else {
                    timeline(stops)
                }

                if allowsEditing {
                    Button("Add another place", action: addPlace)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(isSaving || (!proposal.usesExperienceFlow && proposal.input.places.count >= 6))
                        .accessibilityIdentifier("itineraryAddPlace")
                }

                ItineraryMapView(proposal: proposal, showsTripDetails: AppMode.current.showsPlanningDiagnostics)
                if AppMode.current.showsPlanningDiagnostics, proposal.input.planningEndpoint != nil,
                   let seconds = proposal.returnTravelSeconds {
                    let destination = proposal.input.enginePreferences?.endPointName ?? "starting point"
                    let action = proposal.input.enginePreferences?.endPointName == nil ? "Return to" : "End at"
                    Label("\(action) \(destination) · \(Int(ceil(Double(seconds) / 60))) min · arrive by \(ItineraryFormatting.time(proposal.finishesAt, zone: proposal.input.timeZone, locale: .current))", systemImage: "arrow.uturn.backward")
                        .font(.footnote)
                }

                if proposal.synthetic {
                    Text(isDesignPreview ? "Design preview · sample itinerary from Sketch" : "Synthetic demonstration · trips last until the app closes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("itineraryList")
        .bottomActionBar(isVisible: showsSaveAction || startNow != nil) {
            itineraryActions(hasStops: !stops.isEmpty)
        }
        .scrollPosition($scrollPosition)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { viewport = $0 }
        .onScrollGeometryChange(for: ScrollRange.self) { geometry in
            ScrollRange(offset: geometry.contentOffset.y + geometry.contentInsets.top,
                        maximum: max(0, geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom - geometry.containerSize.height))
        } action: { _, range in
            scrollRange = range
        }
        .task(id: autoScrollDirection) { await scrollWhileDragging() }
        .sensoryFeedback(.selection, trigger: drag?.targetIndex) { old, new in old != nil && new != nil }
        .onChange(of: stops.map(\.id)) { _, _ in cancelDrag() }
        .task(id: proposal.input.places) {
            guard let lookupHours else { return }
            for place in proposal.input.places where stops.contains(where: { $0.id == place.id }) {
                guard !Task.isCancelled, let source = place.sourceID, source.hasPrefix("apple:") else { continue }
                let id = String(source.dropFirst(6))
                if hoursByPlace[id] == nil {
                    let result = await lookupHours(id)
                    guard !Task.isCancelled else { return }
                    hoursByPlace[id] = result
                }
            }
        }
        .background(Color("TripCanvas"))
        .tint(Color("ItineraryAction"))
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func itineraryActions(hasStops: Bool) -> some View {
        VStack(spacing: 8) {
            if let completionMessage {
                Label(completionMessage, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
            }
            if let startNow {
                Button("Start your trip today", action: startNow)
                    .buttonStyle(TripPrimaryButtonStyle())
                    .accessibilityIdentifier("itineraryStartNow")
            }
            if showsSaveAction {
                Button(action: save) {
                    HStack {
                        if isSaving { ProgressView() }
                        Text(isSaving ? "Please wait…" : actionTitle)
                    }
                }
                .buttonStyle(TripPrimaryButtonStyle())
                .accessibilityIdentifier("Save this trip")
            }
        }
        .disabled(isSaving || !canSave || !proposal.feasible || !hasStops)
    }

    private var reorderAnimation: Animation? { reduceMotion ? nil : .snappy(duration: 0.23, extraBounce: 0) }
    private var timelineIndent: CGFloat { timelineMarkerSize + 10 }
    private var markedSlot: Int? {
        guard let drag, drag.targetIndex != drag.originalIndex, isInDropArea(drag.finger) else { return nil }
        return drag.targetIndex
    }

    private func timeline(_ stops: [ScheduledPlanningStop]) -> some View {
        let ordered = pendingOrder?.compactMap { id in stops.first { $0.id == id } } ?? stops
        let displayed = ordered.count == stops.count ? ordered : stops
        return VStack(spacing: 0) {
            ForEach(Array(displayed.enumerated()), id: \.element.id) { index, stop in
                let lifted = drag?.source == stop.id
                ZStack {
                    timelineRow(index: index, stop: stop, stops: displayed, lifted: lifted)
                        .offset(y: rowOffset(index: index, lifted: lifted))
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("itineraryTimeline")) } action: {
                    rowFrames[stop.id] = $0
                }
                .zIndex(lifted ? 1 : 0)
                .animation(lifted ? nil : reorderAnimation, value: drag?.targetIndex)
            }
        }
        .background(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                if let drag, markedSlot != nil {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(AppColor.accent.opacity(0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(AppColor.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 4]))
                        }
                        .frame(height: drag.cardHeight + 4)
                        .padding(.leading, timelineIndent - 2)
                        .padding(.trailing, -2)
                        .offset(y: drag.slotY - 2)
                        .transition(.opacity)
                }
            }
            .animation(reorderAnimation, value: markedSlot)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .coordinateSpace(.named("itineraryTimeline"))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            timelineFrame = $0
            updateTarget()
        }
    }

    private func timelineRow(index: Int, stop: ScheduledPlanningStop, stops: [ScheduledPlanningStop], lifted: Bool) -> some View {
        let next = index + 1 < stops.count ? stops[index + 1] : nil
        let isExperience = proposal.usesExperienceFlow
        let place = proposal.input.places.first { $0.id == stop.id }
        var stopDetails = details[stop.id] ?? ItineraryStopDetails()
        let poi = place.flatMap { RecommendedPlace(place: $0).poiPresentation }
        if stopDetails.category == nil { stopDetails.category = poi?.label }
        let distance = next.flatMap { next in
            if let meters = next.roadDistanceMeters { return formattedDistance(meters) }
            return isExperience ? nil : details[next.id]?.distance
        }
        let reorder: ((DragGesture.Value) -> Void)? = move == nil || stops.count < 2 ? nil : {
            updateDrag($0, source: stop.id, index: index, stops: stops)
        }
        let up: (() -> Void)? = index > 0 ? { commitMove(from: index, to: index - 1, stops: stops) } : nil
        let down: (() -> Void)? = index + 1 < stops.count ? { commitMove(from: index, to: index + 1, stops: stops) } : nil
        return ItineraryTimelineRow(markerSize: timelineMarkerSize, stop: stop, number: (drag?.position(of: index) ?? index) + 1, isLast: next == nil,
                                    nextStop: next, nextDistance: distance,
                                    mode: proposal.input.mode, zone: proposal.input.timeZone,
                                    details: stopDetails, isEditable: allowsEditing,
                                    weatherEvidence: proposal.evidence.filter { $0.kind == "weather" },
                                    orderingOnly: isExperience, symbol: poi?.symbol, edit: { edit(stop.id) },
                                    reorderChanged: reorder, reorderEnded: { finishDrag($0, source: stop.id, stops: stops) },
                                    reorderCancelled: { if drag?.source == stop.id { cancelDrag() } },
                                    isLifted: lifted, isReordering: drag != nil || pendingOrder != nil,
                                    moveUp: up, moveDown: down, cardHeightChanged: { cardHeights[stop.id] = $0 })
    }

    @ViewBuilder private func tripEdits(_ edit: @escaping (ItineraryEditRoute) -> Void) -> some View {
        Button("Change start") { edit(.startingPoint) }
        Button("Change end") { edit(.endPoint) }
        if !proposal.usesExperienceFlow { Button("Change time") { edit(.tripTime) } }
    }

    private func updateDrag(_ value: DragGesture.Value, source: UUID, index: Int, stops: [ScheduledPlanningStop]) {
        guard !isSaving, pendingOrder == nil else { return }
        if drag == nil {
            let frames = stops.compactMap { rowFrames[$0.id] }
            guard frames.count == stops.count, let cardHeight = cardHeights[source] else { return }
            drag = StopDrag(source: source, originalIndex: index, frames: frames, cardHeight: cardHeight, startY: value.startLocation.y,
                            startTimelineY: timelineFrame.minY, finger: value.location, targetIndex: index)
        }
        guard drag?.source == source else { return }
        drag?.finger = value.location
        updateTarget()
    }

    private func updateTarget() {
        guard let drag else { return }
        let center = drag.frames[drag.originalIndex].midY + drag.translation(timelineY: timelineFrame.minY)
        if let target = drag.frames.indices.min(by: { abs(drag.frames[$0].midY - center) < abs(drag.frames[$1].midY - center) }),
           target != drag.targetIndex {
            self.drag?.targetIndex = target
        }
    }

    private func rowOffset(index: Int, lifted: Bool) -> CGFloat {
        guard let drag, drag.frames.indices.contains(index) else { return 0 }
        if lifted { return drag.translation(timelineY: timelineFrame.minY) }
        let position = drag.position(of: index)
        guard position != index else { return 0 }
        return drag.frames[drag.originalIndex].height * (position < index ? -1 : 1)
    }

    private func finishDrag(_ value: DragGesture.Value, source: UUID, stops: [ScheduledPlanningStop]) {
        guard let drag, drag.source == source else { return }
        self.drag?.finger = value.location
        updateTarget()
        guard let target = self.drag?.targetIndex, target != drag.originalIndex, isInDropArea(value.location) else {
            cancelDrag()
            return
        }
        commitMove(from: drag.originalIndex, to: target, stops: stops)
    }

    private func isInDropArea(_ point: CGPoint) -> Bool {
        viewport.contains(point) && timelineFrame.insetBy(dx: -16, dy: -16).contains(point)
    }

    private func cancelDrag() {
        guard drag != nil else { return }
        withAnimation(reorderAnimation) { drag = nil }
    }

    private func commitMove(from source: Int, to target: Int, stops: [ScheduledPlanningStop]) {
        guard let move, !isSaving, pendingOrder == nil else {
            cancelDrag()
            return
        }
        var ordered = stops.map(\.id)
        ordered.insert(ordered.remove(at: source), at: target)
        withAnimation(reorderAnimation) {
            pendingOrder = ordered
            drag = nil
        }
        Task {
            await move(stops[source].id, stops[target].id)
            withAnimation(reorderAnimation) { pendingOrder = nil }
        }
    }

    private var autoScrollDirection: CGFloat {
        guard let drag, viewport.insetBy(dx: -16, dy: 0).contains(drag.finger) else { return 0 }
        if drag.finger.y < viewport.minY + 56 { return -1 }
        if drag.finger.y > viewport.maxY - 56 { return 1 }
        return 0
    }

    private func scrollWhileDragging() async {
        let direction = autoScrollDirection
        guard direction != 0 else { return }
        while !Task.isCancelled, autoScrollDirection == direction {
            let next = min(max(scrollRange.offset + 9 * direction, 0), scrollRange.maximum)
            // Stop at the first or last visit when the whole view extends beyond the timeline.
            let withinTimeline = direction < 0 ? timelineFrame.minY < viewport.minY + 56 : timelineFrame.maxY > viewport.maxY - 56
            if withinTimeline, next != scrollRange.offset { scrollPosition.scrollTo(y: next) }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private func formattedDistance(_ meters: Double) -> String {
        if meters < 1_000 { return "\(Int(meters.rounded())) m" }
        return "\((meters / 1_000).formatted(.number.precision(.fractionLength(1)))) km"
    }

    private func hoursLabel(place: PlanningPlace, stop: ScheduledPlanningStop) -> String {
        let fallback = categoryHoursHint(for: place)
        guard let source = place.sourceID, source.hasPrefix("apple:") else { return "Hours unavailable — check before visiting.\(fallback)" }
        let id = String(source.dropFirst(6))
        guard let lookup = hoursByPlace[id] else { return "Checking hours…" }
        guard let hours = lookup.hours, lookup.status == "available", let start = stop.visitStartsAt ?? stop.arrivalAt, let end = stop.departureAt else {
            let message = ["temporary_error", "configuration_error", "not_configured", "rate_limited"].contains(lookup.status)
                ? "Could not check hours — check before visiting." : "Hours unavailable — check before visiting."
            return message + fallback
        }
        switch hours.match(start: start, end: end) {
        case .within: return "Estimated visit fits regular hours."
        case .partial: return "Estimated visit partly outside regular hours."
        case .outside: return "Estimated visit outside regular hours."
        case .unknown: return "Hours could not be compared — check before visiting." + fallback
        }
    }

    private func hoursConflicts(in stops: [ScheduledPlanningStop]) -> [String] {
        stops.compactMap { stop in
            guard let source = proposal.input.places.first(where: { $0.id == stop.id })?.sourceID,
                  source.hasPrefix("apple:"), let lookup = hoursByPlace[String(source.dropFirst(6))],
                  lookup.status == "available", let hours = lookup.hours,
                  let start = stop.visitStartsAt ?? stop.arrivalAt, let end = stop.departureAt else { return nil }
            switch hours.match(start: start, end: end) {
            case .partial, .outside: return stop.name
            case .within, .unknown: return nil
            }
        }
    }

    private func categoryHoursHint(for place: PlanningPlace) -> String {
        guard proposal.scheduleAssessment?.unresolved.contains(where: {
            $0.placeID == place.id && $0.source == EstimatedVisitWindow.source
        }) == true else { return "" }
        let estimate = EstimatedVisitWindow(categories: place.categories)
        let label = estimate.closesHour >= 24 ? "\(estimate.clockLabel) next day" : estimate.clockLabel
        return " Estimated visit window: \(label). Actual hours may differ."
    }

    private func addPlace() { edit(nil) }
}

#if DEBUG
    #Preview("ITINERARY LIST · Light") {
        ItineraryDesignPreview()
            .preferredColorScheme(.light)
    }

    #Preview("ITINERARY LIST · Dark") {
        ItineraryDesignPreview()
            .preferredColorScheme(.dark)
    }
#endif

/// Developer-only schedule assessment.
private struct ItineraryReviewNotice: View {
    let needsReview: Bool
    let issues: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Schedule diagnostics").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(needsReview ? "\(issues.count + 1) to check" : "1 to check")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(needsReview ? .orange : AppColor.accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((needsReview ? Color.orange : AppColor.accent).opacity(0.12), in: .capsule)
            }
            .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) {
                checkRow(symbol: needsReview ? "exclamationmark.circle.fill" : "checkmark.circle.fill",
                         tint: needsReview ? .orange : .green,
                         title: needsReview ? "Visit and travel details" : "Schedule ready",
                         detail: needsReview ? "Some details are marked below." : nil)
                ForEach(issues, id: \.self) { issue in
                    Divider().padding(.leading, 48)
                    checkRow(symbol: "circle", tint: .orange, title: nil, detail: issue)
                }
                Divider().padding(.leading, 48)
                checkRow(symbol: "clock.fill", tint: AppColor.accent, title: "Opening hours",
                         detail: "Hours can change at any time, especially on holidays. Confirm before you head out.")
            }
            .background(AppColor.surface, in: .rect(cornerRadius: 22, style: .continuous))
        }
        .accessibilityIdentifier("itineraryReviewNotice")
    }

    private func checkRow(symbol: String, tint: Color, title: LocalizedStringKey?, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 22).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if let title { Text(title).font(.subheadline.weight(.semibold)) }
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(title == nil ? AppColor.primaryText : AppColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
