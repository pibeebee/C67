import SwiftUI
import MapKit
import C67Domain

struct ItineraryMapView: View {
    private static let cardDismissalDuration = 0.16
    private static let stopColors: [Color] = [.blue, .orange, .purple, .teal, .pink, .brown]

    private struct RouteTaskID: Equatable {
        let path: [PlanningPoint]
        let retry: Int
    }
    let proposal: PlanProposal
    /// "Trip details" (route estimates and planner notes) is a developer-build diagnostic.
    var showsTripDetails = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedStopID: UUID?
    @State private var previewMapPosition: MapCameraPosition = .automatic
    @State private var fullMapPosition: MapCameraPosition = .automatic
    @State private var fullMapCamera: MapCamera?
    @State private var overviewPosition: MapCameraPosition?
    @State private var selectedAddress: String?
    @State private var projectedPin: (id: UUID, point: CGPoint)?
    @State private var routes: [Int: MKRoute] = [:]
    @State private var loadedPath: [PlanningPoint] = []
    @State private var routeUnavailable = false
    @State private var isLoadingRoutes = false
    private var path: [PlanningPoint] { [proposal.input.origin] + proposal.stops.map(\.location) }
    @State private var showsFullMap = false
    @State private var retryGeneration = 0

    @ViewBuilder private func scheduleDecision(_ decision: PlanningScheduleDecision) -> some View {
        Text("Schedule decision").font(.headline)
            .accessibilityIdentifier("v51ScheduleDecision")
        Text("Extra travel versus fastest checked schedule: \(decision.extraTravel) min")
        ForEach(decision.checkIns) { checkIn in
            VStack(alignment: .leading) {
                Text(placeName(checkIn.id)).fontWeight(.semibold)
                Text("Check-in buffer: \(checkIn.buffer.formatted(.number.precision(.fractionLength(0 ... 1)))) min · target \(checkIn.target) min")
                if checkIn.shortfall > 0 {
                    Text("\(checkIn.shortfall.formatted(.number.precision(.fractionLength(0 ... 1)))) min below target")
                }
            }
        }
        ForEach(decision.outdoor) { outdoor in
            VStack(alignment: .leading) {
                Text(placeName(outdoor.id)).fontWeight(.semibold)
                HStack {
                    Text(outdoor.interval.start, style: .time)
                    Text("–")
                    Text(outdoor.interval.end, style: .time)
                }
                ForEach(outdoor.readings) { reading in
                    if let value = reading.value, let source = reading.source {
                        Text("\(reading.id): \(value.formatted(.number.precision(.fractionLength(0 ... 1)))) · \(source)")
                    } else {
                        Text("\(reading.id): unavailable")
                    }
                }
            }
        }
        if !decision.alternative.isEmpty {
            Text("Alternative schedule").font(.headline)
            ForEach(Array(decision.alternative.enumerated()), id: \.offset) { _, line in
                Text(line)
            }
        }
    }

    private func placeName(_ id: UUID) -> String {
        proposal.stops.first { $0.id == id }?.name ?? String(localized: "Visit")
    }

