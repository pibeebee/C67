import SwiftUI
import MapKit
import PlaceContextEngine

struct PersonalRouteMapData {
    struct Point: Identifiable {
        let id: String
        let name: String
        let label: String
        let latitude: Double
        let longitude: Double

        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
        var mapItem: MKMapItem {
            let item = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
            item.name = name
            return item
        }
    }

    struct Leg: Identifiable {
        let id: Int
        let from: Point
        let to: Point
        let departure: Date
        let arrival: Date

        var number: Int { id + 1 }
        var color: Color { [.blue, .orange, .purple, .green, .pink, .teal, .indigo][id % 7] }
    }

    let points: [Point]
    let legs: [Leg]

    @MainActor init?(model: PersonalLabModel, trip: ContextItineraryResult) {
        guard let origin = model.origin, let initialLeg = trip.legs.first, !trip.visits.isEmpty else { return nil }
        func point(_ id: String, label: String, _ chosen: ChosenPlace) -> Point {
            .init(id: id, name: chosen.apple.name, label: label, latitude: chosen.apple.latitude, longitude: chosen.apple.longitude)
        }

        var order = [point(initialLeg.from, label: "Mulai / pulang", origin)]
        for (index, visit) in trip.visits.enumerated() {
            guard let row = model.stops.first(where: { $0.stop.place.prepared.googlePlaceID == visit.placeID }) else { return nil }
            order.append(point(visit.placeID, label: "\(index + 1). \(row.stop.place.apple.name)", row.stop.place))
        }
        let byID = Dictionary(uniqueKeysWithValues: order.map { ($0.id, $0) })
        var edges: [Leg] = []
        for (index, leg) in trip.legs.enumerated() {
            guard let from = byID[leg.from], let to = byID[leg.to] else { return nil }
            edges.append(.init(id: index, from: from, to: to, departure: leg.departure, arrival: leg.arrival))
        }
        points = order
        legs = edges
    }
}

private struct PersonalMapRoad: Identifiable {
    let leg: PersonalRouteMapData.Leg
    let line: MKPolyline
    let distance: CLLocationDistance
    let badge: CLLocationCoordinate2D

    var id: Int { leg.id }

    init(leg: PersonalRouteMapData.Leg, route: MKRoute) {
        self.leg = leg
        line = route.polyline
        distance = route.distance
        let points = line.points()
        // Use the same fraction in the direction of travel, so an out-and-back
        // sharing the same road can still show two separate badges.
        let total = (1 ..< line.pointCount).reduce(0.0) { $0 + points[$1 - 1].distance(to: points[$1]) }
        var remaining = total * 0.33
        var coordinate = points[0].coordinate
        for index in 1 ..< line.pointCount {
            let start = points[index - 1], end = points[index]
            let length = start.distance(to: end)
            guard length > 0 else { continue }
            if remaining <= length {
                let fraction = remaining / length
                coordinate = MKMapPoint(x: start.x + (end.x - start.x) * fraction,
                                        y: start.y + (end.y - start.y) * fraction).coordinate
                break
            }
            remaining -= length
        }
        badge = coordinate
    }
}

struct PersonalRouteMap: View {
    let data: PersonalRouteMapData
    @State private var roads: [PersonalMapRoad] = []
    @State private var loading = true
    @State private var request = 0
    @State private var showingMap = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showingMap = true
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Map(interactionModes: []) {
                        ForEach(data.points) { point in Marker(point.label, coordinate: point.coordinate) }
                        ForEach(roads) { road in
                            MapPolyline(road.line).stroke(road.leg.color, lineWidth: 4)
                        }
                    }
                    .frame(height: 215)
                    .clipShape(.rect(cornerRadius: 12))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    HStack {
                        Label("Jelajahi peta rute", systemImage: "map")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityIdentifier("simple-apple-map")
            .accessibilityHint("Membuka peta interaktif di dalam aplikasi.")
            PersonalMapStatus(available: roads.count, total: data.legs.count, loading: loading, retry: retry)
        }
        .sheet(isPresented: $showingMap) {
            NavigationStack {
                PersonalRouteDetail(data: data, roads: roads, loading: loading, retry: retry)
            }
        }
        .task(id: request) { await loadMissingRoads() }
    }

    private func retry() {
        loading = true
        request += 1
    }

    private func loadMissingRoads() async {
        loading = true
        for leg in data.legs where !roads.contains(where: { $0.id == leg.id }) {
            guard !Task.isCancelled else { return }
            let directions = MKDirections.Request()
            directions.source = leg.from.mapItem
            directions.destination = leg.to.mapItem
            directions.transportType = .automobile
            directions.departureDate = leg.departure
            do {
                let response = try await MKDirections(request: directions).calculate()
                guard !Task.isCancelled else { return }
                if let route = response.routes.first, route.polyline.pointCount > 1 {
                    roads.append(.init(leg: leg, route: route))
                }
            } catch {
                if Task.isCancelled { return }
            }
        }
        loading = false
    }
}

