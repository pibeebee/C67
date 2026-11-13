import CoreLocation
import MapKit
import PhotosUI
import SwiftUI

struct DiaryPinSetup: View {
    let store: DiaryStore
    let presence: DiaryPresence
    @State private var draft: DiaryPin
    @State private var selection: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(store: DiaryStore, presence: DiaryPresence) {
        self.store = store
        self.presence = presence
        _draft = State(initialValue: store.pin)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Siapkan satu kenangan untuk diuji bersama teman. Pin awal berada di Monas; pindahkan ke lokasi uji kalian bila perlu.")
                        .font(.subheadline)
                }
                Section("Kenangan pembuat peta") {
                    TextField("Judul tempat", text: $draft.title).accessibilityIdentifier("diary-pin-title")
                    TextField("Nama pembuat", text: $draft.creator)
                    DatePicker("Tanggal kenangan", selection: $draft.visitedAt, displayedComponents: .date)
                    TextField("Cerita singkat", text: $draft.story, axis: .vertical).lineLimit(3 ... 6)
                    DiaryPhoto(data: draft.photo).frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 8))
                    PhotosPicker(selection: $selection, matching: .images) { Label("Pilih foto pembuat", systemImage: "photo") }
                    if loadingPhoto { ProgressView("Membuka foto…") }
                    Text("Foto pembuat boleh berasal dari perjalanan lama. Tidak perlu berada di pin saat membuat kenangan.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Lokasi percobaan") {
                    NavigationLink {
                        DiaryPinLocationPicker(coordinate: draft.coordinate) { coordinate in
                            draft.latitude = coordinate.latitude
                            draft.longitude = coordinate.longitude
                        }
                    } label: { Label("Tentukan pin di peta", systemImage: "mappin.and.ellipse") }
                    Button("Pakai lokasi saya sekarang", systemImage: "location") {
                        guard let sample = presence.latest,
                              DiaryPresencePolicy.evaluate(sample, pin: DiaryPin(latitude: sample.coordinate.latitude,
                                                                                 longitude: sample.coordinate.longitude),
                                                           precise: presence.precise).canAddPhoto else {
                            error = "Aktifkan lokasi dan tunggu posisi yang cukup akurat dahulu."
                            presence.start(pin: store.pin)
                            return
                        }
                        draft.latitude = sample.coordinate.latitude
                        draft.longitude = sample.coordinate.longitude
                    }
                    Text("\(draft.latitude, format: .number.precision(.fractionLength(6))), \(draft.longitude, format: .number.precision(.fractionLength(6)))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Stepper("Radius uji: \(Int(draft.radius)) m", value: $draft.radius, in: 50 ... 300, step: 25)
                    Text("Radius ini parameter eksperimen. Bila lokasi pin atau radius diubah, jejak lama tetap tersimpan dengan identitas pin sebelumnya dan tidak dipindahkan ke lokasi baru.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Text("PoC lokal: satu pin aktif, tanpa akun, tanpa pengiriman foto ke server. Peta dasar memerlukan koneksi atau cache sistem.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Atur pin uji").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") {
                        do { try store.savePin(draft); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                    .disabled(loadingPhoto || !draft.isValid).accessibilityIdentifier("diary-save-pin")
                }
            }
            .task(id: selection) {
                guard let selection else { return }
                loadingPhoto = true
                do {
                    guard let data = try await selection.loadTransferable(type: Data.self) else {
                        throw DiaryError.message("Foto belum dapat dibuka. Coba pilih lagi.")
                    }
                    try Task.checkCancellation()
                    let normalized = try DiaryPhotoCodec.normalized(data)
                    try Task.checkCancellation()
                    draft.photo = normalized
                    loadingPhoto = false
                } catch is CancellationError { }
                catch { self.error = error.localizedDescription; loadingPhoto = false }
            }
        }
    }
}

struct DiaryPinLocationPicker: View {
    let selected: (CLLocationCoordinate2D) -> Void
    @State private var camera: MapCameraPosition
    @State private var center: CLLocationCoordinate2D
    @Environment(\.dismiss) private var dismiss

    init(coordinate: CLLocationCoordinate2D, selected: @escaping (CLLocationCoordinate2D) -> Void) {
        self.selected = selected
        _center = State(initialValue: coordinate)
        _camera = State(initialValue: .region(.init(center: coordinate, latitudinalMeters: 900, longitudinalMeters: 900)))
    }

    var body: some View {
        Map(position: $camera).mapStyle(.standard(pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .onEnd) { center = $0.region.center }
            .overlay {
                Image(systemName: "mappin.circle.fill").font(.largeTitle).foregroundStyle(DiaryStyle.accent)
                    .background(.background, in: Circle()).allowsHitTesting(false).accessibilityHidden(true)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Text("Geser peta hingga penanda berada di tempat kenanganmu.").font(.subheadline)
                    Button("Gunakan titik ini") { selected(center); dismiss() }.buttonStyle(.borderedProminent)
                }
                .padding().frame(maxWidth: .infinity).background(.regularMaterial)
            }
            .navigationTitle("Pilih tempat").navigationBarTitleDisplayMode(.inline)
    }
}
