import MapKit
import PreferenceQuality
import SwiftUI
import TripIntegration
import VisitTiming

struct IntegrationHome: View {
    @Bindable var model: IntegrationModel
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Gabungkan minat, fakta tempat, jadwal, routing dan cuaca dalam satu draf yang dapat ditinjau.")
                    Text(model.replay ? "REPLAY SINTETIS · bukan hasil MapKit/WeatherKit" : "Jakarta · satu hari WIB · maksimal 6 tempat · mobil/taksi")
                        .font(.caption).foregroundStyle(model.replay ? Color.orange : Color.secondary)
                    Text("Aplikasi dan penyimpanan ini terpisah dari Foundation Lab serta PoC routing.").font(.caption)
                }
                inputSection
                preferenceSection
                requiredSection
                Section {
                    Button("Cari rekomendasi", systemImage: "sparkle.magnifyingglass", action: model.recommend)
                        .accessibilityIdentifier("recommend")
                    if model.busy {
                        ProgressView(model.progress)
                        Button("Batalkan", role: .cancel, action: model.cancel)
                    } else { Text(model.progress).font(.caption).accessibilityIdentifier("pipeline-status") }
                    if let error = model.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("pipeline-error") }
                    if let warning = model.persistenceWarning, !warning.isEmpty { Text(warning).foregroundStyle(.orange) }
                }
                if let review = model.review { suggestionSection(review) }
                if let prepared = model.prepared, model.review != nil { locationSection(prepared) }
                if let proposal = model.session.proposal {
                    Section("Usulan · belum diterapkan") {
                        NavigationLink { PlanScreen(model: model, plan: proposal) } label: {
                            Label(proposal.feasible ? "Tinjau usulan jadwal" : "Tinjau konflik jadwal", systemImage: "calendar")
                        }.accessibilityIdentifier("proposal")
                        Text(proposal.summary).font(.caption)
                    }
                }
                if let accepted = model.session.accepted {
                    Section("Jadwal diterima") {
                        NavigationLink("Buka jadwal tersimpan") { PlanScreen(model: model, plan: accepted) }
                        Text(TripClock.label(accepted.createdAt)).font(.caption)
                    }
                }
                Section("Eksperimen") {
                    NavigationLink("Diagnosis dan bukti cuaca") { WeatherDiagnostics(model: model) }
                    Text("Skor rekomendasi bukan probabilitas kepuasan. Kapasitas, hari libur, antrean dan parkir belum dijamin.")
                        .font(.caption)
                }
            }
            .navigationTitle("C67 · Trip Integration")
            .disabled(model.saving)
            .environment(\.timeZone, TimeZone(identifier: "Asia/Jakarta")!)
        }
    }
    private func binding<T>(_ keyPath: WritableKeyPath<TripRequest, T>) -> Binding<T> {
        Binding(get: { model.request[keyPath: keyPath] }, set: { value in model.edit { $0[keyPath: keyPath] = value } })
    }
    private var departureBinding: Binding<Date> {
        Binding(get: { model.request.departure }, set: { date in
            model.edit { input in
                if TripClock.day(date) != TripClock.day(input.departure) {
                    let clock = TripClock.calendar.dateComponents([.hour, .minute], from: input.deadline)
                    input.deadline = TripClock.calendar.date(bySettingHour: clock.hour!, minute: clock.minute!, second: 0, of: date)!
                }
                input.departure = date
            }
        })
    }
    private var inputSection: some View {
        Section("1 · Batas perjalanan") {
            DatePicker("Berangkat (WIB)", selection: departureBinding)
            DatePicker("Kembali paling lambat", selection: binding(\.deadline))
            Text("Mulai dan kembali di Bundaran HI. Tidak meminta lokasi perangkat.").font(.caption)
            Stepper("Usulan tempat: \(model.request.desiredCount)", value: binding(\.desiredCount), in: 1 ... 6)
            Stepper("Durasi per tempat: \(model.request.defaultDuration) menit", value: binding(\.defaultDuration), in: 15 ... 360, step: 15)
            Picker("Tujuan waktu (saran)", selection: binding(\.goal)) {
                ForEach(TimingGoal.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Gunakan embeddings E5", isOn: binding(\.useEmbedding))
            Toggle("Izinkan fallback Open-Meteo", isOn: binding(\.allowOpenMeteo))
            Text("WeatherKit diminta lebih dahulu. Fallback mati secara default; kegagalan provider tetap dicatat.").font(.caption)
        }
    }
    private var preferenceSection: some View {
        Section("2 · Preferensi (boleh dilewati)") {
            DisclosureGroup("Ubah minat dan syarat") {
                ForEach(QualityFeature.allCases) { feature in
                    Picker(feature.label, selection: Binding(get: {
                        model.request.profile.must.contains(feature) ? "must" : model.request.profile.avoid.contains(feature)
                            ? "avoid" : model.request.profile.prefer.contains(feature) ? "prefer" : "unknown"
                    }, set: { state in
                        model.edit { input in
                            input.profile.must.remove(feature); input.profile.prefer.remove(feature); input.profile.avoid.remove(feature)
                            switch state {
                            case "must": input.profile.must.insert(feature)
                            case "prefer": input.profile.prefer.insert(feature)
                            case "avoid": input.profile.avoid.insert(feature)
                            default: break
                            }
                        }
                    })) {
                        Text("Belum diketahui").tag("unknown")
                        Text("Disukai").tag("prefer")
                        Text("Wajib").tag("must")
                        Text("Hindari").tag("avoid")
                    }
                }
                TextField("Optional trip direction in English", text: Binding(get: { model.request.profile.direction },
                                                                              set: { value in model.edit { $0.profile.direction = value; $0.profile.directionConfirmed = false } }), axis: .vertical)
                    .lineLimit(1 ... 3)
                if !model.request.profile.direction.isEmpty {
                    Toggle("Makna arahan sudah saya wakili di pilihan di atas", isOn: Binding(
                        get: { model.request.profile.directionConfirmed }, set: { value in model.edit { $0.profile.directionConfirmed = value } }))
                    Text("Embeddings membantu urutan semantik. Negasi dan syarat wajib mengikuti pilihan terstruktur, bukan tebakan model.").font(.caption)
                }
            }
        }
    }
    private var requiredSection: some View {
        Section("3 · Tempat yang sudah ingin dikunjungi (opsional)") {
            DisclosureGroup("Saya sudah punya tempat tujuan") {
                ForEach(model.catalog.quality.candidates) { candidate in
                    Toggle("\(candidate.name) · \(candidate.scope)", isOn: Binding(
                        get: { model.request.requiredCandidateIDs.contains(candidate.id) },
                        set: { enabled in model.edit { input in
                            if enabled { input.requiredCandidateIDs.append(candidate.id) }
                            else { input.requiredCandidateIDs.removeAll { $0 == candidate.id } }
                        } }))
                }
                Text("Pilihan ini wajib dipertahankan. Jika bukti atau jadwalnya belum cukup, aplikasi meminta koreksi tanpa menggantinya diam-diam.").font(.caption)
            }
        }
    }
    private func suggestionSection(_ review: RecommendationReview) -> some View {
        Section("4 · Tinjau tempat usulan") {
            Text("Metode: \(review.quality.status)").font(.caption)
            ForEach(review.suggestions.filter { $0.recommended || $0.required || model.selected.contains($0.id) }) { item in
                suggestionRow(item)
            }
            DisclosureGroup("Alternatif dan tempat yang belum layak") {
                ForEach(review.suggestions.filter { !$0.recommended && !$0.required && !model.selected.contains($0.id) }) { item in
                    suggestionRow(item)
                }
            }
            Button("Verifikasi lokasi pilihan melalui MapKit", action: model.verifyLocations)
                .disabled(model.busy || model.selected.isEmpty).accessibilityIdentifier("verify-locations")
            Text("Satu query untuk titik awal dan setiap venue terpilih, maksimal 7 pencarian per percobaan. Tidak ada perluasan query otomatis.").font(.caption)
            DisclosureGroup("Batas dan sumber rekomendasi") {
                ForEach(review.warnings, id: \.self) { Text($0).font(.caption) }
                ForEach(review.quality.catalog.sources) { source in
                    Link(source.title, destination: source.url).font(.caption)
                    Text("Diperiksa: \(TripClock.label(source.checkedAt))").font(.caption2)
                }
            }
        }
    }
    private func suggestionRow(_ item: PlaceSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { model.selected.contains(item.id) },
                                 set: { model.setSelected(item.id, enabled: $0) })) {
                VStack(alignment: .leading) {
                    Text(item.name).font(.headline)
                    Text(item.area).font(.caption)
                    if item.required { Text("Dipilih pengguna · wajib dipertahankan").font(.caption).foregroundStyle(.blue) }
                }
            }.disabled(item.required || !item.selectable || model.busy)
            ForEach(item.reasons, id: \.self) { Text($0).font(.caption) }
            ForEach(item.issues, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            if let timing = item.timing {
                Text("Jam layanan: \(timing.status)").font(.caption)
                ForEach(timing.sources) { source in
                    Link(source.title, destination: source.url).font(.caption)
                }
            }
        }.padding(.vertical, 4)
    }
    private func locationSection(_ prepared: PreparedTrip) -> some View {
        Section("5 · Verifikasi cabang dan buat jadwal") {
            ForEach(prepared.locations) { location in
                VStack(alignment: .leading, spacing: 6) {
                    Text(location.query).font(.headline)
                    if let pin = location.selected {
                        Label(pin.name, systemImage: "checkmark.circle").foregroundStyle(.green)
                        Text(pin.address).font(.caption)
                    }
                    if let issue = location.issue { Text(issue).foregroundStyle(.orange).font(.caption) }
                    if location.selected == nil {
                        ForEach(location.candidates) { pin in
                            Button("Pilih \(pin.name) — \(pin.address)") { model.choosePin(pin.id, locationID: location.id) }
                                .font(.caption).disabled(model.busy)
                        }
                    } else {
                        DisclosureGroup("Ubah hasil pilihan") {
                            ForEach(location.candidates) { pin in
                                Button("Pilih \(pin.name) — \(pin.address)") { model.choosePin(pin.id, locationID: location.id) }
                                    .font(.caption).disabled(model.busy)
                            }
                        }
                    }
                }
            }
            Button("Hitung jadwal, rute dan cuaca", action: model.plan)
                .disabled(model.busy || !prepared.ready).accessibilityIdentifier("calculate-plan")
            Text("Semua kandidat akhir memakai ETA MapKit pada waktu berangkat tiap ruas. Sesi layanan dan aturan masuk diperiksa lagi pada waktu tiba.").font(.caption)
        }
    }
}