private struct PersonalMapStatus: View {
    let available: Int
    let total: Int
    let loading: Bool
    let retry: () -> Void

    var body: some View {
        if loading {
            HStack {
                ProgressView()
                Text("Memuat jalur · \(available)/\(total) ruas")
            }.font(.caption)
        } else if available == total {
            Text("Rute mobil · Apple Maps")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("simple-map-route-ready")
        } else {
            Text(available == 0 ? "Jalur belum tersedia. Titik kunjungan tetap terlihat."
                : "Jalur tersedia untuk \(available) dari \(total) ruas.")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("simple-map-route-partial")
            Button("Muat ulang jalur yang belum tersedia", action: retry).font(.caption)
        }
    }
}

private struct PersonalRouteDetail: View {
    let data: PersonalRouteMapData
    let roads: [PersonalMapRoad]
    let loading: Bool
    let retry: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedLeg: Int?

    var body: some View {
        GeometryReader { layout in
            VStack(spacing: 0) {
                routeCanvas
                    .frame(height: min(410, layout.size.height * 0.53))
                    .accessibilityIdentifier("personal-route-detail-map")

                List {
                    Section {
                        PersonalMapStatus(available: roads.count, total: data.legs.count, loading: loading, retry: retry)
                        Text("Ketuk nomor di peta atau pilih ruas di bawah untuk menyorot jalurnya.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Urutan ruas") {
                        ForEach(data.legs) { leg in legRow(leg) }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Peta itinerary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Tutup", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("personal-route-close")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Seluruh rute", systemImage: "arrow.up.left.and.arrow.down.right") { select(nil) }
                    .accessibilityIdentifier("personal-route-all")
            }
        }
        .onAppear { frame(selectedLeg) }
        .onChange(of: roads.map(\.id)) { _, _ in
            if !position.positionedByUser { frame(selectedLeg) }
        }
    }

    private var routeCanvas: some View {
        let visibleRoads = roads.filter { $0.id != selectedLeg } + roads.filter { $0.id == selectedLeg }
        return Map(position: $position) {
            ForEach(visibleRoads) { road in
                let active = selectedLeg == nil || selectedLeg == road.id
                MapPolyline(road.line)
                    .stroke(road.leg.color.opacity(active ? 1 : 0.24),
                            style: StrokeStyle(lineWidth: selectedLeg == road.id ? 7 : 4, lineCap: .round, lineJoin: .round))
                if active {
                    Annotation("Ruas \(road.leg.number)", coordinate: road.badge) {
                        Button { select(road.id) } label: {
                            Label("\(road.leg.number)", systemImage: "car.fill")
                                .font(.caption.bold())
                                .foregroundStyle(road.leg.color)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 7)
                                .background(.regularMaterial, in: Capsule())
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Sorot ruas \(road.leg.number)")
                        .accessibilityIdentifier("personal-route-badge-\(road.id)")
                    }.annotationTitles(.hidden)
                }
            }
            ForEach(data.points) { point in
                Marker(point.label, coordinate: point.coordinate)
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
    }

    private func legRow(_ leg: PersonalRouteMapData.Leg) -> some View {
        let selected = selectedLeg == leg.id
        let road = roads.first { $0.id == leg.id }
        return Button {
            select(leg.id)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text("\(leg.number)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(leg.color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(leg.from.name) → \(leg.to.name)").font(.subheadline.weight(.semibold))
                    Text("\(ContextLabModel.time(leg.departure))–\(ContextLabModel.time(leg.arrival)) WIB · Mobil")
                    if let road {
                        Text("\(road.distance / 1000, specifier: "%.1f") km di peta")
                    } else {
                        Text(loading ? "Memuat jalur…" : "Garis jalan belum tersedia")
                    }
                }
                .font(.caption)
                .foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(leg.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(selected ? leg.color.opacity(0.12) : Color.clear)
        .accessibilityIdentifier("personal-route-leg-\(leg.id)")
        .accessibilityValue(selected ? "Disorot" : "")
    }

    private func select(_ id: Int?) {
        selectedLeg = id
        withAnimation(.easeInOut(duration: 0.3)) { frame(id) }
    }

    private func frame(_ id: Int?) {
        let leg = data.legs.first { $0.id == id }
        let points = leg.map { [$0.from, $0.to] } ?? data.points
        var rect = points.reduce(MKMapRect.null) { rect, point in
            let pin = MKMapPoint(point.coordinate)
            return rect.union(.init(x: pin.x, y: pin.y, width: 1, height: 1))
        }
        for road in roads where id == nil || road.id == id {
            rect = rect.union(road.line.boundingMapRect)
        }
        guard !rect.isNull else { return }
        position = .rect(rect.insetBy(dx: -max(900, rect.width * 0.18), dy: -max(900, rect.height * 0.18)))
    }
}
