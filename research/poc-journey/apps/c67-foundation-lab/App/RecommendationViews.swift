import SwiftUI
import TripIntelligence

private enum RecommendationRoute: Hashable { case preferences, result, diagnostics, legacy }
struct RecommendationRootView: View {
    let legacy: LabModel
    @State private var model = RecommendationModel()
    @State private var path: [RecommendationRoute] = []
    @State private var addingPlace = false
    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Text("Tempat yang cocok untuk Anda").font(.title2.bold())
                    Text("Pilih minat Anda. Aplikasi mencari tempat dan menyarankan waktu berkunjung.")
                    Label("Jakarta · rekomendasi tempat dan waktu", systemImage: "mappin.and.ellipse").font(
                        .caption
                    ).foregroundStyle(.secondary)
                    if model.fixture {
                        Text("Mode fixture · data sintetis, tanpa inferensi model").font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Section("Sudah punya tempat yang ingin dikunjungi?") {
                    Picker("Tujuan", selection: $model.brief.hasPlaces) {
                        Text("Belum · pilihkan untuk saya").tag(false)
                        Text("Sudah punya tempat").tag(true)
                    }.pickerStyle(.inline).accessibilityIdentifier("has-places")
                    if model.brief.hasPlaces {
                        ForEach(model.brief.places) { place in
                            VStack(alignment: .leading) {
                                Text(place.place.name)
                                Text(place.place.address).font(.caption).foregroundStyle(.secondary)
                            }
                        }.onDelete { model.brief.places.remove(atOffsets: $0) }
                        Button("Tambah tempat dari MapKit") { addingPlace = true }.disabled(
                            model.brief.places.count >= 6
                        ).accessibilityIdentifier("add-known-place")
                        Text(
                            "Semua tempat pilihan Anda dipertahankan; tidak ada tujuan utama yang ditentukan otomatis."
                        ).font(.caption)
                    }
                }
                Section {
                    NavigationLink("Lanjut · Preferensi Anda", value: RecommendationRoute.preferences)
                        .disabled(model.brief.hasPlaces && model.brief.places.isEmpty).accessibilityIdentifier(
                            "onboarding-next")
                }
                Section {
                    NavigationLink("Eksperimen dan riwayat", value: RecommendationRoute.diagnostics)
                        .accessibilityIdentifier("recommendation-experiments")
                }
                if !model.error.isEmpty { Text(model.error).foregroundStyle(.red) }
            }
            .navigationTitle("Foundation Lab")
            .navigationDestination(for: RecommendationRoute.self) { route in
                switch route {
                case .preferences: RecommendationPreferencesView(model: model)
                case .result: RecommendationResultsView(model: model)
                case .diagnostics: RecommendationDiagnosticsView(model: model, legacy: legacy)
                case .legacy: LabRootView(model: legacy)
                }
            }
            .sheet(isPresented: $addingPlace) {
                PlaceSelectionView(fixture: model.fixture) { model.add($0) }
            }
            .task { await model.load() }
            .onChange(of: model.result?.id) { _, id in
                if id != nil && !path.contains(.result) && !path.contains(.diagnostics) {
                    path.append(.result)
                }
            }
        }
    }
}
private struct RecommendationPreferencesView: View {
    @Bindable var model: RecommendationModel
    var body: some View {
        List {
            Section("Pengalaman yang Anda sukai") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
                    ForEach(Experience.allCases) { experience in
                        Button {
                            model.toggle(experience)
                        } label: {
                            Label(
                                experience.title,
                                systemImage: model.brief.experiences.contains(experience)
                                    ? "checkmark.circle.fill" : "circle"
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.bordered).accessibilityIdentifier("experience-\(experience.rawValue)")
                    }
                }
                Text("Boleh dilewati. Tidak ada minat yang ditambahkan diam-diam.").font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Ritme perjalanan") {
                Picker("Ritme", selection: $model.brief.pace) {
                    Text("Santai").tag(Pace.relaxed)
                    Text("Seimbang").tag(Pace.balanced)
                    Text("Padat").tag(Pace.packed)
                }.pickerStyle(.segmented).accessibilityIdentifier("recommendation-pace")
            }
            Section {
                DisclosureGroup("Preferensi tambahan · opsional") {
                    Picker("Budget per orang", selection: $model.brief.spending) {
                        ForEach(SpendingPreference.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Karakter destinasi", selection: $model.brief.destinations) {
                        ForEach(DestinationPreference.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Transportasi", selection: $model.brief.transport) {
                        ForEach(GettingAround.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Berjalan kaki", selection: $model.brief.walking) {
                        ForEach(WalkingPreference.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Tanggal · YYYY-MM-DD", text: $model.brief.date).autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Text(
                        "Harga, popularitas dan akses belum selalu tersedia. Pilihan dicatat; kesesuaiannya hanya dinilai bila ada data."
                    ).font(.caption)
                    DisclosureGroup("Hal yang dihindari") {
                        ForEach(Experience.allCases) { experience in
                            Button {
                                if model.brief.avoids.contains(experience) {
                                    model.brief.avoids.removeAll { $0 == experience }
                                } else {
                                    model.brief.avoids.append(experience)
                                    model.brief.experiences.removeAll { $0 == experience }
                                }
                            } label: {
                                Label(
                                    experience.title,
                                    systemImage: model.brief.avoids.contains(experience)
                                        ? "minus.circle.fill" : "circle")
                            }
                        }
                    }
                    TextField("Optional English direction", text: $model.brief.text, axis: .vertical)
                        .lineLimit(2 ... 3).autocorrectionDisabled()
                        .accessibilityIdentifier("recommendation-free-text")
                    Text(
                        "Teks bebas dan jawaban model memakai English. Pilihan tombol dapat dipakai tanpa teks."
                    ).font(.caption)
                }
                Button("Simpan pilihan sebagai profil awal") { Task { await model.saveProfile() } }
            }
            Section {
                Button("Temukan rekomendasi") { model.generate() }.disabled(model.busy)
                    .accessibilityIdentifier("discover-recommendations")
                if model.busy {
                    ProgressView(model.progress)
                    Button("Batalkan", role: .cancel) { model.cancel() }.accessibilityIdentifier(
                        "cancel-recommendations")
                }
                if !model.error.isEmpty { Text(model.error).foregroundStyle(.red) }
            }
        }.navigationTitle("Preferensi Anda")
    }
}
private struct PlaceSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let fixture: Bool
    let select: (CandidateV1) -> Void
    @State private var query = ""
    @State private var submitted = ""
    @State private var attempt = 0
    @State private var candidates: [CandidateV1] = []
    @State private var loading = false
    @State private var error = ""
    var body: some View {
        NavigationStack {
            List {
                TextField("Nama tempat di Jakarta", text: $query).autocorrectionDisabled()
                    .accessibilityIdentifier("known-place-query")
                Button("Cari tempat") {
                    submitted = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    attempt += 1
                }
                .disabled(query.isEmpty || loading)
                .accessibilityIdentifier("search-known-place")
                if loading { ProgressView("Mencari…") }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
                ForEach(candidates) { candidate in
                    Button {
                        select(candidate)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(candidate.place.name)
                            Text(candidate.place.category).font(.caption)
                            if let lat = candidate.place.latitude, let lon = candidate.place.longitude {
                                Text("\(lat, specifier: "%.4f"), \(lon, specifier: "%.4f")").font(.caption)
                            }
                        }
                    }.accessibilityIdentifier("choose-known-\(candidate.id)")
                }
                if !submitted.isEmpty && !loading && candidates.isEmpty && error.isEmpty {
                    Text("Belum ada hasil. Coba nama atau cabang yang lebih spesifik.")
                }
            }
            .navigationTitle("Pilih tempat")
            .toolbar { Button("Selesai") { dismiss() } }
            .task(id: attempt) {
                guard !submitted.isEmpty else { return }
                loading = true
                error = ""
                do {
                    let service: any RecommendationSearching =
                        fixture ? RecommendationFixtureSearch() : RecommendationMapSearch()
                    let values = try await service.resolve(submitted)
                    try Task.checkCancellation()
                    candidates = values
                    loading = false
                } catch is CancellationError {} catch {
                    self.error = error.localizedDescription
                    loading = false
                }
            }
        }
    }
}
private struct RecommendationResultsView: View {
    @Bindable var model: RecommendationModel
    var body: some View {
        List {
            if let run = model.result {
                Section {
                    Text("Rekomendasi tempat dan waktu").font(.headline)
                    Text("\(run.brief.date) · Jakarta/WIB").font(.caption)
                    Text(
                        "Urutan kartu bukan urutan perjalanan. Tidak ada rute, ETA atau jadwal baru yang dihitung."
                    ).font(.caption).foregroundStyle(.secondary)
                    Text(run.explanation.summary)
                }
                ForEach(run.advice) { item in
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.candidate.place.name).font(.headline)
                            Text(item.candidate.place.category).font(.caption).foregroundStyle(.secondary)
                            Text(
                                run.selectedIDs.contains(item.id)
                                    ? (run.brief.hasPlaces ? "Tempat pilihan Anda" : "Direkomendasikan model")
                                    : "Kandidat untuk ditinjau"
                            ).font(.caption.bold())
                            Text(item.advice.reason)
                            Label(item.advice.window.recommendationTitle, systemImage: "clock")
                            Text(item.advice.timeReason).font(.footnote)
                            Text(item.advice.timeBasis.recommendationTitle).font(.caption).foregroundStyle(
                                item.advice.timeBasis == .suppliedFacts ? Color.secondary : Color.orange)
                            Text(
                                item.source == "Foundation Models"
                                    ? "Usulan model lokal · periksa alasannya"
                                    : "Template · model tidak memberikan hasil yang dapat digunakan"
                            ).font(.caption).foregroundStyle(.secondary)
                            if !item.advice.unknowns.isEmpty {
                                Text("Belum diketahui: \(item.advice.unknowns.joined(separator: ", "))").font(
                                    .caption)
                            }
                            DisclosureGroup("Sumber informasi") {
                                ForEach(item.candidate.evidence) { evidence in
                                    Text("\(evidence.value)\n\(evidence.source) · \(evidence.observedAt)").font(
                                        .caption)
                                }
                            }
                        }
                    }
                }
                if run.advice.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Belum ada kandidat", systemImage: "magnifyingglass",
                            description: Text("Ubah minat atau coba kembali. Tidak ada tempat yang dibuat-buat."))
                    }
                }
                Section("Informasi yang masih terbatas") {
                    ForEach(run.brief.notices, id: \.self) { Text($0).font(.caption) }
                    ForEach(run.search.errors, id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
                    Text(
                        "\(run.advice.count) kandidat dinilai dari \(run.search.candidates.count) hasil. Maksimal tiga rekomendasi baru ditandai."
                    ).font(.caption)
                }
                Section {
                    if !run.brief.hasPlaces {
                        Button("Cari tempat alternatif") { model.alternatives() }.disabled(model.busy)
                            .accessibilityIdentifier("alternative-recommendations")
                    }
                    NavigationLink("Ubah preferensi", value: RecommendationRoute.preferences)
                        .accessibilityIdentifier("adjust-preferences")
                    NavigationLink("Detail eksperimen dan ekspor", value: RecommendationRoute.diagnostics)
                        .accessibilityIdentifier("discovery-diagnostics")
                }
            } else if model.busy {
                ProgressView(model.progress)
                Button("Batalkan") { model.cancel() }
            } else {
                Text("Pilihan berubah. Buat rekomendasi kembali dari halaman preferensi.")
            }
        }.navigationTitle("Rekomendasi")
    }
}
private struct RecommendationDiagnosticsView: View {
    @Bindable var model: RecommendationModel
    let legacy: LabModel
    var body: some View {
        List {
            Section("Eksperimen") {
                Text(model.runtime?.availability ?? "Memeriksa model…").font(.caption)
                Toggle("Mode fixture · tanpa model", isOn: $model.fixture).onChange(of: model.fixture) {
                    model.invalidate()
                }
                Button("Muat contoh sintetis untuk pengujian") { model.example() }.accessibilityIdentifier(
                    "recommendation-example")
                Button("Jalankan pembanding tanpa model") { model.generate(baseline: true) }.disabled(
                    model.busy)
                NavigationLink(
                    "Lab lama · impor itinerary dan pengujian awal", value: RecommendationRoute.legacy)
                if let context = legacy.context {
                    Button("Gunakan tempat dari snapshot impor") { model.useImported(context) }
                }
            }
            if let run = model.result {
                Section("Run terakhir") {
                    NavigationLink("Lihat rekomendasi ini", value: RecommendationRoute.result)
                        .accessibilityIdentifier("open-saved-recommendations")
                    Text(run.id).font(.caption.monospaced())
                    Text(
                        "\(run.elapsedSeconds, specifier: "%.2f") detik · input \(run.inputSubmissions) · koreksi \(run.correctionRounds)"
                    )
                    Text(run.search.source).font(.caption)
                    Button("Siapkan ekspor") { model.export() }.accessibilityIdentifier(
                        "export-recommendations")
                    if let url = model.exportURL {
                        ShareLink("Bagikan JSON", item: url)
                        ShareLink(
                            "Bagikan Markdown",
                            item: url.deletingLastPathComponent().appendingPathComponent("REPORT.md"))
                    }
                }
                ForEach(run.records) { record in
                    Section(record.capability.rawValue) {
                        Text(
                            "\(record.source) · \(record.status) · \(record.durationSeconds, specifier: "%.2f") detik"
                        ).font(.caption)
                        if !record.error.isEmpty { Text(record.error).font(.caption).foregroundStyle(.orange) }
                        DisclosureGroup("Prompt") {
                            Text(record.instructions + "\n" + record.prompt).font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        DisclosureGroup("Output mentah") {
                            Text(record.rawOutput.isEmpty ? "Tidak ada inferensi" : record.rawOutput).font(
                                .caption.monospaced()
                            ).textSelection(.enabled)
                        }
                    }
                }
            }
            Section("Riwayat rekomendasi") {
                ForEach(model.history) { run in
                    Button("\(run.createdAt) · \(run.advice.count) tempat") { model.restore(run) }
                }
            }
            Section("Sumber wilayah") {
                Text(
                    "Mask operasional Jakarta geoBoundaries/OSM vintage 2017 · ODbL 1.0, bukan batas survei terbaru."
                ).font(.caption)
                Link("geoBoundaries", destination: URL(string: "https://www.geoboundaries.org/")!)
                Link(
                    "OpenStreetMap contributors",
                    destination: URL(string: "https://www.openstreetmap.org/copyright")!)
            }
        }.navigationTitle("Eksperimen")
    }
}
extension VisitWindow {
    fileprivate var recommendationTitle: String {
        switch self {
        case .morning: "Pagi · saran kunjungan"
        case .midday: "Siang · saran kunjungan"
        case .afternoon: "Sore · saran kunjungan"
        case .evening: "Malam · saran kunjungan"
        case .any: "Tidak ada jendela khusus"
        case .unknown: "Waktu yang cocok belum diketahui"
        }
    }
}
extension VisitTimeBasis {
    fileprivate var recommendationTitle: String {
        switch self {
        case .suppliedFacts: "Berdasarkan informasi waktu yang disediakan · periksa sumber"
        case .generalActivitySuggestion:
            "Saran aktivitas umum · bukan jam terbaik atau jam buka tempat yang terverifikasi"
        case .unknown: "Informasi waktu belum mencukupi"
        }
    }
}
