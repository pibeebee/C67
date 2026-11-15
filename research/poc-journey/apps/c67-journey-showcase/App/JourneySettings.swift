import SwiftUI
import TripIntegration

struct JourneySettings: View {
    @Bindable var model: JourneyModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Sumber perjalanan") {
                    Picker("Mode", selection: Binding(get: { model.mode }, set: { value in Task { await model.switchMode(value) } })) {
                        Text("Demo").tag(JourneyMode.demo)
                        Text("Live").tag(JourneyMode.live)
                    }.pickerStyle(.segmented).accessibilityIdentifier("data-mode")
                    Text(model.mode == .demo ? "Provider, lokasi, dan cuaca contoh memakai clock fixture. Label Demo mengikuti seluruh hasil dan ekspor." : "MapKit mencari lokasi dan walking ETA. TransJakarta memakai GTFS static, dengan WeatherKit sebagai sumber cuaca utama.")
                    Text("Draf dan itinerary tersimpan terpisah untuk setiap mode.").font(.footnote)
                }
                if model.mode == .live {
                    Section("Cuaca") {
                        Toggle("Izinkan fallback Open-Meteo", isOn: Binding(get: { model.request.allowOpenMeteo }, set: { value in model.edit { $0.allowOpenMeteo = value } }))
                        Button("Periksa WeatherKit", action: model.diagnoseWeather).disabled(model.busy)
                        Text("WeatherKit membutuhkan App ID dan provisioning aplikasi baru yang sudah diaktifkan.").font(.footnote)
                        ForEach(model.diagnosis) { value in JourneyWeatherEvidence(value: value) }
                    }
                }
                Section("Tentang POC") {
                    Text("Blok M · pulang-pergi Bundaran HI · maksimal 6 tempat · WIB")
                    Text("TJ Koridor 1 langsung, dua platform terdekat dalam 800 m, maksimal 20 menit per komponen jalan kaki.").font(.footnote)
                    Text("Bundle ID \(Bundle.main.bundleIdentifier ?? "unknown")").font(.caption).textSelection(.enabled)
                    if let source = try? BuswayFeed.load().source {
                        Link("TransJakarta · GTFS", destination: source.attributionURL)
                        Link("CC BY 4.0", destination: source.licenseURL)
                    }
                }
                if model.busy { ProgressView(model.progress); Button("Batalkan", action: model.cancel) }
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Mode dan sumber").navigationBarTitleDisplayMode(.inline)
                .disabled(model.switching || model.saving)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Selesai") { dismiss() } } }
        }
    }
}