    var body: some View {
        VStack(spacing: 0) {
            routeMap(position: $previewMapPosition)
                .frame(height: 200)
                .overlay(alignment: .topTrailing) {
                    Button { showsFullMap = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .frame(width: 44, height: 44)
                            .background(.regularMaterial, in: .circle)
                    }
                    .accessibilityLabel("Expand map")
                    .accessibilityIdentifier("itineraryExpandMap")
                    .padding(8)
                }
            if routeUnavailable {
                routeFailure
            }
            ForEach(proposal.evidence.filter { $0.kind == "weather" && $0.attributionLogoURL != nil }) { evidence in
                if let url = evidence.url, let logo = evidence.attributionLogoURL, url.scheme == "https", logo.host == "weatherkit.apple.com" {
                    Link(destination: url) {
                        AsyncImage(url: logo) { image in image.resizable().scaledToFit() } placeholder: { Text("Apple Weather") }
                            .frame(width: 120, height: 28)
                            .padding(6).background(.white)
                    }
                    .accessibilityLabel("Apple Weather and data sources")
                }
            }

            if !showsTripDetails, let decision = proposal.scheduleDecision {
                DisclosureGroup("Schedule decision") {
                    VStack(alignment: .leading, spacing: 12) {
                        scheduleDecision(decision)
                    }
                }
            }

            if showsTripDetails {
                DisclosureGroup("Trip details") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Route estimates").font(.headline)
                        if !proposal.usesExperienceFlow {
                            #if DEBUG
                                Text(proposal.explanation)
                                ForEach(proposal.warnings, id: \.self) { Text($0) }
                            #else
                                Text("Travel and visit times are estimates.")
                            #endif
                        } else {
                            #if DEBUG
                                Text("Itinerary method").font(.headline)
                                switch proposal.effectiveOrderingMethod {
                                case .luna: Text("Luna")
                                case .hybridLegacy: Text("Hybrid: candidates (retired)")
                                case .hybridV4, .hybridV41, .hybridV42, .hybridV42FoundationModels:
                                    if proposal.effectiveOrderingMethod == .hybridV42FoundationModels {
                                        Text("Hybrid v4.2 · Foundation Models (experimental)")
                                    } else if proposal.effectiveOrderingMethod == .hybridV42 {
                                        Text("Hybrid v4.2 · Luna (experimental)")
                                    } else if proposal.effectiveOrderingMethod == .hybridV41 {
                                        Text("Hybrid v4.1: flexible schedules (experimental)")
                                    } else {
                                        Text("Hybrid v4: schedules (experimental)")
                                    }
                                    Text(proposal.explanation)
                                    if proposal.effectiveOrderingMethod.usesFlexibleSchedule, proposal.experiencePlan == nil {
                                        Text(proposal.input.places.allSatisfy(\.hasExplicitVisitDuration)
                                            ? "Visit durations were supplied by you."
                                            : "Travelants estimated missing visit durations on this device.")
                                    }
                                    ForEach(proposal.warnings, id: \.self) { Text($0) }
                                    ForEach(Array(Set(proposal.stops.flatMap(\.warnings))).sorted(), id: \.self) { Text($0) }
                                case .hybridV51: Text("Travelants v5.1")
                                case .hybridV52: Text("Travelants v5.2")
                                case .hybridWeather:
                                    Text("Hybrid: weather context (experimental)")
                                    Text("Activity exposure and candidate arrival times were unavailable, so heat and rain exposure were not compared.")
                                }
                            #endif
                            Text(proposal.synthetic ? "Driving times and distances are synthetic examples." : "Driving times and road distances are estimated by Apple Maps. Travel conditions can change.")
                            if proposal.hasExperienceTravelFallback {
                                Text("Legs without a driving estimate use a \(PlanProposal.defaultExperienceTravelSeconds / 60)-minute default. Their road distance is unavailable.")
                            }
                            Text("Opening hours").font(.headline)
                            Text("Regular hours do not verify opening or access on the selected date.")
                        }
                        if let decision = proposal.scheduleDecision {
                            scheduleDecision(decision)
                        }
                        if !proposal.evidence.isEmpty { Text("Sources").font(.headline) }
                        ForEach(proposal.evidence) { evidence in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(evidence.label).fontWeight(.semibold)
                                Text(evidence.summary)
                                Text("Checked \(evidence.checkedAt.formatted())")
                                    .foregroundStyle(.secondary)
                                if let url = evidence.url, url.scheme == "https" {
                                    Link("Open source", destination: url)
                                }
                                if let logo = evidence.attributionLogoURL,
                                   logo.scheme == "https", logo.host == "weatherkit.apple.com" {
                                    AsyncImage(url: logo) { image in
                                        image.resizable().scaledToFit()
                                    } placeholder: { Text("Apple Weather") }
                                        .frame(width: 120, height: 28)
                                        .padding(6)
                                        .background(.white)
                                        .accessibilityLabel("Apple Weather")
                                }
                            }
                        }
                    }
                    .font(.footnote)
                    .padding(.vertical, 8)
                }
                .font(.footnote)
                .foregroundStyle(.primary)
                .padding(12)
            }
        }
        .background(Color("ItinerarySurface"))
        .clipShape(.rect(cornerRadius: 14))
        .task(id: RouteTaskID(path: path, retry: retryGeneration)) { await loadRoutes() }
        .fullScreenCover(isPresented: $showsFullMap, onDismiss: resetExpandedMap) {
            NavigationStack {
                MapReader { proxy in
                    routeMap(position: $fullMapPosition)
                        .onMapCameraChange(frequency: .continuous) { _ in projectSelectedPin(using: proxy) }
                        .onMapCameraChange(frequency: .onEnd) { fullMapCamera = $0.camera }
                        .onChange(of: selectedStopID, initial: true) { _, _ in projectSelectedPin(using: proxy) }
                        .ignoresSafeArea(edges: .bottom)
                        .overlay { stopCardOverlay }
                }
                    .task(id: selectedStopID) {
                        if let stop = selectedStop {
                            await focusMap(on: stop)
                        } else {
                            await restoreOverview()
                        }
                    }
                    .task(id: selectedStopID) { await loadSelectedAddress() }
                    .safeAreaInset(edge: .bottom) {
                        if routeUnavailable { routeFailure.background(.regularMaterial) }
                    }
                    .navigationTitle("Itinerary map")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsFullMap = false }
                                .accessibilityIdentifier("itineraryCloseMap")
                        }
                    }
            }
        }
    }

    private var routeFailure: some View {
        RecoveryNotice(title: "Driving routes incomplete",
                       message: isLoadingRoutes ? "Checking the missing routes…" : "Some routes couldn’t be drawn. You can still see all the stops.",
                       primary: isLoadingRoutes ? nil : .init(title: "Try loading routes again") { retryGeneration += 1 })
    }

    private func routeMap(position: Binding<MapCameraPosition>) -> some View {
        Map(position: position, interactionModes: [.pan, .zoom]) {
            ForEach(routes.keys.sorted(), id: \.self) { index in
                if let route = routes[index], loadedPath == path {
                    MapPolyline(route.polyline)
                        .stroke(stopColor(at: index - 1), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
            ForEach(Array(proposal.stops.enumerated()), id: \.element.id) { index, stop in
                Annotation(stop.name, coordinate: .init(latitude: stop.location.latitude, longitude: stop.location.longitude)) {
                    Button {
                        if selectedStopID == stop.id {
                            closeStop()
                        } else {
                            selectedAddress = nil
                            selectedStopID = stop.id
                            showsFullMap = true
                        }
                    } label: {
                        let isSelected = selectedStopID == stop.id
                        pin(index)
                            .padding(3)
                            .background(isSelected ? .white.opacity(0.85) : .clear, in: .circle)
                            .scaleEffect(isSelected && !reduceMotion ? 1.18 : 1)
                            .offset(y: isSelected && !reduceMotion ? -3 : 0)
                            .animation(reduceMotion ? nil : .spring(duration: 0.34, bounce: 0.28), value: isSelected)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop \(index + 1): \(stop.name)")
                    .accessibilityAddTraits(selectedStopID == stop.id ? .isSelected : [])
                    .accessibilityIdentifier("itineraryMapStop-\(index + 1)")
                }
            }
        }
        .accessibilityLabel("Itinerary places on the map")
    }

    private var selectedStop: ScheduledPlanningStop? {
        guard let selectedStopID else { return nil }
        return proposal.stopsWithExperienceEstimates.first { $0.id == selectedStopID }
    }

    private func pin(_ index: Int) -> some View {
        Text(index + 1, format: .number)
            .font(.footnote.weight(.bold).monospacedDigit())
            .foregroundStyle(.black)
            .frame(minWidth: 30, minHeight: 30)
            .background(.white, in: .capsule)
            .overlay(Capsule().strokeBorder(stopColor(at: index), lineWidth: 3))
    }

    private func closeStop() {
        selectedStopID = nil
        selectedAddress = nil
        projectedPin = nil
    }

    private func resetExpandedMap() {
        closeStop()
        fullMapPosition = .automatic
        fullMapCamera = nil
        overviewPosition = nil
    }

    private func focusMap(on stop: ScheduledPlanningStop) async {
        guard !Task.isCancelled, selectedStopID == stop.id else { return }
        if overviewPosition == nil {
            overviewPosition = fullMapCamera.map { .camera($0) } ?? .automatic
        }
        let startingDistance = fullMapCamera?.distance ?? 1_800
        let overviewDistance = overviewPosition?.camera?.distance ?? startingDistance
        let targetDistance = max(140, min(1_100, overviewDistance * 0.26))
        let focusedDistance = min(startingDistance, targetDistance)
        let center = coordinate(for: stop)
        let heading = fullMapCamera?.heading ?? 0
        let pitch = fullMapCamera?.pitch ?? 0

        if !reduceMotion, focusedDistance < startingDistance {
            let centered = MapCamera(centerCoordinate: center, distance: startingDistance, heading: heading, pitch: pitch)
            moveCamera(to: .camera(centered), duration: 0.24)
            do { try await Task.sleep(for: .milliseconds(240)) }
            catch { return }
            guard !Task.isCancelled, selectedStopID == stop.id, !fullMapPosition.positionedByUser else { return }
        }

        let focused = MapCamera(centerCoordinate: center, distance: focusedDistance, heading: heading, pitch: pitch)
        moveCamera(to: .camera(focused), duration: 0.40)
    }

    private func restoreOverview() async {
        guard let overviewPosition else { return }
        // Let the outgoing card finish shrinking toward its pin before moving that pin.
        do { try await Task.sleep(for: .seconds(Self.cardDismissalDuration)) }
        catch { return }
        guard !Task.isCancelled, selectedStopID == nil else { return }
        moveCamera(to: overviewPosition, duration: 0.42)
        self.overviewPosition = nil
    }

    private func projectSelectedPin(using proxy: MapProxy) {
        guard let stop = selectedStop,
              let point = proxy.convert(coordinate(for: stop), to: .global) else { return }
        projectedPin = (stop.id, point)
    }

    private func moveCamera(to position: MapCameraPosition, duration: Double) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: duration)) {
            fullMapPosition = position
        }
    }

    private func coordinate(for stop: ScheduledPlanningStop) -> CLLocationCoordinate2D {
        .init(latitude: stop.location.latitude, longitude: stop.location.longitude)
    }

    private func loadSelectedAddress() async {
        guard !proposal.synthetic, let stop = selectedStop,
              let place = proposal.input.places.first(where: { $0.id == stop.id }),
              place.address == nil, let source = place.sourceID,
              let address = await MapKitTripPlaceSearch.address(for: source),
              !Task.isCancelled, selectedStopID == stop.id else { return }
        selectedAddress = address
    }

    private var stopCardOverlay: some View {
        GeometryReader { geometry in
            let stop = projectedPin?.id == selectedStopID ? selectedStop : nil
            ZStack {
                if let stop, let point = projectedPin?.point {
                    let frame = geometry.frame(in: .global)
                    let localPoint = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
                    stopCard(for: stop, at: localPoint)
                        .id(stop.id)
                        .transition(stopCardTransition(pivot: pinAnchor(at: localPoint, in: frame.size)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? .easeOut(duration: 0.14) : .spring(duration: 0.52, bounce: 0.53),
                       value: stop?.id)
        }
    }

    private func pinAnchor(at point: CGPoint, in size: CGSize) -> UnitPoint {
        guard size.width > 0, size.height > 0 else { return .center }
        return UnitPoint(x: min(1, max(0, point.x / size.width)),
                         y: min(1, max(0, point.y / size.height)))
    }

    private func stopCardTransition(pivot: UnitPoint) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(active: StopCardTilt(angle: -5, pivot: pivot),
                                 identity: StopCardTilt(angle: 0, pivot: pivot))
                .combined(with: .scale(scale: 0.76, anchor: pivot))
                .combined(with: .opacity),
            removal: .scale(scale: 0.92, anchor: pivot)
                .combined(with: .opacity)
                .animation(.easeIn(duration: Self.cardDismissalDuration))
        )
    }

    private func stopCard(for stop: ScheduledPlanningStop, at point: CGPoint) -> some View {
        let place = proposal.input.places.first { $0.id == stop.id }
        return ItineraryMapStopCard(point: point, stop: stop, zone: proposal.input.timeZone,
                                    address: selectedAddress ?? place?.address,
                                    isSynthetic: proposal.synthetic, close: closeStop,
                                    openMaps: {
                                        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate(for: stop)))
                                        item.name = stop.name
                                        item.openInMaps()
                                    })
    }

    private func stopColor(at index: Int) -> Color {
        Self.stopColors[index % Self.stopColors.count]
    }

    private func loadRoutes() async {
        let requestedPath = path
        if requestedPath != loadedPath {
            routes = [:]
            routeUnavailable = false
            loadedPath = requestedPath
        }
        guard !proposal.synthetic else { return }
        isLoadingRoutes = true
        defer { if !Task.isCancelled { isLoadingRoutes = false } }
        for index in requestedPath.indices.dropFirst() where routes[index] == nil {
            guard !Task.isCancelled else { return }
            let origin = requestedPath[index - 1], destination = requestedPath[index]
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: origin.latitude, longitude: origin.longitude)))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: destination.latitude, longitude: destination.longitude)))
            request.transportType = .automobile
            let directions = MKDirections(request: request)
            do {
                let result = try await withTaskCancellationHandler { try await directions.calculate() } onCancel: { directions.cancel() }
                guard !Task.isCancelled else { return }
                if let route = result.routes.first { routes[index] = route } else { routeUnavailable = true }
            } catch { if !Task.isCancelled { routeUnavailable = true } }
        }
        guard !Task.isCancelled else { return }
        routeUnavailable = routes.count < requestedPath.count - 1
    }
}

