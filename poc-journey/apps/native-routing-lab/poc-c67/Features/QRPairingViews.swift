import SwiftUI
import CoreImage.CIFilterBuiltins
import VisionKit
import Vision
import AVFoundation

struct LeaderQRView: View {
    let app: POCController
    @State private var journey = "Jalan bersama"
    @State private var leader = ""
    @State private var confirm = false
    @State private var creatingNew = false
    var body: some View {
        NavigationStack {
            List {
                ErrorNotice(app: app)
                if app.store.state.qrMembers == nil || creatingNew {
                    Section {
                        Label("Satu QR untuk rombongan", systemImage: "qrcode").font(.title2.bold())
                        Text("Peserta scan dari iPhone-nya, isi nama, lalu menyetujui berbagi lokasi. Undangan iCloud dan nomor peserta ditangani otomatis.").foregroundStyle(.secondary)
                        TextField("Nama perjalanan", text: $journey).accessibilityIdentifier("qr-journey-name")
                        TextField("Nama tour leader", text: $leader).accessibilityIdentifier("qr-leader-name")
                        Button("Buat perjalanan QR") { confirm = true }
                            .buttonStyle(.borderedProminent).disabled(!app.canReplaceRun || journey.trimmingCharacters(in: .whitespaces).isEmpty || leader.trimmingCharacters(in: .whitespaces).isEmpty || app.pairing.working)
                            .accessibilityIdentifier("create-qr-journey")
                        if creatingNew { Button("Kembali ke perjalanan saat ini") { creatingNew = false } }
                        Text("Membuat perjalanan baru mengganti pemeriksaan, rundown dan riwayat lokal setelah konfirmasi. Roster dimulai kosong.").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text(app.store.state.qrJourneyName ?? "Perjalanan").font(.title2.bold())
                        Label(app.store.state.qrLeaderName ?? "Tour leader", systemImage: "person.crop.circle")
                        if let invite = app.pairing.invite, app.pairing.nearby.active {
                            QRCodeView(text: invite.encoded).frame(maxWidth: .infinity).accessibilityLabel("QR undangan perjalanan, berlaku lima menit")
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(context.date < invite.expiresAt ? "QR berlaku \(max(0, Int(invite.expiresAt.timeIntervalSince(context.date)))) detik lagi" : "QR kedaluwarsa").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Button("Tutup undangan QR", role: .destructive) { app.pairing.stop() }
                        } else {
                            Button("Tampilkan QR undangan", systemImage: "qrcode") { Task { await app.pairing.host() } }
                                .buttonStyle(.borderedProminent).disabled(app.pairing.working || app.store.state.activeIndex == nil)
                                .accessibilityIdentifier("show-journey-qr")
                        }
                        if app.pairing.working { ProgressView("Menyiapkan iCloud…") }
                        Text(app.pairing.nearby.status).font(.subheadline).accessibilityIdentifier("qr-pairing-status")
                    }
                    Section("Peserta terhubung · \(app.store.state.qrMembers?.count ?? 0)/20") {
                        if app.store.state.qrMembers?.isEmpty == true { Text("Belum ada peserta. Tampilkan QR, lalu minta peserta membuka Peserta → Scan QR perjalanan.").foregroundStyle(.secondary) }
                        ForEach(app.store.state.qrMembers ?? []) { member in
                            VStack(alignment: .leading, spacing: 8) {
                                Label(member.name, systemImage: "person.crop.circle.badge.checkmark")
                                Text("Terhubung · pemeriksaan kehadiran tetap oleh TL").font(.caption).foregroundStyle(.secondary)
                                Button("Putuskan akses TL", role: .destructive) { Task { await app.leaveShare(participantID: member.id) } }.font(.caption).disabled(app.busy != nil || app.pairing.nearby.active || app.leaderSharing.locked)
                            }
                        }
                    }
                }
                if app.store.state.qrMembers != nil, !creatingNew {
                    Section {
                        Button("Buat perjalanan baru") { creatingNew = true }.disabled(!app.canReplaceRun)
                        if !app.canReplaceRun { Text("Tutup QR, putuskan koneksi peserta, lalu hapus koneksi lokasi TL melalui Berbagi lokasi TL sebelum mengganti perjalanan.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Section("Saat pairing") {
                    Label("Kedua iPhone berdekatan dan app tetap terbuka", systemImage: "iphone.gen3.radiowaves.left.and.right")
                    Label("Internet, Wi-Fi/Bluetooth dan izin Jaringan Lokal", systemImage: "wifi")
                    Text("Setelah terhubung, peserta boleh menjauh. Lokasi dikirim melalui CloudKit privat, hanya ke akun TL. Tutup layar ini untuk menutup QR; koneksi lokasi yang sudah jadi tetap tersimpan.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Undang lewat QR").navigationBarTitleDisplayMode(.inline).toolbar { SheetCloseButton() }
                .alert("Buat perjalanan QR baru?", isPresented: $confirm) {
                    Button("Ganti & buat perjalanan", role: .destructive) {
                        do {
                            try app.createQRJourney(journey: journey, leader: leader)
                            creatingNew = false
                            Task { await app.pairing.host() }
                        } catch { app.error = error.localizedDescription }
                    }
                    Button("Batal", role: .cancel) {}
                } message: { Text("Riwayat pemeriksaan dan rundown lokal diganti. Peserta ditambahkan ketika pairing berhasil, tanpa otomatis ditandai hadir.") }
                .onDisappear { app.pairing.stop() }
        }
    }
}

private enum ParticipantQRModal: String, Identifiable {
    case scanner, consent
    var id: String { rawValue }
}
private struct ApprovedQRJoin {
    let invite: JourneyInvite
    let name: String
}

struct ParticipantQRView: View {
    let app: POCController
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var text = ""
    @State private var invite: JourneyInvite?
    @State private var modal: ParticipantQRModal?
    @State private var approvedJoin: ApprovedQRJoin?
    @State private var manualExpanded = false
    @FocusState private var editing: Bool
    private var joining: Bool { app.pairing.nearby.active || app.pairing.working || app.store.state.owner != nil }
    var body: some View {
        NavigationStack {
            Form {
                ErrorNotice(app: app)
                Section {
                    Label("Gabung perjalanan", systemImage: "qrcode.viewfinder").font(.title2.bold())
                    TextField("Nama Anda", text: $name).textContentType(.name).focused($editing).disabled(joining).accessibilityIdentifier("qr-participant-name")
                    Button("Buka kamera & scan QR", systemImage: "camera") { modal = .scanner }.disabled(joining || !app.canReplaceRun)
                    DisclosureGroup("Masukkan isi QR secara manual", isExpanded: $manualExpanded) {
                        TextField("c67://join/…", text: $text, axis: .vertical).lineLimit(3 ... 5).focused($editing).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("qr-manual-input")
                        Button("Baca undangan") { read(text) }.disabled(joining).accessibilityIdentifier("read-qr-invite")
                    }
                }
                if let invite, !joining, !app.pairing.completed {
                    Section("Periksa sebelum bergabung") {
                        Text(invite.journey).font(.headline)
                        Label("Tour leader: \(invite.leader)", systemImage: "person.crop.circle")
                        Text("Pastikan QR ini ditampilkan langsung oleh TL Anda. Nama adalah label perjalanan, bukan verifikasi identitas resmi.").font(.caption).foregroundStyle(.secondary)
                        Button("Gabung perjalanan") { editing = false; modal = .consent }
                            .buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 40 || joining || !app.canReplaceRun)
                            .accessibilityIdentifier("join-qr-journey")
                    }
                }
                if joining || app.pairing.completed {
                    Section("Status koneksi") {
                        Text(app.pairing.nearby.status).accessibilityIdentifier("qr-guest-status")
                        Text(app.sharingStatus).font(.caption)
                        if app.sensor.running { Label("Sesi lokasi dimulai", systemImage: "location.fill").foregroundStyle(TourStyle.accent) }
                        if app.store.state.owner != nil {
                            Button("Hentikan / cleanup koneksi", role: .destructive) { Task { await app.stopSharing() } }
                        }
                        if app.pairing.completed { Button("Kembali ke peserta") { dismiss() } }
                    }
                }
                Section {
                    Text("Dekatkan iPhone ke TL dan tetap di layar ini sampai terhubung. Kedua perangkat perlu internet, akun iCloud berbeda, serta izin Jaringan Lokal. QR berlaku lima menit.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Scan perjalanan").navigationBarTitleDisplayMode(.inline).toolbar { SheetCloseButton() }
                .sheet(item: $modal, onDismiss: beginApprovedJoin) { destination in
                    switch destination {
                    case .scanner: QRScannerScreen { value in modal = nil; read(value) }
                    case .consent:
                        if let invite {
                            ParticipantConsentSheet(app: app, receiver: invite.leader, title: "Persetujuan lokasi", actionTitle: "Setuju & gabung",
                                                    context: "\(invite.journey). Bergabung mengganti run, rundown dan riwayat lokal pada iPhone ini. Lokasi mulai dikirim setelah pairing berhasil.",
                                                    canConfirm: invite.expiresAt > .now && app.canReplaceRun) {
                                approvedJoin = ApprovedQRJoin(invite: invite, name: name)
                                modal = nil
                            }
                        }
                    }
                }
                .onChange(of: app.sensor.running) { _, running in if running { dismiss() } }
                .onDisappear { app.pairing.stop() }
        }
    }
    private func read(_ text: String) {
        invite = nil; approvedJoin = nil
        app.attempt { invite = try JourneyInvite.decode(text); editing = false; manualExpanded = false }
    }
    private func beginApprovedJoin() {
        guard let approved = approvedJoin else { return }
        approvedJoin = nil
        Task { await app.pairing.join(approved.invite, name: approved.name, consent: true) }
    }
}

struct QRCodeView: View {
    let text: String
    private var image: UIImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(text.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 5, y: 5)), from: output.extent.applying(CGAffineTransform(scaleX: 5, y: 5))) else { return nil }
        return UIImage(cgImage: cg)
    }
    var body: some View {
        if let image { Image(uiImage: image).interpolation(.none).resizable().scaledToFit().padding(16).background(.white).clipShape(RoundedRectangle(cornerRadius: 16)).frame(maxWidth: 340).accessibilityIdentifier("journey-qr-image") }
    }
}
struct ScannerPresentation: Identifiable { let id = UUID() }
struct QRScannerScreen: View {
    var found: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var allowed = false
    @State private var message = "Menyiapkan kamera…"
    var body: some View {
        NavigationStack {
            Group {
                if allowed { CameraQRScanner(found: found, failed: { message = $0; allowed = false }) }
                else { ContentUnavailableView("Kamera QR", systemImage: "qrcode.viewfinder", description: Text(message)) }
            }.navigationTitle("Scan QR tour leader").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } } }
                .task {
                    guard DataScannerViewController.isSupported else { message = "Scanner tidak tersedia di perangkat ini. Gunakan isi QR manual untuk pengujian atau iPhone fisik yang mendukung."; return }
                    let granted = await AVCaptureDevice.requestAccess(for: .video)
                    allowed = granted && DataScannerViewController.isAvailable
                    if !allowed { message = "Izinkan Kamera di Pengaturan, lalu coba lagi. Isi QR manual tetap tersedia." }
                }
        }
    }
}
struct CameraQRScanner: UIViewControllerRepresentable {
    var found: (String) -> Void
    var failed: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(found: found) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        do { try scanner.startScanning() } catch { Task { @MainActor in failed("Kamera belum dapat dimulai. Tutup scanner dan coba lagi.") } }
        return scanner
    }
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) { uiViewController.stopScanning() }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        var handled = false
        init(found: @escaping (String) -> Void) { self.found = found }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) { consume(addedItems, scanner: dataScanner) }
        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) { consume(updatedItems, scanner: dataScanner) }
        private func consume(_ items: [RecognizedItem], scanner: DataScannerViewController) {
            guard !handled else { return }
            for case .barcode(let barcode) in items { if let value = barcode.payloadStringValue { handled = true; scanner.stopScanning(); found(value); return } }
        }
    }
}
