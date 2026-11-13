import SwiftUI

struct LeaderSharingView: View {
    let app: POCController
    @State private var consent = false
    @State private var erase = false
    var body: some View {
        @Bindable var sharing = app.leaderSharing
        NavigationStack {
            Form {
                ErrorNotice(app: app)
                Section {
                    Label("Lokasi saya sebagai TL", systemImage: "location.fill").font(.title2.bold())
                    Text(sharing.status).accessibilityIdentifier("leader-sharing-status")
                    Text("Koneksi privat ini juga mengirim rundown. Stop lokasi hanya menghentikan GPS; gunakan Hapus seluruh koneksi untuk mencabut kanal rundown juga.").font(.caption).foregroundStyle(.secondary)
                    Text("Lokasi ini hanya dibaca peserta yang dihubungkan lewat QR. Peserta baru yang bergabung selama sesi aktif juga menerima lokasi TL sampai sesi berakhir.").font(.caption).foregroundStyle(.secondary)
                }
                if sharing.sensor.running || sharing.pausePending {
                    Section {
                        Button("Hentikan lokasi TL", role: .destructive) { consent = false; Task { await sharing.stop() } }.accessibilityIdentifier("stop-leader-sharing")
                        Text("Sensor berhenti langsung. Saat online, koordinat pada cloud dibersihkan; undangan tetap tersimpan untuk sesi berikutnya.").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Section("Sesi berbagi TL") {
                        Stepper("Durasi \(Int(sharing.durationMinutes)) menit", value: $sharing.durationMinutes, in: 5 ... 120, step: 5)
                        Toggle("Lanjutkan saat layar terkunci", isOn: $sharing.backgroundEnabled)
                        Toggle("Saya setuju membagikan lokasi TL kepada peserta perjalanan ini selama durasi tersebut", isOn: $consent).accessibilityIdentifier("leader-location-consent")
                        Button("Mulai berbagi lokasi TL") {
                            Task { do { try await sharing.start(consent: consent) } catch { app.error = error.localizedDescription } }
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("start-leader-sharing")
                            .disabled(!consent || sharing.busy || !sharing.hasConnections || app.sensor.running || app.store.state.qrMembers == nil)
                        if !sharing.hasConnections { Text("Hubungkan minimal satu peserta melalui QR terbaru terlebih dahulu.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if sharing.busy { Section { ProgressView("Menyelesaikan operasi lokasi TL…") } }
                Section("Sampel TL di iPhone ini") { LocationReadout(sample: sharing.sensor.running ? sharing.sensor.latest : nil) }
                if sharing.hasConnections {
                    Section {
                        Button("Hapus seluruh koneksi lokasi TL", role: .destructive) { erase = true }
                            .disabled(sharing.busy || sharing.sensor.running || app.pairing.nearby.active || app.pairing.hasPendingCloudWork)
                        Text("Gunakan sebelum mengganti perjalanan atau membersihkan pairing yang tidak selesai. Peserta perlu scan ulang QR agar mendapat lokasi TL lagi.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.navigationTitle("Berbagi lokasi TL").navigationBarTitleDisplayMode(.inline).toolbar { SheetCloseButton() }
                .onChange(of: sharing.sensor.running) { _, running in if !running { consent = false } }
                .alert("Cabut seluruh akses ke lokasi TL?", isPresented: $erase) {
                    Button("Cabut koneksi lokasi TL", role: .destructive) { Task { do { try await sharing.remove() } catch { app.error = error.localizedDescription } } }
                    Button("Batal", role: .cancel) {}
                } message: { Text("Koneksi lokasi TL dihapus dari cloud. Posisi peserta dan riwayat pemeriksaan tidak dihapus.") }
        }
    }
}