private nonisolated struct StopCardTilt: ViewModifier, Animatable {
    var angle: Double
    let pivot: UnitPoint

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content.rotationEffect(.degrees(angle), anchor: pivot)
    }
}

private struct ItineraryMapStopCard: View {
    let point: CGPoint
    let stop: ScheduledPlanningStop
    let zone: String
    let address: String?
    let isSynthetic: Bool
    let close: () -> Void
    let openMaps: () -> Void

    @Environment(\.locale) private var locale

    @State private var contentHeight: CGFloat = 148
    @State private var prefersAbove: Bool?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            if CGRect(origin: .zero, size: size).insetBy(dx: 0, dy: 8).contains(point) {
                let width = min(308, max(0, size.width - 24))
                let left = min(max(point.x - 68, 12), size.width - width - 12)
                let above = point.y - 32
                let below = size.height - point.y - 64
                let preferredSide = prefersAbove ?? (above >= contentHeight || above >= below)
                let preferredSpace = preferredSide ? above : below
                let otherSpace = preferredSide ? below : above
                let opensAbove = preferredSpace >= contentHeight || preferredSpace >= otherSpace ? preferredSide : !preferredSide
                let height = min(contentHeight, max(0, opensAbove ? above : below))
                let tip = min(max(point.x - left, 20), width - 20)
                let top = opensAbove ? point.y - 24 - height - 10 : point.y + 24

                VStack(spacing: 0) {
                    if !opensAbove { tail(at: tip, pointsUp: true) }
                    ScrollView {
                        content
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: height)
                    .background(.background, in: .rect(cornerRadius: 18))
                    .clipShape(.rect(cornerRadius: 18))
                    if opensAbove { tail(at: tip, pointsUp: false) }
                }
                .frame(width: width)
                .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)
                .offset(x: left, y: top)
                .onAppear {
                    if prefersAbove == nil { prefersAbove = preferredSide }
                }
            }
        }
    }

    private func tail(at offset: CGFloat, pointsUp: Bool) -> some View {
        Path { path in
            let tip: CGFloat = pointsUp ? 0 : 10
            let base: CGFloat = pointsUp ? 10 : 0
            path.move(to: CGPoint(x: offset, y: tip))
            path.addLine(to: CGPoint(x: offset - 10, y: base))
            path.addLine(to: CGPoint(x: offset + 10, y: base))
            path.closeSubpath()
        }
        .fill(.background)
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(stop.name)
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("itineraryPinTitle")
                    Text(address ?? String(localized: "Address unavailable"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("itineraryPinAddress")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .padding(9)
                        .background(.quaternary, in: .circle)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close place details")
                .accessibilityIdentifier("itineraryPinClose")
            }

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    visitSchedule
                    Spacer(minLength: 2)
                    mapsAction
                }
                VStack(alignment: .leading, spacing: 8) {
                    visitSchedule
                    mapsAction
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isSynthetic {
                Text("Sample details")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    private var visitSchedule: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(scheduledTime)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text("\((stop.visitSeconds + 59) / 60) min")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("itineraryPinSchedule")
    }

    private var mapsAction: some View {
        Button(action: openMaps) {
            Label("Open in Maps", systemImage: "arrow.up.right")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color("ItineraryAction").opacity(0.09), in: .capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color("ItineraryAction"))
        .disabled(isSynthetic)
        .accessibilityIdentifier("itineraryPinOpenMaps")
    }

    private var scheduledTime: String {
        guard let start = stop.visitStartsAt ?? stop.arrivalAt, let end = stop.departureAt else {
            return String(localized: "Not scheduled")
        }
        let from = ItineraryFormatting.time(start, zone: zone, locale: locale)
        let to = ItineraryFormatting.time(end, zone: zone, locale: locale)
        return "\(from)–\(to)"
    }
}
