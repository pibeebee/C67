import SwiftUI

struct WeatherLabRootView: View {
    private enum Destination: Hashable { case weather, planner }
    @State private var selected = Destination.weather
    @State private var plannerOpened = false
    var body: some View {
        TabView(selection: $selected) {
            Tab("Weather Lab", systemImage: "cloud.sun", value: Destination.weather) { WeatherLabView() }
            Tab("Rencana", systemImage: "map", value: Destination.planner) {
                if plannerOpened { NativeTripPlannerView() }
            }
        }
        .onChange(of: selected) { _, value in if value == .planner { plannerOpened = true } }
    }
}

struct WeatherLabView: View {
    @State private var model = WeatherLabModel(simulated: ProcessInfo.processInfo.arguments.contains("--weather-lab-ui-testing"))
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            Form {
                WeatherLabOverviewSection(model: model)
                WeatherLabActionsSection(model: model)
                WeatherLabInputSection(model: model)
                WeatherLabCoverageSection(groups: model.groups)
                if !model.results.isEmpty, let window = model.resultWindow {
                    Section("Hasil pengujian terakhir") {
                        Text("\(WeatherLabFormat.date(window.start)) – \(WeatherLabFormat.date(window.end)) · WIB")
                            .font(.caption)
                        ForEach(model.results) { result in
                            NavigationLink { WeatherLabResultView(result: result, window: window) } label: {
                                WeatherLabResultRow(result: result)
                            }
                        }
                    }
                }
                WeatherLabDiagnosticsSection(model: model)
            }
            .navigationTitle("Weather Lab")
            .environment(\.timeZone, TimeZone(identifier: "Asia/Jakarta")!)
            .onDisappear { model.cancel() }
            .onChange(of: scenePhase) { _, phase in if phase == .background { model.cancel() } }
        }
    }
}

private struct WeatherLabOverviewSection: View {
    let model: WeatherLabModel
    var body: some View {
        Section {
            Label(model.simulated ? "SIMULASI UI · tanpa jaringan" : "Eksperimen cuaca Jakarta", systemImage: "flask")
                .font(.headline)
            Text("Uji WeatherKit di sini. Tab Rencana tetap memakai alur Jakarta dan Open-Meteo yang sudah ada.")
                .font(.footnote).foregroundStyle(.secondary)
            Text(model.status).accessibilityIdentifier("weather-lab-status")
            if model.isRunning { ProgressView("Mengambil cuaca…") }
            if model.authBlocked {
                Label("Autentikasi WeatherKit diblokir untuk sesi ini", systemImage: "exclamationmark.shield")
                    .foregroundStyle(.orange)
                Text("Kelompok berikutnya memakai cadangan. Setelah memperbaiki konfigurasi Apple, uji satu titik lagi atau reset pemutus autentikasi.")
                    .font(.caption)
            }
        }
    }
}

