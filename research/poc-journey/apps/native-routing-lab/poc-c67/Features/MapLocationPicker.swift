import MapKit
import SwiftUI
import Observation

private struct PlaceResult: Identifiable {
    let id = UUID()
    let place: TourPlace
}
@MainActor @Observable private final class PlaceSearch {
    var query = ""
    private(set) var results: [PlaceResult] = []
    private(set) var searching = false
    private(set) var message: String?
    private var request: MKLocalSearch?
    private var generation = UUID()
    func search(region: MKCoordinateRegion?) async {
        cancel(); let token = generation
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { message = "Ketik nama tempat atau alamat."; return }
        searching = true
        let input = MKLocalSearch.Request(); input.naturalLanguageQuery = text
        if let region { input.region = region }
        let request = MKLocalSearch(request: input); self.request = request
        do {
            let response = try await request.start()
            guard generation == token, !Task.isCancelled else { return }
            results = response.mapItems.prefix(8).compactMap { item in
                let place = TourPlace(name: String((item.name ?? text).prefix(120)), latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
                return place.valid ? PlaceResult(place: place) : nil
            }
            message = results.isEmpty ? "Tempat tidak ditemukan. Anda tetap bisa memilih titik pada peta." : nil
        } catch { if generation == token, !Task.isCancelled { message = "Pencarian belum berhasil. Coba lagi atau pilih titik pada peta." } }
        if generation == token { searching = false; self.request = nil }
    }
    func cancel() { generation = UUID(); request?.cancel(); request = nil; searching = false; results = [] }
}

struct MapLocationPicker: View {
    let initial: TourPlace?
    let runID: UUID
    let allowGPS: Bool
    let save: (TourPlace) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var camera: MapCameraPosition = .automatic
    @State private var picked: TourPlace?
    @State private var name = ""
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var sensor = LocationService()
    @State private var search = PlaceSearch()
    @State private var searchTask: Task<Void, Never>?
    private var validSelection: TourPlace? {
        guard var picked else { return nil }
        picked.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return picked.valid ? picked : nil
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                if search.searching { ProgressView("Mencari tempat…").padding(8) }
                if let message = search.message { Text(message).font(.caption).padding(8) }
                if !search.results.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(search.results) { result in
                                Button { choose(result.place); search.cancel() } label: {
                                    Label(result.place.name, systemImage: "mappin.and.ellipse").frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                }
                            }
                        }
                    }.frame(maxHeight: 180)
                }
                MapReader { proxy in
                    Map(position: $camera, interactionModes: .all) {
                        if let picked { Marker(name.isEmpty ? "Titik pilihan" : name, coordinate: picked.coordinate).tint(.orange) }
                    }
                    .mapControls { MapCompass(); MapScaleView() }
                    .onMapCameraChange(frequency: .onEnd) { context in visibleRegion = context.region }
                    .onTapGesture { point in
                        if let coordinate = proxy.convert(point, from: .local) { pick(coordinate) }
                    }
                    .overlay { Image(systemName: "plus").font(.title2.bold()).foregroundStyle(.orange).allowsHitTesting(false).accessibilityHidden(true) }
                    .accessibilityIdentifier("location-picker-map")
                    .safeAreaInset(edge: .bottom, spacing: 0) { selectionPanel }
                }
            }
            .navigationTitle("Pilih lokasi").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gunakan lokasi") { if let place = validSelection { save(place); dismiss() } }
                        .disabled(validSelection == nil).accessibilityIdentifier("use-picked-location")
                }
            }
            .onAppear {
                picked = initial; name = initial?.name ?? ""
                if let initial { focus(initial.coordinate) }
                updateSensor()
            }
            .onChange(of: phase) { _, _ in updateSensor() }
            .onDisappear { sensor.stop(); searchTask?.cancel(); search.cancel() }
        }
    }
    private var searchBar: some View {
        HStack {
            TextField("Cari tempat atau alamat", text: $search.query).submitLabel(.search).autocorrectionDisabled()
                .accessibilityIdentifier("place-search-query").onSubmit { beginSearch() }
            Button("Cari", systemImage: "magnifyingglass") { beginSearch() }.disabled(search.searching || search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("place-search-submit")
        }.padding()
    }
    private var selectionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ketuk peta atau geser lalu pilih titik tengah.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Pilih titik tengah", systemImage: "plus.circle") { if let center = visibleRegion?.center { pick(center) } }
                    .disabled(visibleRegion == nil).accessibilityIdentifier("pick-map-center")
                Spacer()
                Button("Lokasi saya", systemImage: "location") {
                    if let sample = sensor.latest { focus(CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude)) }
                }.disabled(!sensor.running || sensor.latest == nil).accessibilityIdentifier("picker-my-location")
            }
            TextField("Nama lokasi, misalnya Parkir B", text: $name).textFieldStyle(.roundedBorder).accessibilityIdentifier("picked-place-name")
            if let picked { Text(String(format: "%.5f, %.5f", picked.latitude, picked.longitude)).font(.caption.monospaced()).foregroundStyle(.secondary) }
            else { Text("Belum ada titik dipilih").font(.caption).foregroundStyle(.secondary) }
        }.padding().background(.regularMaterial)
    }
    private func pick(_ coordinate: CLLocationCoordinate2D) {
        picked = TourPlace(name: name.isEmpty ? "Titik pilihan" : name, latitude: coordinate.latitude, longitude: coordinate.longitude)
        if name.isEmpty { name = "Titik pilihan" }
    }
    private func choose(_ place: TourPlace) { picked = place; name = place.name; focus(place.coordinate) }
    private func focus(_ coordinate: CLLocationCoordinate2D) { camera = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200)) }
    private func beginSearch() { searchTask?.cancel(); searchTask = Task { await search.search(region: visibleRegion) } }
    private func updateSensor() {
        guard allowGPS, phase != .background else { sensor.stop(); return }
        guard !sensor.running else { return }
        sensor.start(runID: runID, epoch: UUID(), expiresAt: .now.addingTimeInterval(7200), background: false)
    }
}

extension TourPlace {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
