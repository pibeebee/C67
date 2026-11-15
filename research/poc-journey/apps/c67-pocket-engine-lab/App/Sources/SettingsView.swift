import SwiftUI
import PocketEngine

struct SettingsScreen: View {
    @Bindable var model: PocketModel
    @State private var token = TokenVault.read()
    var body: some View {
        NavigationStack {
            Form {
                Section("Katalog bersama") {
                    TextField("URL server", text: $model.serverURL).textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Token baca katalog", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Simpan koneksi") { model.saveConnection(token: token) }
                    Button("Unduh katalog terbaru", systemImage: "arrow.triangle.2.circlepath") { model.sync() }.disabled(model.isSyncing)
                    if model.isSyncing { ProgressView("Mengunduh katalog…") }
                    Text(model.syncLabel).font(.caption).foregroundStyle(.secondary)
                    Text("Simulator dapat memakai localhost. iPhone fisik memerlukan server LAN yang dapat dijangkau atau HTTPS. Token tulis dan kunci provider tetap di server.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Saran waktu kunjungan") {
                    Toggle("Gunakan Luna Max", isOn: $model.usesLunaAdvice)
                    Text("Server mengirim pilihan jadwal, nama tempat, preferensi, dan ringkasan bukti/cuaca ke luna-provider.example. Model memilih ID pilihan; planner memeriksa hasil. Kegagalan tidak memanggil model lain.").font(.caption)
                }
                Section("Mesin di perangkat") {
                    LabeledContent("Ranking & itinerary", value: "Swift di iPhone")
                    LabeledContent("Pencarian katalog", value: "Core Spotlight + kata")
                    LabeledContent("Peta & ETA", value: "Apple MapKit")
                    LabeledContent("Prakiraan", value: "WeatherKit")
                    Text(AppleExplanation.availability).font(.caption)
                }
                Section("Batas PoC") {
                    Text("Jakarta · satu hari WIB · mobil · enam tujuan. Bukti yang berumur 30 hari atau melewati masa berlaku menjadi belum diketahui. Jam dan akses pribadi tidak dibagikan ke server.")
                    Text("Katalog awal berisi identitas sumber terbuka. Tidak ada klaim bahwa 30 tempat sudah layak dikunjungi. Luna memilih satu jadwal yang telah dihitung planner. AI Apple hanya memilih alasan kecocokan yang telah diperiksa.")
                    Text("Profil, pilihan, dan katalog independen disimpan dengan SwiftData. Titik awal sesi, hasil Apple/TomTom, geometri, dan ETA tidak dijadikan cache fakta 30 hari.")
                }
                Section("Sumber & atribusi") {
                    Link("OpenStreetMap contributors · ODbL", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                    Link("Overture Places", destination: URL(string: "https://docs.overturemaps.org/guides/places/")!)
                    Link("TomTom Places Search", destination: URL(string: "https://docs.tomtom.com/places-search-api/documentation/product-information/introduction")!)
                    Link("Apple Weather", destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!)
                }
            }.navigationTitle("Pengaturan")
        }
    }
}
