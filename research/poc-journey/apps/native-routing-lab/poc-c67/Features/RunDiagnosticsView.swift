import SwiftUI
import UniformTypeIdentifiers

struct RunReport: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

struct RunDiagnosticsView: View {
    let app: POCController
    @State private var exporting = false
    @State private var document = RunReport(text: "")
    @State private var confirmProbe = false
    @State private var manual: ScannerPresentation?
    @State private var routingLab = false
    var body: some View {
        @Bindable var diagnostics = app.diagnostics
        NavigationStack {
            List {
                ErrorNotice(app: app)
                Section("Alat pengujian") {
                    Button("Pairing manual", systemImage: "link") { manual = ScannerPresentation() }.accessibilityIdentifier("open-manual-pairing")
                    Button("Lab rute dinamis", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath") {
                        app.groupRouting.stop(); routingLab = true
                    }.accessibilityIdentifier("open-routing-lab")
                        .disabled(app.sensor.running || app.leaderSharing.locked || app.uploading || app.busy != nil)
                    if app.sensor.running || app.leaderSharing.locked || app.uploading {
                        Text("Hentikan sesi GPS/pengiriman utama sebelum membuka eksperimen DDS agar sesi lokasi tidak berjalan bersamaan.").font(.caption).foregroundStyle(.secondary)
                    }
                    NavigationLink { SensorLabView(app: app) } label: { Label("GPS & iCloud", systemImage: "sensor") }
                }
                Section("Routing rombongan") {
                    Text("Pilih pin orang, kegiatan, atau meeting point pada peta untuk memulai rute. Koordinat tidak dikirim ke perangkat lain oleh modul routing; request arah diteruskan ke Apple MapKit.")
                        .font(.caption)
                    Text("Request \(app.groupRouting.engine.requests) · berhasil \(app.groupRouting.engine.successes) · gagal \(app.groupRouting.engine.failures)")
                    ShareLink("Bagikan laporan routing", item: app.groupRouting.report)
                }
                Section("Pengukuran run") {
                    Picker("Skenario peserta", selection: $diagnostics.scenario) {
                        Text("Foreground").tag("Foreground"); Text("Background / locked").tag("Background")
                    }
                    Button("Mulai ulang pengukuran — warm-up 60 dtk") { app.diagnostics.reset() }
                    Text(app.diagnostics.report(run: app.store.state)).font(.caption.monospaced()).textSelection(.enabled)
                    Button("Ekspor laporan metadata .txt") { document = RunReport(text: app.diagnostics.report(run: app.store.state)); exporting = true }
                }
                Section("Failure / access probes") {
                    Button(app.store.failNextSave ? "Save failure sudah diaktifkan" : "Gagalkan SATU simpan lokal berikutnya") { app.store.failNextSave = true }
                    Text("Lalu coba Tandai diperiksa atau Tutup; tidak boleh ada sukses/count parsial. Input tetap tersedia untuk dicoba lagi.").font(.caption)
                    Button("Uji penolakan write TL…") { confirmProbe = true }.disabled(app.store.state.binding == nil || app.busy != nil)
                    Text("Probe mencoba menulis field uji pada record POC peserta; server harus menolak. Akun ketiga tidak diundang perlu diuji terpisah.").font(.caption)
                }
                Section("Event terbaru — tanpa koordinat/email") {
                    ForEach(app.diagnostics.entries.suffix(80).reversed()) { entry in
                        VStack(alignment: .leading) { Text(entry.event); Text(entry.at.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }.navigationTitle("Diagnostik")
                .fullScreenCover(isPresented: $routingLab) { RoutingExperimentView(lab: app.groupRouting.engine) }
                .sheet(item: $manual) { _ in ManualPairingView(app: app) }
                .fileExporter(isPresented: $exporting, document: document, contentType: .plainText, defaultFilename: "C67-\(app.store.state.runID.uuidString.prefix(8))") { result in
                    if case .failure(let error) = result { app.error = error.localizedDescription }
                }
                .confirmationDialog("Coba write pada record uji peserta?", isPresented: $confirmProbe, titleVisibility: .visible) {
                    Button("Jalankan probe") {
                        Task {
                            await app.perform("Probe akses TL") {
                                guard let ref = app.store.state.binding else { return }
                                let denied = try await app.cloud.probeWriteDenied(ref)
                                app.diagnostics.log(denied ? "ACL probe PASS: server menolak write TL" : "ACL probe FAIL: write TL berhasil")
                                app.error = denied ? "Server menolak write: hasil yang diharapkan." : "AKSES TIDAK SESUAI: TL berhasil menulis. Stop sharing dan perbaiki izin."
                            }
                        }
                    }
                }
        }
    }
}
