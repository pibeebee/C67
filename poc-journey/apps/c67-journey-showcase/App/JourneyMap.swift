import CoreLocation
import MapKit
import SwiftUI
import TripIntegration

struct JourneyMap: View {
    let plan: IntegratedPlan?
    let geometry: BuswayGeometryCatalog?
    let roads: JourneyRoadRoutes
    var focusedLegID: String? = nil
    var interactive = false
    var allowsExpansion = true
    @State private var owner = UUID()
    @State private var showFullMap = false
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var userMovedCamera = false
    @State private var zoomActions = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var position = MapCameraPosition.region(MKCoordinateRegion(
        center: .init(latitude: -6.22, longitude: 106.81),
        span: .init(latitudeDelta: 0.08, longitudeDelta: 0.06)))
    private struct Line: Identifiable {
        var id: String
        var points: [CLLocationCoordinate2D]
        var bus: Bool
    }
    private struct Pin: Identifiable {
        var id: String
        var name: String
        var point: CLLocationCoordinate2D
        var symbol: String
    }
    private var legs: [PlannedLeg] { plan?.legs.filter { focusedLegID == nil || $0.id == focusedLegID } ?? [] }
    private var lines: [Line] {
        let busLines = legs.flatMap { leg -> [Line] in
            guard let journey = leg.busway else { return [] }
            var result: [Line] = []
            for (index, ride) in journey.rides.enumerated() {
                if let segment = try? geometry?.segment(for: ride, source: journey.source) {
                    result.append(.init(id: leg.id + "bus-\(index)", points: segment.points.map { .init(latitude: $0.latitude, longitude: $0.longitude) }, bus: true))
                }
            }
            return result
        }
        let roadLines = segments.compactMap { segment -> Line? in
            guard let points = roads.paths[segment.id] else { return nil }
            return .init(id: segment.id, points: points.map { .init(latitude: $0.latitude, longitude: $0.longitude) }, bus: !segment.walking)
        }
        return busLines + roadLines
    }
    private var segments: [JourneyRoadSegment] { JourneyRoadSegment.segments(plan: plan, focusedLegID: focusedLegID) }
    private var signature: String { segments.map(\.id).joined(separator: "|") }
    private var missingBusGeometry: Int {
        legs.reduce(0) { count, leg in
            count + (leg.busway?.rides.filter { ride in
                guard let source = leg.busway?.source else { return true }
                return (try? geometry?.segment(for: ride, source: source)) == nil
            }.count ?? 0)
        }
    }
    private var pins: [Pin] {
        guard let plan else {
            return [.init(id: "hi", name: "Bundaran HI", point: .init(latitude: -6.195, longitude: 106.823), symbol: "location.circle.fill"),
                    .init(id: "bm", name: "Blok M", point: .init(latitude: -6.2434, longitude: 106.7986), symbol: "mappin.circle.fill")]
        }
        var result: [Pin] = []
        if focusedLegID == nil {
            result = plan.stops.enumerated().map { index, stop in
                .init(id: stop.id, name: "\(index + 1). \(stop.name)", point: coordinate(stop.pin), symbol: "mappin.circle.fill")
            }
            if let pin = plan.prepared.locations.first(where: { $0.id == "origin" })?.selected {
                result.append(.init(id: "origin", name: pin.name, point: coordinate(pin), symbol: "location.circle.fill"))
            }
        }
        for leg in legs {
            if let journey = leg.busway {
                if focusedLegID != nil {
                    result += [.init(id: leg.id + "start", name: leg.from, point: coordinate(journey.access.from), symbol: "figure.walk.circle.fill"),
                               .init(id: leg.id + "end", name: leg.to, point: coordinate(journey.egress?.to ?? journey.access.to), symbol: "mappin.circle.fill")]
                }
                for (index, ride) in journey.rides.enumerated() {
                    result += [.init(id: leg.id + "board-\(index)", name: "Naik \(ride.pattern.effectiveRouteID) · " + ride.board.name, point: coordinate(ride.board.pin), symbol: "bus.fill"),
                               .init(id: leg.id + "alight-\(index)", name: "Turun · " + ride.alight.name, point: coordinate(ride.alight.pin), symbol: "bus.fill")]
                }
            }
        }
        return result
    }
    var body: some View {
        Map(position: $position, interactionModes: interactive ? .all : [.zoom]) {
            ForEach(lines) { line in
                MapPolyline(coordinates: line.points)
                    .stroke(line.bus ? JourneyTheme.blue : Color.orange, style: StrokeStyle(lineWidth: line.bus ? 5 : 4, lineCap: .round, dash: line.bus ? [] : [6, 4]))
            }
            ForEach(pins) { pin in Marker(pin.name, systemImage: pin.symbol, coordinate: pin.point).tint(JourneyTheme.blue) }
        }
        .mapControls { MapCompass(); MapScaleView() }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            if position.positionedByUser { userMovedCamera = true }
        }
        .simultaneousGesture(MagnifyGesture().onChanged { _ in userMovedCamera = true })
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 8) {
                mapButton("Perbesar peta", symbol: "plus", id: "map-zoom-in") { zoom(by: 0.5) }
                    .accessibilityValue("\(zoomActions) perubahan zoom")
                mapButton("Perkecil peta", symbol: "minus", id: "map-zoom-out") { zoom(by: 2) }
                mapButton("Tampilkan seluruh rute", symbol: "viewfinder", id: "map-fit") {
                    userMovedCamera = false; fit()
                }
                if allowsExpansion {
                    mapButton("Buka peta penuh", symbol: "arrow.up.left.and.arrow.down.right", id: "map-fullscreen") { showFullMap = true }
                }
            }.padding(10)
        }
        .overlay(alignment: .bottomLeading) {
            if plan != nil {
                VStack(alignment: .leading, spacing: 4) {
                    let loaded = segments.filter { roads.paths[$0.id] != nil }.count
                    Text("\(loaded)/\(segments.count) ruas jalan dimuat")
                        .accessibilityIdentifier((interactive ? "full-" : "") + "map-route-status")
                    Text(roads.sourceLabel + (plan?.evidenceMode == "synthetic_replay" ? " · jadwal Demo" : ""))
                    if segments.contains(where: { roads.failures[$0.id] != nil }) {
                        Text("Sebagian jalur jalan belum tersedia.")
                        Button("Coba muat jalur lagi") { roads.retry(owner, segments: segments) }
                            .accessibilityIdentifier("map-retry")
                    }
                    if missingBusGeometry > 0 { Text("\(missingBusGeometry) geometri bus belum tersedia.") }
                }.font(.caption2).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(8).padding(.trailing, 56).padding(.bottom, 20)
            }
        }
        .onAppear { roads.subscribe(owner, segments: segments) }
        .onDisappear { roads.release(owner) }
        .onChange(of: scenePhase) { _, value in
            if value == .active { roads.subscribe(owner, segments: segments) }
            else if value == .background { roads.release(owner) }
        }
        .onChange(of: signature) { _, _ in roads.subscribe(owner, segments: segments) }
        .onChange(of: focusedLegID, initial: true) { _, _ in userMovedCamera = false; fit() }
        .onChange(of: plan?.id) { _, _ in userMovedCamera = false; fit() }
        .onChange(of: lines.count) { _, _ in if !userMovedCamera { fit() } }
        .accessibilityHidden(showFullMap)
        .fullScreenCover(isPresented: $showFullMap) {
            NavigationStack {
                JourneyMap(plan: plan, geometry: geometry, roads: roads, focusedLegID: focusedLegID,
                           interactive: true, allowsExpansion: false)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Rute perjalanan").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Selesai") { showFullMap = false }.accessibilityIdentifier("close-full-map")
                        }
                    }
            }
        }
    }
    private func mapButton(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.semibold)).frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle()).contentShape(Circle())
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityIdentifier((interactive ? "full-" : "") + id)
    }
    private func zoom(by factor: Double) {
        let base = visibleRegion ?? position.region ?? MKCoordinateRegion(
            center: .init(latitude: -6.22, longitude: 106.81), span: .init(latitudeDelta: 0.08, longitudeDelta: 0.06))
        let span = MKCoordinateSpan(latitudeDelta: min(30, max(0.0002, base.span.latitudeDelta * factor)),
                                    longitudeDelta: min(30, max(0.0002, base.span.longitudeDelta * factor)))
        let region = MKCoordinateRegion(center: base.center, span: span)
        userMovedCamera = true; visibleRegion = region; zoomActions += 1
        withAnimation(.easeInOut(duration: 0.2)) { position = .region(region) }
    }
    private func coordinate(_ pin: PlacePin) -> CLLocationCoordinate2D { .init(latitude: pin.latitude, longitude: pin.longitude) }
    private func fit() {
        let points = lines.flatMap(\.points) + pins.map(\.point)
        guard let first = points.first else { return }
        var rect = MKMapRect(origin: MKMapPoint(first), size: .init(width: 1, height: 1))
        for point in points { rect = rect.union(MKMapRect(origin: MKMapPoint(point), size: .init(width: 1, height: 1))) }
        position = .rect(rect.insetBy(dx: -max(rect.width * 0.18, 600), dy: -max(rect.height * 0.18, 600)))
    }
}

enum JourneyTime {
    static func clock(_ date: Date) -> String {
        let components = TripClock.calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d.%02d", components.hour!, components.minute!)
    }
    static func minutes(_ seconds: Double) -> String { "\(Int(ceil(seconds / 60))) menit" }
}
