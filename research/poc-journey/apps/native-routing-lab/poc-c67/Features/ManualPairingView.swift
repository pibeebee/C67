import CloudKit
import SwiftUI

enum ManualPairingRole: String, CaseIterable { case participant = "Peserta", leader = "Tour leader" }
private struct ManualSharePresentation: Identifiable { let id = UUID(); let share: CKShare }

struct ManualPairingView: View {
    let app: POCController
    var initialRole: ManualPairingRole = .participant
    @State private var role: ManualPairingRole = .participant
    @State private var runText = ""
    @State private var participantID = "P01"
    @State private var confirmJoin = false
    @State private var sharing: ManualSharePresentation?
    @State private var copied = false
    @State private var url = ""
    @State private var mode: RunMode = .real
    @State private var reset = false
    var body: some View {
        NavigationStack {
            Form {
                ErrorNotice(app: app)
                Section {
                    Text("Alat pengujian untuk alur manual POC lama. Onboarding utama berada pada Rombongan/Peserta melalui QR.").font(.caption).foregroundStyle(.secondary)
                    Picker("Peran perangkat", selection: $role) { ForEach(ManualPairingRole.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                }
                if (app.store.state.qrMembers != nil || app.store.state.joinedQR != nil), app.incoming == nil {
                    Section {
                        Text("Perjalanan QR sedang digunakan. Kelola koneksi melalui Rombongan atau Peserta; alat pairing fixture hanya digunakan pada run manual.").foregroundStyle(.secondary)
                    }
                } else if role == .participant {
                    Section {
                        Text("Run aktif: \(app.store.state.runID.uuidString)").font(.caption.monospaced()).textSelection(.enabled)
                        TextField("Tempel Run ID dari TL", text: $runText).textInputAutocapitalization(.characters).autocorrectionDisabled().accessibilityIdentifier("join-run-id")
                        Button("Gunakan perjalanan TL…", systemImage: "link") { confirmJoin = true }.disabled(app.sensor.running || app.busy != nil || runText.isEmpty)
                        Picker("Identitas peserta uji", selection: $participantID) { ForEach(Participant.fixture) { Text("\($0.id) · \($0.name)").tag($0.id) } }.disabled(app.store.state.owner != nil)
                    } header: { Text("Run & identitas fixture") }
                    Section {
                        Button(app.store.state.owner == nil ? "Siapkan undangan lokasi" : "Muat ulang undangan tersimpan", systemImage: "person.badge.plus") {
                            Task { await app.prepare(participantID: participantID) }
                        }.disabled(app.busy != nil || app.sensor.running || app.store.state.mode == .simulation)
                        if let share = app.cloudShare {
                            Button("Undang atau kelola tour leader", systemImage: "square.and.arrow.up") { sharing = ManualSharePresentation(share: share) }.disabled(app.sensor.running || app.busy != nil)
                        }
                        Button("Periksa apakah TL sudah menerima", systemImage: "arrow.clockwise") { Task { await app.checkRecipient() } }
                            .disabled(app.store.state.owner == nil || app.busy != nil || app.sensor.running)
                        Label(app.recipientAccepted ? "TL sudah menerima" : "Menunggu konfirmasi TL", systemImage: app.recipientAccepted ? "checkmark.circle.fill" : "clock")
                            .foregroundStyle(app.recipientAccepted ? TourStyle.accent : .secondary)
                        Text("Penerima: \(app.recipient)").font(.subheadline)
                        Text("Undang satu akun TL. Akses hanya baca; TL tidak dapat memulai GPS di iPhone Anda.").font(.caption).foregroundStyle(.secondary)
                    } header: { Text("Undangan peserta") }

                } else {
                    Section {
                        ModeBadge(mode: app.store.state.mode)
                        Text(app.store.state.runID.uuidString).font(.caption.monospaced()).textSelection(.enabled).accessibilityIdentifier("run-id")
                        Button(copied ? "Run ID disalin" : "Salin Run ID", systemImage: copied ? "checkmark" : "doc.on.doc") { UIPasteboard.general.string = app.store.state.runID.uuidString; copied = true }
                        ShareLink(item: app.store.state.runID.uuidString) { Label("Bagikan Run ID", systemImage: "square.and.arrow.up") }
                    } header: { Text("Run TL") }
                    if app.store.state.mode == .real {
                        Section {
                            if let ref = app.store.state.binding {
                                Label("\(ref.participantID) terhubung", systemImage: "checkmark.circle.fill").foregroundStyle(TourStyle.accent)
                                Text("Akses TL: read-only. Minta peserta menekan Mulai berbagi di iPhone-nya.").font(.caption)
                            } else { Text("Buka tautan undangan yang dikirim peserta. Setelah diterima, hubungkan ke nomor peserta yang sesuai.") }
                            if let incoming = app.incoming {
                                Text("Peserta \(incoming.participantID) · \(incoming.runID.uuidString)").font(.caption.monospaced())
                                if incoming.runID != app.store.state.runID { Label("Run ID berbeda. Binding belum dapat disimpan.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                                Button("Hubungkan ke \(incoming.participantID)") { app.attempt { try app.bindIncoming() }; Task { await app.fetch() } }
                                    .buttonStyle(.borderedProminent).disabled(incoming.runID != app.store.state.runID)
                            }
                            DisclosureGroup("Terima tautan secara manual") {
                                TextField("URL iCloud share", text: $url).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                                Button("Terima URL undangan") { Task { await app.acceptURL(url) } }.disabled(app.busy != nil || url.isEmpty)
                            }
                            if app.store.state.binding != nil || app.incoming != nil {
                                Button("Putuskan share / keluar dari undangan", role: .destructive) { Task { await app.leaveShare() } }.disabled(app.busy != nil)
                            }
                        } header: { Text("Undangan lokasi") }
                    }

                }
                Section("Reset fixture pengujian") {
                    Picker("Mode", selection: $mode) { ForEach(RunMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    Button("Reset ke roster fixture…") { reset = true }.disabled(!app.canReplaceRun).accessibilityIdentifier("reset-fixture")
                    if !app.canReplaceRun { Text("Hentikan GPS, cleanup share, dan putuskan undangan/binding sebelum mengganti run.").font(.caption).foregroundStyle(.orange) }
                    Text("Run manual memakai empat peserta uji. Perjalanan QR memakai roster dinamis hingga 20 peserta; batas ini belum diuji pada 20 iPhone.").font(.caption).foregroundStyle(.secondary)
                }

            }.navigationTitle("Pairing manual").navigationBarTitleDisplayMode(.inline).toolbar { SheetCloseButton() }
                .onAppear { role = initialRole; mode = app.store.state.mode; participantID = app.store.state.owner?.participantID ?? "P01" }
                .onChange(of: app.store.state.owner) { _, ref in if let ref { participantID = ref.participantID } }
                .onChange(of: app.incoming) { _, ref in if ref != nil { role = .leader } }
                .alert("Ganti dengan perjalanan TL?", isPresented: $confirmJoin) {
                    Button("Gunakan run TL", role: .destructive) { app.attempt { try app.joinRun(runText) } }
                    Button("Batal", role: .cancel) {}
                } message: { Text("Pemeriksaan dan riwayat lokal diganti. Cleanup koneksi sebelumnya terlebih dahulu.") }
                .alert("Reset ke roster fixture?", isPresented: $reset) {
                    Button("Ganti run lokal", role: .destructive) { app.attempt { try app.resetRun(mode: mode) }; copied = false }
                    Button("Batal", role: .cancel) {}
                } message: { Text("Khusus pengujian: mengganti seluruh run/riwayat lokal dengan empat peserta fixture. Membuat perjalanan QR tetap melalui Rombongan.") }
                .sheet(item: $sharing) { presentation in
                    CloudSharingView(share: presentation.share, container: app.cloud.sharingContainer,
                                     changed: { Task { await app.checkRecipient() } }, failure: { app.error = $0.localizedDescription })
                }
        }
    }
}

struct SensorLabView: View {
    let app: POCController
    var body: some View {
        @Bindable var app = app
        Form {
            ErrorNotice(app: app)
            Section("Akun & sensor") {
                Text(app.cloud.account)
                Button("Periksa akun iCloud") { Task { await app.perform("Periksa iCloud") { try await app.cloud.checkAccount() } } }.disabled(app.busy != nil)
                Stepper("Durasi uji lokal \(Int(app.durationMinutes)) menit", value: $app.durationMinutes, in: 5 ... 120, step: 5).disabled(app.sensor.running)
                Toggle("Uji saat layar terkunci", isOn: $app.backgroundEnabled).disabled(app.sensor.running)
                Button("Mulai GPS lokal — tanpa pengiriman") { app.attempt { try app.startLocalSensor() } }
                    .disabled(app.sensor.running || app.store.state.owner != nil || app.store.state.mode != .real || app.busy != nil)
                if app.sensor.running || app.store.state.owner != nil {
                    Button("Hentikan sensor / cleanup", role: .destructive) { Task { await app.stopSharing() } }
                }
                Text("Pengaturan durasi ini dipakai untuk uji sensor tanpa upload. Pilih mode Perangkat nyata melalui reset fixture di Pairing manual bila perlu.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Status izin") {
                Text("Izin lokasi: \(app.sensor.authorization)")
                Text(app.sensor.reduced ? "Presisi terbatas" : "Status akurasi penuh")
                Text(app.sensor.status)
                Text(CloudLocationChannel.containerID).font(.caption.monospaced())
            }
        }.navigationTitle("GPS & iCloud")
    }
}
