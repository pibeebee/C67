import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct DiaryFootprintComposer: View {
    let store: DiaryStore
    let presence: DiaryPresence
    @State private var selection: PhotosPickerItem?
    @State private var photo: Data?
    @State private var loadingPhoto = false
    @State private var photoError: String?
    @State private var uploadError: String?
    @State private var name = ""
    @State private var showsCamera = false
    @State private var saved: DiaryFootprint?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let saved {
                        Label("Jejakmu tersimpan di iPhone ini", systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(DiaryStyle.accent).accessibilityIdentifier("diary-upload-success")
                        DiaryPostcard(pin: store.pin, footprint: saved)
                        Text("Simulasi unggahan lokal · belum dikirim ke teman atau server.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Kembali ke peta kenangan") { dismiss() }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("diary-finish")
                    } else {
                        Text("Sekarang, ceritamu.").font(.system(.largeTitle, design: .serif))
                        Text("\(store.pin.creator) pernah di sini. Tinggalkan momen versimu dari tempat yang sama.")
                            .foregroundStyle(.secondary)
                        photoSelection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Namamu").font(.subheadline.weight(.semibold))
                            TextField("Nama pada kartu kenangan", text: $name)
                                .textContentType(.givenName).textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("diary-visitor-name")
                        }
                        uploadControl
                        Text("Foto boleh dari galeri atau sudah diedit. Yang diperiksa adalah lokasi perangkat saat unggah, bukan lokasi atau sudut foto.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .navigationTitle(saved == nil ? "Jejak fotomu" : "Kenangan bersama")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(saved == nil ? "Batal" : "Selesai") { presence.cancelUpload(); dismiss() }
                }
            }
            .sheet(isPresented: $showsCamera) {
                DiaryCamera { image in
                    showsCamera = false
                    do {
                        guard let data = image.jpegData(compressionQuality: 0.9) else { throw DiaryError.message("Foto belum dapat dibuka.") }
                        photo = try DiaryPhotoCodec.normalized(data)
                        photoError = nil
                    } catch { photoError = error.localizedDescription }
                } cancelled: { showsCamera = false }
                    .ignoresSafeArea()
            }
            .task(id: selection) { await loadSelectedPhoto() }
            .onDisappear { presence.cancelUpload() }
            .interactiveDismissDisabled(presence.checkingUpload)
            .onAppear {
                #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--diary-ui-testing"),
                       ProcessInfo.processInfo.arguments.contains("--diary-seed-photo") {
                        photo = DiaryPhotoCodec.fixture()
                    }
                #endif
            }
        }
        .tint(DiaryStyle.accent)
    }

    private var photoSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let photo { DiaryPhoto(data: photo).aspectRatio(0.9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14)) }
            else {
                ContentUnavailableView("Foto versimu", systemImage: "camera", description: Text("Selfie, pemandangan, atau momen kecil yang ingin kamu simpan."))
                    .frame(minHeight: 180).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
            }
            ViewThatFits(in: .horizontal) {
                HStack { galleryButton; cameraButton }
                VStack(alignment: .leading) { galleryButton; cameraButton }
            }
            .disabled(presence.checkingUpload || loadingPhoto)
            if loadingPhoto { ProgressView("Membuka foto…") }
            if let photoError { Text(photoError).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("diary-photo-error") }
        }
    }

    private var galleryButton: some View {
        PhotosPicker(selection: $selection, matching: .images) {
            Label(photo == nil ? "Pilih dari galeri" : "Ganti foto", systemImage: "photo.on.rectangle")
        }.buttonStyle(.bordered).accessibilityIdentifier("diary-photo-picker")
    }

    private var cameraButton: some View {
        Button("Ambil foto", systemImage: "camera") {
            Task {
                guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                    photoError = "Kamera tidak tersedia di perangkat ini. Pilih foto dari galeri."
                    return
                }
                let allowed = await AVCaptureDevice.requestAccess(for: .video)
                if allowed { showsCamera = true }
                else { photoError = "Izin kamera belum diberikan. Pilih foto dari galeri atau ubah izin di Pengaturan." }
            }
        }.buttonStyle(.bordered)
    }

    private var uploadControl: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let state = presence.state(for: store.pin, now: context.date)
            VStack(alignment: .leading, spacing: 12) {
                Label(state.title, systemImage: state.canAddPhoto ? "location.fill" : "location.slash")
                    .font(.subheadline.weight(.medium))
                if !state.canAddPhoto { Text(state.explanation).font(.footnote).foregroundStyle(.secondary) }
                if presence.checkingUpload { ProgressView("Memeriksa GPS terbaru…") }
                Button {
                    upload()
                } label: {
                    Label("Unggah jejak", systemImage: "arrow.up.circle.fill").frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(photo == nil || loadingPhoto || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !state.canAddPhoto || presence.checkingUpload || store.loadError != nil)
                .accessibilityIdentifier("diary-upload")
                if presence.blocked {
                    Button("Buka Pengaturan Lokasi") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                } else if !presence.running {
                    Button("Aktifkan kembali lokasi") { presence.start(pin: store.pin) }
                }
                if let uploadError {
                    Text(uploadError).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("diary-upload-error")
                }
                if presence.simulated { Text("SIMULASI LOKASI · bukan bukti kunjungan nyata").font(.caption).foregroundStyle(.orange) }
            }
        }
    }

    private func loadSelectedPhoto() async {
        guard let selection else { return }
        loadingPhoto = true
        photoError = nil
        photo = nil
        do {
            guard let data = try await selection.loadTransferable(type: Data.self) else {
                throw DiaryError.message("Foto belum tersedia. Periksa koneksi jika foto masih berada di iCloud.")
            }
            try Task.checkCancellation()
            let normalized = try DiaryPhotoCodec.normalized(data)
            try Task.checkCancellation()
            photo = normalized
            loadingPhoto = false
        } catch is CancellationError { /* A newer selection owns the loading state. */ }
        catch { photoError = error.localizedDescription; loadingPhoto = false }
    }

    private func upload() {
        guard let photo else { return }
        uploadError = nil
        let pinID = store.pin.id
        let visitor = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        presence.verifyUpload(pin: store.pin) { result in
            do {
                let (sample, pressedAt, simulated) = try result.get()
                saved = try store.addPhoto(photo, name: visitor, sample: sample, precise: presence.precise,
                                           pinID: pinID, requestedAt: pressedAt, simulated: simulated)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch { uploadError = error.localizedDescription }
        }
    }
}