struct PlanScreen: View {
    @Bindable var model: IntegrationModel
    let plan: IntegratedPlan
    private var isProposal: Bool { model.session.proposal?.id == plan.id }
    var body: some View {
        List {
            Section(plan.evidenceMode == "live" ? "Draf perjalanan" : "REPLAY SINTETIS") {
                Text(plan.feasible ? "Memenuhi batas jadwal yang dihitung" : "Ada konflik yang belum terselesaikan")
                    .font(.headline).accessibilityIdentifier("plan-status")
                Text(plan.summary)
                if isProposal {
                    Button("Gunakan jadwal ini", action: model.apply)
                        .disabled(!plan.feasible || model.busy || !model.canApplyProposal)
                        .accessibilityIdentifier("accept-plan")
                    if !model.canApplyProposal { Text("Input berubah. Hitung usulan baru sebelum menerapkan.").font(.caption).foregroundStyle(.orange) }
                    Button("Tolak usulan", role: .destructive, action: model.reject).disabled(model.busy)
                } else if model.session.accepted?.id == plan.id {
                    Text("Versi tersimpan; tidak diubah oleh input baru.").font(.caption)
                } else { Text("Usulan ini tidak sedang diterapkan.").font(.caption) }
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }
            Section {
                Map {
                    ForEach(plan.stops) { stop in
                        Marker(stop.name, coordinate: .init(latitude: stop.pin.latitude, longitude: stop.pin.longitude))
                    }
                }.frame(height: 240)
                Text("Pin tujuan; garis geometri rute tidak ditampilkan.").font(.caption)
            }
            ForEach(plan.stops) { stop in
                Section(stop.name) {
                    Text(stop.area).font(.subheadline)
                    LabeledContent("Tiba", value: TripClock.label(stop.arrival))
                    LabeledContent("Kunjungan", value: "\(TripClock.label(stop.visit)) → \(TripClock.label(stop.leave))")
                    LabeledContent("Durasi", value: "\(stop.duration) menit")
                    Text(stop.rainChance.map { "Peluang hujan maksimum selama kunjungan: \(Int(($0 * 100).rounded()))%" }
                        ?? "Cuaca pada interval kunjungan belum diketahui.")
                    Text("Provider: \(stop.weatherProvider ?? "belum diketahui")").font(.caption)
                    DisclosureGroup("Usulan waktu dan sumber") {
                        ForEach(stop.recommendedWindows) { option in
                            Text("\(TripClock.label(option.start))–\(TripClock.label(option.end)): \(option.reason)").font(.caption)
                        }
                        Text("Saran ini tidak otomatis menjadi waktu kunjung dalam rute.").font(.caption)
                        ForEach(plan.timing.filter { $0.venue.id == stop.venueID }) { run in
                            ForEach(run.sources) { source in Link(source.title, destination: source.url).font(.caption) }
                        }
                        ForEach(stop.notes, id: \.self) { Text($0).font(.caption) }
                    }
                    Button("Buat usulan durasi +30 menit") { model.extend(stop, plan: plan) }
                        .disabled(model.busy || stop.duration > 330)
                    Text("Menghitung ulang seluruh draf sebelum trip. Setelah menekan, kembali ke layar utama untuk verifikasi dan perhitungan usulan.").font(.caption)
                }
            }
            Section("Ruas perjalanan") {
                ForEach(plan.legs) { leg in
                    VStack(alignment: .leading) {
                        Text("\(leg.from) → \(leg.to)")
                        Text("\(TripClock.label(leg.departure)) · \(leg.seconds.map { String(format: "%.1f menit", $0 / 60) } ?? "ETA belum tersedia") · \(leg.providerStatus)").font(.caption)
                    }
                }
            }
            Section("Konflik dan ketidakpastian") {
                ForEach(plan.conflicts, id: \.self) { Text($0).foregroundStyle(.red) }
                ForEach(plan.uncertainties, id: \.self) { Text($0).font(.caption) }
            }
            Section("Cuaca dan atribusi") { ForEach(plan.weather) { WeatherEvidenceView(value: $0) } }
            Section("Bukti eksperimen") {
                ForEach(plan.metrics, id: \.stage) { metric in
                    Text("\(metric.stage): \(String(format: "%.2f", metric.seconds)) detik; \(metric.requests) permintaan/grup").font(.caption)
                }
                Text("weather_groups menghitung grup fetch, bukan jumlah internal panggilan hourly/daily/attribution Apple.").font(.caption)
                Button("Siapkan ekspor JSON dan laporan") { model.export(plan) }.disabled(model.busy)
                ForEach(model.exportURLs, id: \.self) { url in ShareLink(url.lastPathComponent, item: url) }
            }
        }.navigationTitle("Tinjau jadwal")
    }
}

