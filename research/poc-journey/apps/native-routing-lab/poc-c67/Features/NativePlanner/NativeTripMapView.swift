import MapKit
import SwiftUI

struct NativeTripMapView: View {
    let candidate: NativeTripCandidate
    let draft: NativeTripDraft
    let routes: NativeTripMapRouteStore
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedLegID: String?
    @State private var attempt = 0
    @State private var retryFailed = false
    @Environment(\.scenePhase) private var scenePhase

    private var segments: [NativeTripMapSegment] {
        candidate.legs.enumerated().map { .init(index: $0.offset, leg: $0.element) }
    }
    private var pins: [NativeTripMapPin] { NativeTripMapPin.make(candidate.legs) }

    var body: some View {
        GeometryReader { layout in
            VStack(spacing: 0) {
                NativeTripRouteCanvas(
                    segments: segments, pins: pins, routes: routes, position: $position,
                    selectedLegID: selectedLegID, onSelect: select
                )
                .frame(height: max(200, min(380, layout.size.height * 0.45)))
                .accessibilityIdentifier("itinerary-route-map")
                List {
                    NativeTripMapStatusSection(
                        legs: candidate.legs, complete: candidate.complete, routes: routes,
                        onRetry: {
                            retryFailed = true
                            attempt += 1
                        })
                    Section("Urutan ruas") {
                        ForEach(segments) { segment in
                            NativeTripMapLegRow(
                                segment: segment, state: routes.state(for: segment.leg), draft: draft,
                                selected: selectedLegID == segment.id
                            ) { select(segment.leg) }
                        }
                    }
                    NativeTripMapLegendSection()
                }
            }
        }
        .navigationTitle("Peta itinerary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Seluruh rute", systemImage: "arrow.up.left.and.arrow.down.right") {
                    select(nil)
                }
            }
        }
        .task(id: "\(attempt)-\(scenePhase)") {
            guard scenePhase == .active else {
                routes.cancel()
                return
            }
            let retry = retryFailed
            retryFailed = false
            await routes.load(candidate.legs, retryFailed: retry)
            if !Task.isCancelled, selectedLegID == nil, !position.positionedByUser { frameAll() }
        }
        .onDisappear { routes.cancel() }
    }

    private func select(_ leg: NativeTripLeg?) {
        selectedLegID = leg?.id
        routes.select(leg)
        if let leg {
            let rect =
                routes.state(for: leg).geometry?.polyline.boundingMapRect
                    ?? NativeTripMapFrame.rect([leg.from.coordinate, leg.to.coordinate].compactMap { $0 })
            if !rect.isNull { position = .rect(NativeTripMapFrame.padded(rect)) }
        } else {
            frameAll()
        }
    }

    private func frameAll() {
        var rect = NativeTripMapFrame.rect(pins.map(\.coordinate))
        for leg in candidate.legs {
            if let geometry = routes.state(for: leg).geometry {
                rect = rect.union(geometry.polyline.boundingMapRect)
            }
        }
        if !rect.isNull { position = .rect(NativeTripMapFrame.padded(rect)) }
    }
}

private struct NativeTripMapSegment: Identifiable {
    let index: Int
    let leg: NativeTripLeg
    var id: String { leg.id }
    var color: Color {
        let palette: [Color] = [.blue, .orange, .purple, .green, .red, .teal, .pink, .indigo]
        return palette[index % palette.count]
    }
}

private struct NativeTripMapPin: Identifiable {
    let id: String
    let point: NativeTripPoint
    var labels: [String]
    var legID: String?
    var coordinate: CLLocationCoordinate2D { point.coordinate! }

