import CoreLocation
import MapKit
import SwiftUI

struct NativeTripPinPicker: View {
    let point: NativeTripPoint
    let jakartaOnly: Bool
    let onSelect: (NativeTripPoint) -> Void
    @State private var camera: MapCameraPosition
    @State private var center: CLLocationCoordinate2D
    @State private var hasSelectedArea: Bool

    init(
        point: NativeTripPoint, jakartaOnly: Bool = false, onSelect: @escaping (NativeTripPoint) -> Void
    ) {
        self.point = point
        self.jakartaOnly = jakartaOnly
        self.onSelect = onSelect
        let hint = jakartaOnly ? NativeTripJakarta.region : point.searchRegion
        let coordinate =
            (jakartaOnly
                && point.coordinate.map {
                    !NativeTripJakarta.contains(latitude: $0.latitude, longitude: $0.longitude)
                } == true ? nil : point.coordinate)
            ?? hint.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
        let initial = coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        _center = State(initialValue: initial)
        _hasSelectedArea = State(initialValue: coordinate != nil)
        let region =
            coordinate.map {
                MKCoordinateRegion(
                    center: $0, latitudinalMeters: point.coordinate == nil ? 10_000 : 1000,
                    longitudinalMeters: point.coordinate == nil ? 10_000 : 1000)
            }
            ?? MKCoordinateRegion(
                center: initial, span: .init(latitudeDelta: 150, longitudeDelta: 300))
        _camera = State(initialValue: .region(region))
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $camera)
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .onMapCameraChange(frequency: .onEnd) { context in center = context.region.center }
                .onTapGesture { position in
                    guard let coordinate = proxy.convert(position, from: .local) else { return }
                    center = coordinate
                    hasSelectedArea = true
                    camera = .region(
                        MKCoordinateRegion(
                            center: coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000))
                }
                .overlay {
                    Image(systemName: "plus.circle.fill").font(.title).foregroundStyle(.primary)
                        .allowsHitTesting(false)
                }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text(point.title).font(.headline)
                Text(
                    "Ketuk area tujuan pada peta, lalu geser dan perbesar sampai tanda tengah berada di lokasi yang Anda maksud. Area awal bukan lokasi yang sudah ditemukan."
                ).font(.footnote)
                if hasSelectedArea {
                    Text("\(center.latitude, specifier: "%.6f"), \(center.longitude, specifier: "%.6f")")
                        .font(.caption.monospaced())
                }
                if jakartaOnly,
                   !NativeTripJakarta.contains(latitude: center.latitude, longitude: center.longitude)
                {
                    Text("Titik di luar cakupan Jakarta pada PoC. Geser pin ke lokasi yang sesuai.")
                        .font(.footnote).foregroundStyle(.red)
                }
                Button("Gunakan titik yang saya pilih") {
                    var selected = point
                    selected.latitude = center.latitude
                    selected.longitude = center.longitude
                    selected.resolvedName = "Pin manual · \(point.title)"
                    selected.address = "Koordinat dipilih pengguna, bukan hasil pencarian nama."
                    selected.selectionSource = "Pin manual pengguna"
                    onSelect(selected)
                }.buttonStyle(.borderedProminent)
                    .disabled(
                        !hasSelectedArea || !CLLocationCoordinate2DIsValid(center)
                            || (jakartaOnly
                                && !NativeTripJakarta.contains(
                                    latitude: center.latitude, longitude: center.longitude))
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding().background(.regularMaterial)
        }
        .navigationTitle("Pilih pin manual")
        .navigationBarTitleDisplayMode(.inline)
    }
}