private struct WeatherLabActionsSection: View {
    @Bindable var model: WeatherLabModel
    var body: some View {
        Section("Jalankan eksperimen") {
            Button("1. Diagnosis satu titik WeatherKit") { model.run(probe: true) }
                .disabled(model.isRunning || model.groups.isEmpty)
                .accessibilityIdentifier("weather-lab-probe")
            Text("Request baru ke titik perwakilan pertama, tanpa cache dan cadangan. Gagal autentikasi tetap terlihat.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Provider kelompok", selection: $model.mode) {
                ForEach(WeatherLabMode.allCases) { Text($0.title).tag($0) }
            }.disabled(model.isRunning)
            Button("2. Uji semua kelompok") { model.run() }
                .disabled(model.isRunning || model.groups.isEmpty)
                .accessibilityIdentifier("weather-lab-run")
            Button("Ambil ulang tanpa cache") { model.run(refresh: true) }
                .disabled(model.isRunning || model.groups.isEmpty)
            if model.isRunning { Button("Batalkan", role: .cancel) { model.cancel() } }
            Text("Radius 3 km · maksimal 2 kelompok bersamaan · 8 detik per provider, termasuk maksimal satu retry untuk putus koneksi/timeout jaringan.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct WeatherLabInputSection: View {
    @Bindable var model: WeatherLabModel
    var body: some View {
        Section("Titik dan waktu · WIB") {
            DatePicker("Mulai", selection: $model.start, displayedComponents: [.date, .hourAndMinute])
            DatePicker("Selesai", selection: $model.end, displayedComponents: [.date, .hourAndMinute])
            Text("Pilih rentang maksimal 24 jam. Ketersediaan tanggal mengikuti horizon provider; data yang hilang tetap unknown.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(model.points) { point in
                Toggle(isOn: Binding(get: { model.selected.contains(point.id) }, set: { _ in model.toggle(point.id) })) {
                    VStack(alignment: .leading) {
                        Text(point.name)
                        Text("\(point.latitude, specifier: "%.5f"), \(point.longitude, specifier: "%.5f")")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
            Button("Salin titik dari rencana tersimpan") { model.importSavedPlan() }
            Button("Gunakan enam titik contoh Jakarta") { model.useExamples() }
            Text("Salin titik hanya membaca rencana lokal. Koordinat dipakai langsung; tidak ada pencarian MapKit atau akses GPS.")
                .font(.caption).foregroundStyle(.secondary)
        }.disabled(model.isRunning)
    }
}

private struct WeatherLabCoverageSection: View {
    let groups: [WeatherLabGroup]
    var body: some View {
        Section("Cakupan sebelum request") {
            Text("\(groups.reduce(0) { $0 + $1.members.count }) titik → \(groups.count) kelompok")
                .font(.headline)
            Text("Semua anggota berjarak maksimal 3 km dari titik perwakilannya. Ini asumsi PoC, bukan batas wilayah cuaca resmi atau jaminan hujan seragam.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text("Perwakilan: \(group.representative.name)")
                    Text(group.members.map(\.name).joined(separator: ", ")).font(.caption)
                    Text("Anggota terjauh \(group.maximumDistance / 1_000, specifier: "%.2f") km")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct WeatherLabDiagnosticsSection: View {
    let model: WeatherLabModel
    var body: some View {
        Section("Cache dan bukti uji") {
            LabeledContent("Request hourly WeatherKit", value: "\(model.stats.weatherKitRequests)")
            LabeledContent("Request Open-Meteo", value: "\(model.stats.openMeteoRequests)")
            LabeledContent("Cache hit", value: "\(model.stats.cacheHits)")
            LabeledContent("Entri cache aktif", value: "\(model.cacheCount)")
            LabeledContent("Durasi run", value: String(format: "%.2f detik", model.stats.elapsedSeconds))
            Text("Hitungan request mencakup retry hourly; WeatherKit juga mengambil atribusi jika belum tersedia. Cache hanya di memori, maksimal 15 menit dan mengikuti expiry Apple yang lebih awal.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Kosongkan cache eksperimen") { model.clearCache() }.disabled(model.isRunning)
            Button("Reset pemutus autentikasi") { model.resetAuthentication() }.disabled(model.isRunning)
            NavigationLink("Panduan autentikasi WeatherKit") { WeatherLabAuthGuide() }
            if let url = model.reportURL {
                ShareLink("Bagikan laporan JSON", item: url)
                    .accessibilityIdentifier("weather-lab-export")
            } else if !model.reportJSON.isEmpty {
                ShareLink("Bagikan laporan JSON", item: model.reportJSON)
                    .accessibilityIdentifier("weather-lab-export")
            }
            if !model.events.isEmpty {
                NavigationLink("Log eksperimen (\(model.events.count))") {
                    List(model.events) { event in
                        VStack(alignment: .leading) {
                            Text(WeatherLabFormat.clock(event.date)).font(.caption.monospaced())
                            Text(event.message).font(.footnote).textSelection(.enabled)
                        }
                    }.navigationTitle("Log Weather Lab")
                }
            }
        }
    }
}

private struct WeatherLabResultRow: View {
    let result: WeatherLabResult
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(result.group.representative.name).font(.headline)
            Text(result.group.members.map(\.name).joined(separator: ", ")).font(.caption)
            if let payload = result.payload {
                Label("\(payload.forecast.provider?.title ?? "Provider") · \(result.cached ? "cache" : "request baru")", systemImage: "cloud")
                Text("Berlaku hingga \(WeatherLabFormat.clock(payload.expiresAt)) WIB").font(.caption)
            } else {
                Label("Cuaca belum diketahui", systemImage: "questionmark.circle").foregroundStyle(.orange)
            }
            if let first = result.notes.first { Text(first).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct WeatherLabResultView: View {
    let result: WeatherLabResult
    let window: WeatherLabWindow
    var body: some View {
        List {
            Section { WeatherLabResultRow(result: result) }
            if let payload = result.payload {
                Section("Sumber dan kesegaran") {
                    if let retrieved = payload.forecast.retrievedAt { Text("Diambil: \(WeatherLabFormat.date(retrieved)) WIB") }
                    if let updated = payload.forecast.fetchedAt { Text("Metadata provider: \(WeatherLabFormat.date(updated)) WIB") }
                    Text("Kedaluwarsa: \(WeatherLabFormat.date(payload.expiresAt)) WIB")
                    Text("Prakiraan titik perwakilan dipakai sebagai perkiraan area. Waktu kunjungan setiap tempat membaca interval jamnya sendiri.")
                    if let credit = payload.credit { WeatherLabAppleCredit(credit: credit) }
                    if payload.forecast.provider == .openMeteo { NativeTripOpenMeteoAttribution() }
                }.font(.footnote)
                Section("Coba waktu kunjungan per tempat") {
                    ForEach(result.group.members) { point in
                        WeatherLabVisitRow(point: point, payload: payload, window: window)
                    }
                }
                Section("Prakiraan per jam · WIB") {
                    ForEach(payload.forecast.hours.filter { $0.date < window.end && $0.date.addingTimeInterval(3_600) > window.start }, id: \.date) { hour in
                        HStack {
                            Text(WeatherLabFormat.clock(hour.date))
                            Spacer()
                            Text("Hujan \(hour.rainChance * 100, specifier: "%.0f")%")
                            if let temp = hour.temperatureC { Text("\(temp, specifier: "%.1f")°C") }
                        }.font(.footnote)
                    }
                }
            }
            if !result.notes.isEmpty { Section("Catatan provider") { ForEach(result.notes, id: \.self) { Text($0).font(.footnote) } } }
        }
        .navigationTitle(result.group.representative.name)
        .environment(\.timeZone, TimeZone(identifier: "Asia/Jakarta")!)
    }
}

private struct WeatherLabVisitRow: View {
    let point: WeatherLabPoint
    let payload: WeatherLabPayload
    let window: WeatherLabWindow
    @State private var visit: Date
    init(point: WeatherLabPoint, payload: WeatherLabPayload, window: WeatherLabWindow) {
        self.point = point; self.payload = payload; self.window = window; _visit = State(initialValue: window.start)
    }
    var body: some View {
        VStack(alignment: .leading) {
            DatePicker(point.name, selection: $visit, in: window.start ... window.end.addingTimeInterval(-1))
            if let hour = payload.forecast.hours.first(where: { $0.date <= visit && $0.date.addingTimeInterval(3_600) > visit }) {
                Text("Peluang hujan \(hour.rainChance * 100, specifier: "%.0f")% · interval \(WeatherLabFormat.clock(hour.date)) WIB")
                    .font(.caption).foregroundStyle(.secondary)
            } else { Text("Interval ini belum diketahui.").font(.caption) }
        }
    }
}

private struct WeatherLabAppleCredit: View {
    let credit: NativeTripWeatherCredit
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Link(destination: credit.legalPageURL) {
                AsyncImage(url: colorScheme == .dark ? credit.combinedMarkLightURL : credit.combinedMarkDarkURL) { image in
                    image.resizable().scaledToFit().frame(maxWidth: 130, maxHeight: 30)
                } placeholder: { Text(credit.serviceName) }
            }
            Link("Sumber data \(credit.serviceName)", destination: credit.legalPageURL)
        }
    }
}

private struct WeatherLabAuthGuide: View {
    var body: some View {
        List {
            Section("Jika satu titik gagal autentikasi") {
                Text("1. Periksa Bundle ID dan Team aplikasi di Xcode.")
                Text("2. Pada Apple Developer, App ID harus mengaktifkan WeatherKit di App Capabilities dan App Services.")
                Text("3. Perbarui provisioning profile dan pastikan build bertanda tangan membawa entitlement WeatherKit.")
                Text("4. Jalankan di iPhone, lalu diagnosis satu titik lagi. Keberhasilan cadangan tidak membuktikan autentikasi WeatherKit sudah pulih.")
            }
            Section {
                Link("Panduan konfigurasi Apple", destination: URL(string: "https://developer.apple.com/help/account/services/weatherkit/")!)
                Text("Layar ini tidak mengubah akun, capability atau provisioning secara otomatis. Gunakan laporan JSON untuk mencatat domain/kode kegagalan dan waktu request.")
            }
        }.navigationTitle("Autentikasi")
    }
}

private enum WeatherLabFormat {
    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "id_ID")
        formatter.timeZone = TimeZone(identifier: "Asia/Jakarta"); formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    static func date(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "id_ID")
        formatter.timeZone = TimeZone(identifier: "Asia/Jakarta"); formatter.dateFormat = "d MMM yyyy HH:mm"
        return formatter.string(from: date)
    }
}