struct WeatherEvidenceView: View {
    let value: WeatherEvidence
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(value.provider) · \(value.status)").font(.headline)
            Text("Titik perwakilan: \(value.representative.name), radius grup maksimal 3 km.").font(.caption)
            Text("\(value.memberIDs.joined(separator: ", ")) · \(value.hours.count) interval · cache \(value.cached ? "ya" : "tidak")").font(.caption)
            Text("Metadata: \(TripClock.label(value.fetchedAt)); diambil: \(TripClock.label(value.retrievedAt))").font(.caption)
            if let credit = value.credit {
                if let mark = colorScheme == .dark ? credit.markDarkURL : credit.markLightURL {
                    AsyncImage(url: mark) { image in image.resizable().scaledToFit() }
                        placeholder: { Text(credit.name) }.frame(height: 24)
                }
                Link(credit.name + " · sumber data dan ketentuan", destination: credit.legalURL)
                if value.provider == "open_meteo" {
                    Link("Lisensi CC BY 4.0", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                }
            }
            ForEach(value.errors, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
        }
    }
}

struct WeatherDiagnostics: View {
    @Bindable var model: IntegrationModel
    var body: some View {
        List {
            Section {
                Text("Diagnosis memakai satu titik Jakarta, WeatherKit langsung dan tanpa fallback. Keberhasilan Open-Meteo tidak dianggap keberhasilan WeatherKit.")
                Button("Jalankan diagnosis WeatherKit", action: model.diagnoseWeather).disabled(model.busy || model.replay)
                Text(model.progress).font(.caption)
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }
            ForEach(model.weatherDiagnosis) { WeatherEvidenceView(value: $0) }
            if !model.weatherDiagnosis.isEmpty,
               let data = try? IntegrationJSON.encoder().encode(model.weatherDiagnosis) {
                ShareLink("Bagikan JSON diagnosis", item: String(decoding: data, as: UTF8.self))
            }
            Section("Konfigurasi aplikasi") {
                Text("Bundle ID: giovanchristoffel.c67-trip-integration").textSelection(.enabled)
                Text("Team: DP5XP7C2AM").textSelection(.enabled)
                Text("Aktifkan WeatherKit pada App Services dan App Capabilities untuk App ID ini, lalu gunakan provisioning yang memuat entitlement WeatherKit.")
            }
        }.navigationTitle("Diagnosis cuaca")
    }
}