    static func make(_ legs: [NativeTripLeg]) -> [Self] {
        guard let origin = legs.first?.from else { return [] }
        var pins: [Self] = []
        func add(_ point: NativeTripPoint, label: String, legID: String?) {
            guard let coordinate = point.coordinate else { return }
            let id = "\(coordinate.latitude):\(coordinate.longitude)"
            if let index = pins.firstIndex(where: { $0.id == id }) {
                pins[index].labels.append(label)
            } else {
                pins.append(.init(id: id, point: point, labels: [label], legID: legID))
            }
        }
        add(origin, label: "Awal", legID: nil)
        for (index, leg) in legs.enumerated() {
            add(leg.to, label: leg.isReturn ? "Akhir" : String(index + 1), legID: leg.id)
        }
        return pins
    }
}

private enum NativeTripMapFrame {
    static func rect(_ coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        coordinates.reduce(MKMapRect.null) { value, coordinate in
            let point = MKMapPoint(coordinate)
            return value.union(.init(x: point.x, y: point.y, width: 1, height: 1))
        }
    }
    static func padded(_ rect: MKMapRect) -> MKMapRect {
        rect.insetBy(dx: -max(1500, rect.width * 0.15), dy: -max(1500, rect.height * 0.15))
    }
}

private struct NativeTripRouteCanvas: View {
    let segments: [NativeTripMapSegment]
    let pins: [NativeTripMapPin]
    let routes: NativeTripMapRouteStore
    @Binding var position: MapCameraPosition
    let selectedLegID: String?
    let onSelect: (NativeTripLeg?) -> Void

