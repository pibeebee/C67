import SwiftUI

private enum ParticipantSheet: String, Identifiable {
    case join, resume
    var id: String { rawValue }
}

struct ParticipantLabView: View {
    let app: POCController
    @State private var sheet: ParticipantSheet?
    @State private var map: ScannerPresentation?
    private var hasConnection: Bool { app.store.state.owner != nil || app.store.state.leaderBinding != nil }
    private var receiver: String { app.store.state.joinedQR?.leader ?? app.recipient }
    var body: some View {
        NavigationStack {
            List {
                ErrorNotice(app: app)
                Section {
                    ModeBadge(mode: app.store.state.mode)
                    if let joined = app.store.state.joinedQR {
                        Text(joined.journey).font(.title2.bold())
                        Text("\(joined.participantName) · Tour leader: \(joined.leader)").foregroundStyle(.secondary)
                    } else {
                        Label("Perjalanan Anda", systemImage: "person.crop.circle").font(.title2.bold())
                    }
                    if hasConnection || app.sensor.running {
                        Label(app.sensor.running ? "Sesi lokasi dimulai" : "Berbagi lokasi belum aktif", systemImage: app.sensor.running ? "location.fill" : "location.slash")
                            .font(.headline).foregroundStyle(TourStyle.accent)
                        Text(app.sharingStatus).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("sharing-status")
                        if hasConnection, app.store.state.joinedQR == nil { Text("Penerima: \(receiver)").font(.caption).foregroundStyle(.secondary) }
                    } else {
                        Text("Scan QR dari tour leader untuk bergabung. Persetujuan berbagi lokasi ditampilkan sebelum tersambung.").foregroundStyle(.secondary)
                        Button { sheet = .join } label: {
                            Label("Scan QR perjalanan", systemImage: "qrcode.viewfinder").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 7)
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("open-participant-qr").disabled(!app.canReplaceRun)
                        if !app.canReplaceRun { Text("Selesaikan koneksi yang masih tersimpan di perangkat ini sebelum bergabung ke perjalanan lain.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if app.store.state.joinedQR != nil || app.store.state.mode == .simulation {
                    Section {
                        NavigationLink { ItineraryView(app: app, audience: .participant) } label: { Label("Rundown perjalanan", systemImage: "calendar") }.accessibilityIdentifier("open-participant-itinerary")
                        Button("Lihat posisi tour leader", systemImage: "map") { map = ScannerPresentation() }.accessibilityIdentifier("open-participant-map")
                        Text(app.store.state.leaderBinding == nil && app.store.state.mode == .real ? "Koneksi lama: scan ulang QR versi terbaru untuk menerima lokasi TL." : "Lokasi muncul saat TL membagikannya.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if hasConnection || app.sensor.running {
                    Section("Berbagi lokasi") {
                        if hasConnection, !app.sensor.running {
                            Button("Lanjutkan berbagi lokasi", systemImage: "location") { sheet = .resume }
                                .accessibilityIdentifier("resume-sharing").disabled(app.busy != nil || app.pairing.hasPendingCloudWork || app.uploading)
                            Text("Tinjau penerima, durasi dan persetujuan sebelum memulai sesi baru.").font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Hentikan berbagi & putuskan koneksi", systemImage: "stop.circle.fill", role: .destructive) { Task { await app.stopSharing() } }
                            .font(.headline).accessibilityIdentifier("stop-sharing")
                        Text("Pengiriman lokal langsung berhenti. Saat offline, pencabutan akses cloud diselesaikan setelah kembali online.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.listStyle(.insetGrouped).scrollContentBackground(.hidden).background(TourStyle.canvas)
                .navigationTitle("Peserta")
                .fullScreenCover(item: $map) { _ in GroupMapScreen(app: app, audience: .participant) }
                .sheet(item: $sheet) { destination in
                    switch destination {
                    case .join: ParticipantQRView(app: app)
                    case .resume: ResumeSharingView(app: app)
                    }
                }
        }
    }
}

// The diagnostic/manual pairing form retains its explicit consent switch.
struct SharingPreferencesFields: View {
    let app: POCController
    @Binding var consent: Bool
    let receiver: String
    var disabled = false
    var consentIdentifier = "sharing-consent"
    var body: some View {
        SharingOptionsFields(app: app, disabled: disabled)
        Toggle("Saya setuju membagikan lokasi kepada \(receiver) selama durasi ini", isOn: $consent)
            .disabled(disabled).accessibilityIdentifier(consentIdentifier)
    }
}

private struct SharingOptionsFields: View {
    let app: POCController
    var disabled = false
    var body: some View {
        @Bindable var app = app
        Stepper("Berbagi selama \(Int(app.durationMinutes)) menit", value: $app.durationMinutes, in: 5 ... 120, step: 5)
            .disabled(disabled).accessibilityIdentifier("participant-sharing-duration")
        Toggle("Tetap berbagi saat layar terkunci", isOn: $app.backgroundEnabled)
            .disabled(disabled).accessibilityIdentifier("participant-sharing-background")
    }
}

// A deliberate confirmation button replaces an inline consent switch in the participant flow.
struct ParticipantConsentSheet: View {
    let app: POCController
    let receiver: String
    let title: String
    let actionTitle: String
    let context: String
    var canConfirm = true
    var checking = false
    var confirmIdentifier = "confirm-participant-sharing"
    var retry: (() -> Void)?
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                ErrorNotice(app: app)
                Section("Penerima lokasi") {
                    Label(receiver, systemImage: "person.crop.circle")
                    Text(context).font(.subheadline).foregroundStyle(.secondary)
                    if checking { ProgressView("Memeriksa koneksi privat…") }
                }
                Section("Pilihan berbagi") {
                    SharingOptionsFields(app: app, disabled: checking || app.busy != nil)
                }
                Section {
                    Text("Dengan memilih \"\(actionTitle)\", Anda menyetujui pengiriman lokasi kepada \(receiver) selama \(Int(app.durationMinutes)) menit\(app.backgroundEnabled ? ", termasuk saat layar terkunci" : ", selama aplikasi digunakan"). Izin lokasi iOS tetap diperlukan. Anda dapat berhenti kapan saja dari halaman Peserta.")
                        .font(.subheadline).accessibilityIdentifier("participant-consent-summary")
                    Button(actionTitle, action: confirm).buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(confirmIdentifier)
                        .disabled(!canConfirm || checking || app.busy != nil || app.sensor.running || app.uploading)
                    if let retry, !checking, !canConfirm, app.busy == nil { Button("Periksa ulang koneksi", action: retry) }
                }
            }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() }.accessibilityIdentifier("cancel-participant-consent") } }
        }
    }
}

struct ResumeSharingView: View {
    let app: POCController
    @Environment(\.dismiss) private var dismiss
    @State private var connectionChecked = false
    @State private var checking = true
    private var receiver: String { app.store.state.joinedQR?.leader ?? app.recipient }
    var body: some View {
        ParticipantConsentSheet(app: app, receiver: receiver, title: "Lanjutkan berbagi",
                                actionTitle: "Setuju & mulai berbagi",
                                context: connectionChecked ? "Koneksi privat dikonfirmasi. Mulai sesi baru hanya jika Anda siap berbagi lokasi kembali." : "Koneksi privat tersimpan perlu dikonfirmasi sebelum sesi baru dimulai.",
                                canConfirm: connectionChecked && app.recipientAccepted && app.store.state.owner != nil,
                                checking: checking, confirmIdentifier: "start-sharing",
                                retry: { Task { await checkConnection() } },
                                confirm: { Task { await app.startSharing(consent: true) } })
            .task { await checkConnection() }
            .onChange(of: app.sensor.running) { _, running in if running { dismiss() } }
    }
    private func checkConnection() async {
        connectionChecked = false; checking = true
        let reference = app.store.state.owner
        app.error = nil
        await app.checkRecipient()
        connectionChecked = app.error == nil && app.recipientAccepted && reference != nil && app.store.state.owner == reference
        checking = false
    }
}