    var body: some View {
        // Read Observation state before the escaping MapContent closure so asynchronously
        // loaded geometry invalidates the canvas rather than leaving pin-only content.
        let rendered = segments.compactMap { segment -> NativeTripRenderedSegment? in
            guard let geometry = routes.state(for: segment.leg).geometry else { return nil }
            return .init(segment: segment, geometry: geometry)
        }.sorted { ($0.id == selectedLegID ? 1 : 0) < ($1.id == selectedLegID ? 1 : 0) }
        Map(position: $position) {
            // Draw the selected segment last so overlapping routes remain readable.
            ForEach(rendered) { value in
                let segment = value.segment
                let geometry = value.geometry
                let emphasized = selectedLegID == nil || selectedLegID == segment.id
                MapPolyline(geometry.polyline)
                    .stroke(
                        segment.color.opacity(emphasized ? 1 : 0.25),
                        style: StrokeStyle(
                            lineWidth: selectedLegID == segment.id ? 7 : 4,
                            lineCap: .round, lineJoin: .round,
                            dash: segment.leg.chosen?.mode == .walking ? [8, 12] : []))
                if selectedLegID == nil || selectedLegID == segment.id {
                    Annotation(
                        "Ruas \(segment.index + 1)",
                        coordinate: geometry.polyline.points()[geometry.polyline.pointCount / 2].coordinate
                    ) {
                        Button {
                            onSelect(segment.leg)
                        } label: {
                            Label(
                                "\(segment.index + 1)",
                                systemImage: segment.leg.chosen?.mode.symbol ?? "questionmark"
                            )
                            .font(.caption.bold()).padding(6)
                            .foregroundStyle(segment.color)
                            .background(.regularMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "Sorot ruas \(segment.index + 1), \(segment.leg.from.title) ke \(segment.leg.to.title)"
                        )
                    }.annotationTitles(.hidden)
                }
            }
            ForEach(pins) { pin in
                Annotation(pin.point.title, coordinate: pin.coordinate) {
                    Button {
                        onSelect(segments.first(where: { $0.id == pin.legID })?.leg)
                    } label: {
                        Text(pin.labels.joined(separator: " / "))
                            .font(.caption.bold()).padding(7)
                            .foregroundStyle(.primary)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(pin.labels.joined(separator: ", ")), \(pin.point.title)")
                }
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
    }
}

private struct NativeTripRenderedSegment: Identifiable {
    let segment: NativeTripMapSegment
    let geometry: NativeTripMapGeometry
    var id: String { segment.id }
}

private struct NativeTripMapStatusSection: View {
    let legs: [NativeTripLeg]
    let complete: Bool
    let routes: NativeTripMapRouteStore
    let onRetry: () -> Void

    private var available: Int { legs.filter { routes.state(for: $0).status == .available }.count }
    private var failed: Int { legs.filter { routes.state(for: $0).status == .failed }.count }

    var body: some View {
        Section {
            if routes.isLoading {
                ProgressView("Memuat jalur · \(available)/\(legs.count) ruas tersedia")
            } else {
                Text("\(available)/\(legs.count) ruas memiliki jalur peta")
            }
            Text("Ketuk nomor pada peta atau pilih ruas di bawah untuk menyorot jalurnya.")
                .font(.footnote).foregroundStyle(.secondary)
            if !complete {
                Text("Itinerary belum lengkap. Peta hanya memuat ruas yang telah dihitung.")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if failed > 0, routes.requestCount < routes.requestLimit {
                Button("Coba lagi jalur gagal (\(failed))", systemImage: "arrow.clockwise", action: onRetry)
                    .disabled(routes.isLoading)
            }
            Text(
                "Permintaan jalur: \(routes.requestCount)/\(routes.requestLimit) · terpisah dari permintaan ETA itinerary."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct NativeTripMapLegRow: View {
    let segment: NativeTripMapSegment
    let state: NativeTripMapLegState
    let draft: NativeTripDraft
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 12) {
                    Text("\(segment.index + 1)").font(.headline.monospacedDigit())
                        .foregroundStyle(segment.color)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(segment.leg.from.title) → \(segment.leg.to.title)").font(.subheadline.bold())
                        Label(
                            segment.leg.chosen?.mode.title ?? "Moda belum diketahui",
                            systemImage: segment.leg.chosen?.mode.symbol ?? "questionmark.circle")
                        Text("Berangkat \(draft.clock(segment.leg.departure))")
                        if let seconds = segment.leg.chosen?.seconds {
                            Text("ETA itinerary: \(seconds / 60, specifier: "%.1f") menit")
                        }
                        if let geometry = state.geometry {
                            Text(
                                "Jalur peta: \(geometry.distance / 1000, specifier: "%.1f") km · \(geometry.seconds / 60, specifier: "%.1f") menit"
                            )
                        } else {
                            Text(state.message)
                        }
                    }
                    .foregroundStyle(.primary)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(segment.color) }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("itinerary-map-leg-\(segment.index + 1)")
            .accessibilityValue(selected ? "Disorot" : "")
            if state.status == .unsupported || state.status == .failed, let chosen = segment.leg.chosen {
                Button("Periksa di Apple Maps", systemImage: "map") {
                    NativeTripAppleServices.openMaps(
                        from: segment.leg.from, to: segment.leg.to, mode: chosen.mode)
                }.font(.footnote)
            }
        }
        .listRowBackground(selected ? segment.color.opacity(0.12) : Color.clear)
    }
}

private struct NativeTripMapLegendSection: View {
    var body: some View {
        Section {
            DisclosureGroup("Legenda dan catatan") {
                Text(
                    "Warna dan nomor menunjukkan urutan ruas; warna dapat berulang setelah delapan ruas. Ikon menunjukkan moda."
                )
                Label("Mobil: garis penuh", systemImage: "car")
                Label("Jalan kaki: garis putus-putus", systemImage: "figure.walk")
                Label("Transit: ETA saja; garis tidak tersedia dari MapKit", systemImage: "tram")
                Text(
                    "Awal dan akhir atau kunjungan berulang pada koordinat yang sama digabung dalam satu pin. Nomor ruas tetap terpisah."
                )
                Text(
                    "Geometri diminta ulang sesuai moda dan jam tiap ruas. Jalur ini bukan rekaman jalur fisik yang telah dilalui. Durasi jalur dapat berbeda dari ETA itinerary; jadwal tidak diubah oleh tampilan peta."
                )
                Text(
                    "Jalur yang gagal tidak diganti dengan garis lurus. Jalur yang berhasil tetap terlihat dan disimpan sementara selama laporan ini dibuka."
                )
            }.font(.footnote)
        }
    }
}
