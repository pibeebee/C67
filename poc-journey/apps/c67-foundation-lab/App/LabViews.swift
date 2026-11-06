import SwiftUI
import TripIntelligence
import UniformTypeIdentifiers

private enum LabRoute: Hashable { case preferences, results, experiments }

struct LabRootView: View {
    @Bindable var model: LabModel
    @State private var importing = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Dari itinerary ke rekomendasi yang sesuai Anda.").font(.headline)
                    Text("Mulai dari contoh atau hasil routing tersimpan. Jadwal asli tetap dipertahankan.")
                        .foregroundStyle(.secondary)
                    RuntimeLabel(runtime: model.runtime, fixture: model.fixtureMode)
                }
                Section("1 · Pilih itinerary") {
                    Button("Contoh Jakarta · 5 tujuan") { choose(synthetic: false) }.accessibilityIdentifier(
                        "example-jakarta")
                    Button("Contoh sintetis · 3 tujuan") { choose(synthetic: true) }.accessibilityIdentifier(
                        "example-synthetic")
                    Button("Impor hasil routing (.json)") { importing = true }.accessibilityIdentifier(
                        "import-routing")
                }
                if let context = model.context {
                    Section("Snapshot terpilih") {
                        Text(context.synthetic ? "Data sintetis" : "Snapshot provider bertanggal").font(
                            .subheadline.bold())
                        Text("\(context.stops.count) tujuan · \(context.timeZoneID)")
                        Text("Tanggal asli: \(context.departure)").font(.caption)
                        NavigationLink("Lanjut · Berikan arahan", value: LabRoute.preferences)
                            .accessibilityIdentifier("continue-preferences")
                    }
                }
                if !model.error.isEmpty {
                    Section { Text(model.error).foregroundStyle(.red).accessibilityIdentifier("lab-error") }
                }
                Section {
                    NavigationLink("Eksperimen dan riwayat", value: LabRoute.experiments)
                        .accessibilityIdentifier("open-experiments")
                }
            }
            .navigationTitle("C67 Foundation Lab")
            .navigationDestination(for: LabRoute.self) { route in
                switch route {
                case .preferences: PreferencesView(model: model)
                case .results: ResultsView(model: model)
                case .experiments: ExperimentsView(model: model)
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): model.importFile(url)
                case .failure(let error): model.error = error.localizedDescription
                }
            }
        }
    }
    private func choose(synthetic: Bool) {
        do { model.select(try synthetic ? LabFixtures.synthetic() : LabFixtures.jakarta()) } catch {
            model.error = error.localizedDescription
        }
    }
}

private struct RuntimeLabel: View {
    let runtime: ModelRuntime?
    let fixture: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if fixture {
                Label("Mode fixture · tanpa inferensi model", systemImage: "testtube.2").foregroundStyle(
                    .orange)
            } else if let runtime {
                Label(
                    runtime.available && runtime.englishSupported
                        ? "Model lokal tersedia · English" : "Model belum tersedia · template aktif",
                    systemImage: runtime.available ? "sparkles" : "info.circle")
                if !runtime.available || !runtime.englishSupported {
                    Text(runtime.availability).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Memeriksa model lokal…")
            }
        }.font(.caption)
    }
}

private struct PreferencesView: View {
    @Bindable var model: LabModel
    var body: some View {
        List {
            Section("2 · Berikan arahan") {
                TextField("e.g. Relaxed, coffee and reading", text: $model.direction.text, axis: .vertical)
                    .lineLimit(2 ... 4).textInputAutocapitalization(.sentences).autocorrectionDisabled()
                    .accessibilityIdentifier("trip-direction")
                Text(
                    "Opsional · teks bebas dalam bahasa Inggris. Anda dapat langsung memakai pilihan di bawah."
                ).font(.caption).foregroundStyle(.secondary)
            }
            Section("Untuk perjalanan ini") {
                InterestChoices(selection: model.direction.trip.interests) {
                    model.toggle($0, persistent: false)
                }
                Picker("Ritme", selection: $model.direction.paceOverride) {
                    Text("Ikuti arahan · default seimbang").tag(Optional<Pace>.none)
                    Text("Santai").tag(Optional(Pace.relaxed))
                    Text("Seimbang").tag(Optional(Pace.balanced))
                    Text("Padat").tag(Optional(Pace.packed))
                }.accessibilityIdentifier("trip-pace")
                DisclosureGroup("Hal yang dihindari") {
                    ForEach(Interest.allCases, id: \.self) { interest in
                        Button {
                            if model.direction.trip.avoids.contains(interest) {
                                model.direction.trip.avoids.removeAll { $0 == interest }
                            } else {
                                model.direction.trip.avoids.append(interest)
                                model.direction.trip.interests.removeAll { $0 == interest }
                            }
                        } label: {
                            Label(
                                interest.title,
                                systemImage: model.direction.trip.avoids.contains(interest)
                                    ? "minus.circle.fill" : "circle")
                        }
                    }
                }
            }
            Section {
                DisclosureGroup("Profil saya · disimpan terpisah") {
                    InterestChoices(selection: model.direction.persistent.interests) {
                        model.toggle($0, persistent: true)
                    }
                    Button("Simpan profil pilihan") { Task { await model.saveProfile() } }
                    Text("Arahan teks dan pilihan khusus trip tidak otomatis menjadi profil permanen.").font(
                        .caption)
                }
            }
            Section {
                Button("Buat rekomendasi") { model.generate() }.disabled(model.running)
                    .accessibilityIdentifier("generate-recommendations")
                if model.running {
                    ProgressView("Memproses preferensi, tempat, waktu, dan penjelasan…")
                    Button("Batalkan", role: .cancel) { model.cancel() }.accessibilityIdentifier(
                        "cancel-generation")
                }
                if model.result != nil {
                    NavigationLink("Lihat rekomendasi", value: LabRoute.results).accessibilityIdentifier(
                        "view-results")
                }
                if !model.error.isEmpty { Text(model.error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Preferensi Anda")
    }
}

private struct InterestChoices: View {
    let selection: [Interest]
    let toggle: (Interest) -> Void
    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8
        ) {
            ForEach(Interest.allCases, id: \.self) { interest in
                Button {
                    toggle(interest)
                } label: {
                    Label(
                        interest.title,
                        systemImage: selection.contains(interest) ? "checkmark.circle.fill" : "circle"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.bordered).tint(selection.contains(interest) ? .blue : .secondary)
                    .accessibilityIdentifier("interest-\(interest.rawValue)")
            }
        }
    }
}

private struct ResultsView: View {
    @Bindable var model: LabModel
    var body: some View {
        List {
            if let run = model.result {
                Section {
                    Text("3 · Rekomendasi perjalanan").font(.headline)
                    Text(
                        "Tempat tambahan dan jendela kunjungan masih usulan. Jadwal baru belum dihitung kelayakannya."
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                    Text(run.context.synthetic ? "Konteks sintetis" : "Konteks provider bertanggal").font(
                        .caption)
                }
                Section("Preferensi yang digunakan") {
                    Text(
                        run.profile.interests.map(\.title).joined(separator: ", ").isEmpty
                            ? "Belum ada minat khusus"
                            : run.profile.interests.map(\.title).joined(separator: ", "))
                    Text("Ritme: \(run.profile.pace.rawValue)")
                    if !run.profile.avoids.isEmpty {
                        Text("Dihindari: \(run.profile.avoids.map(\.title).joined(separator: ", "))")
                    }
                    if !run.profile.clarification.isEmpty { Text(run.profile.clarification) }
                    StageSource(run: run, capability: .preferences)
                }
                Section("Jadwal asli · tidak diubah") {
                    Text("\(run.context.departure) · \(run.context.timeZoneID)").font(.caption)
                    ForEach(run.context.stops) { stop in
                        let leg = run.context.legs.first { $0.toID == stop.id && !$0.isReturn }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(stop.place.name).font(.subheadline.bold())
                            Text(
                                "Tiba \(Codec.clock(leg?.arrival, zone: run.context.timeZoneID)) · kunjungan \(stop.dwellMinutes) menit"
                            ).font(.caption)
                        }
                    }
                    Text(
                        "Selesai: \(Codec.clock(run.context.finish, zone: run.context.timeZoneID)) · batas \(Codec.clock(run.context.deadline, zone: run.context.timeZoneID))"
                    )
                    Text(
                        run.context.complete && run.context.conflicts.isEmpty
                            ? "Memenuhi batas yang diketahui pada snapshot"
                            : "Ada konflik atau data belum lengkap"
                    ).font(.caption)
                    ForEach(run.context.conflicts, id: \.self) { Text($0).foregroundStyle(.red) }
                }
                Section("Usulan waktu kunjungan") {
                    StageSource(run: run, capability: .windows)
                    ForEach(run.windows.suggestions, id: \.stopID) { suggestion in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                run.context.stops.first { $0.id == suggestion.stopID }?.place.name
                                    ?? suggestion.stopID
                            ).bold()
                            Text(suggestion.window.title)
                            Text(suggestion.reason).font(.footnote)
                            Text(
                                "Sumber: \(Set(run.context.evidence.filter { suggestion.evidenceIDs.contains($0.id) }.map(\.source)).sorted().joined(separator: ", "))"
                            ).font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Tempat tambahan") {
                    StageSource(run: run, capability: .candidates)
                    Text(run.search.source).font(.caption)
                    if run.candidates.choices.isEmpty {
                        Text("Belum ada kandidat. Pilih minat atau periksa status pencarian.")
                    }
                    ForEach(run.candidates.choices, id: \.candidateID) { choice in
                        if let candidate = run.search.candidates.first(where: { $0.id == choice.candidateID }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.place.name).bold()
                                if let latitude = candidate.place.latitude,
                                   let longitude = candidate.place.longitude
                                {
                                    Text("Lokasi: \(latitude, specifier: "%.5f"), \(longitude, specifier: "%.5f")")
                                        .font(.caption)
                                }
                                Text(choice.reason).font(.footnote)
                                Text("Belum diketahui: \(choice.unknowns.joined(separator: ", "))").font(.caption)
                                Text("Tambahan waktu dan kelayakan belum dihitung").font(.caption).foregroundStyle(
                                    .secondary)
                                Text("Sumber: \(candidate.evidence.map(\.source).joined(separator: ", "))").font(
                                    .caption)
                            }
                        }
                    }
                    ForEach(run.search.errors, id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
                }
                Section("Tentang itinerary Anda") {
                    StageSource(run: run, capability: .explanation)
                    Text(run.explanation.summary)
                    ForEach(run.explanation.unknowns, id: \.self) {
                        Text($0).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    NavigationLink("Detail eksperimen dan ekspor", value: LabRoute.experiments)
                        .accessibilityIdentifier("results-experiments")
                }
            } else {
                Text("Input berubah. Kembali ke preferensi untuk membuat rekomendasi baru.")
            }
        }
        .navigationTitle("Rekomendasi")
    }
}

private struct StageSource: View {
    let run: ExperimentRunV1
    let capability: Capability
    var body: some View {
        if let stage = run.stages.first(where: { $0.capability == capability }) {
            Text(
                stage.source == "Foundation Models"
                    ? "Model lokal · usulan untuk ditinjau"
                    : stage.status == "baseline"
                    ? "Template pembanding" : "Template · model belum memberikan hasil yang dapat digunakan"
            ).font(.caption).foregroundStyle(
                stage.source == "Foundation Models" ? Color.secondary : Color.orange)
        }
    }
}

private struct ExperimentsView: View {
    @Bindable var model: LabModel
    var body: some View {
        List {
            Section("Lingkungan") {
                RuntimeLabel(runtime: model.runtime, fixture: model.fixtureMode)
                Toggle("Mode fixture · tanpa inferensi", isOn: $model.fixtureMode).accessibilityIdentifier(
                    "fixture-mode"
                )
                .onChange(of: model.fixtureMode) { model.changed() }
                Text(
                    "Model: English · kontrol: Indonesia · batas 20 detik/tugas, 800 token keluaran, tanpa retry otomatis."
                ).font(.caption)
                if model.context != nil {
                    Button("Jalankan pembanding tanpa model") { model.generate(baseline: true) }.disabled(
                        model.running)
                }
            }
            if let run = model.result {
                Section("Run terakhir") {
                    Text(run.id).font(.caption.monospaced())
                    Text(
                        "\(run.elapsedSeconds, specifier: "%.2f") detik · input \(run.inputSubmissions) · koreksi \(run.corrections)"
                    )
                    Text("Validasi bentuk/referensi tidak membuktikan kebenaran semua kalimat.").font(
                        .caption)
                    Button("Siapkan ekspor JSON dan Markdown") { model.export() }.accessibilityIdentifier(
                        "prepare-export")
                    if let url = model.exportURL {
                        ShareLink("Bagikan JSON", item: url)
                        ShareLink(
                            "Bagikan laporan Markdown",
                            item: url.deletingLastPathComponent().appendingPathComponent("REPORT.md"))
                    }
                }
                ForEach(run.stages) { stage in
                    Section(stage.capability.rawValue) {
                        Text(
                            "\(stage.source) · \(stage.status) · \(stage.durationSeconds, specifier: "%.3f") s")
                        if !stage.error.isEmpty { Text(stage.error).font(.caption).foregroundStyle(.orange) }
                        DisclosureGroup("Instructions dan prompt") {
                            Text(stage.instructions + "\n\n" + stage.prompt).font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        DisclosureGroup("Output mentah") {
                            Text(stage.rawOutput.isEmpty ? "Tidak ada respons model" : stage.rawOutput).font(
                                .caption.monospaced()
                            ).textSelection(.enabled)
                        }
                        DisclosureGroup("Output yang ditampilkan") {
                            Text(stage.displayedOutput).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
                Section("Sumber snapshot") {
                    Text(run.context.source).font(.caption)
                    ForEach(run.context.evidence) { evidence in
                        DisclosureGroup(evidence.id) {
                            Text("\(evidence.value)\n\(evidence.source)\n\(evidence.observedAt)").font(.caption)
                        }
                    }
                }
            }
            Section("Riwayat lokal") {
                ForEach(model.history) { run in
                    Button("\(run.createdAt) · \(run.context.stops.count) tujuan") { model.restore(run) }
                }
            }
            Section("Data wilayah") {
                Text("Mask Jakarta geoBoundaries/OSM, vintage 2017, ODbL 1.0; cakupan operasional PoC.")
                    .font(.caption)
                Link("geoBoundaries", destination: URL(string: "https://www.geoboundaries.org/")!)
                Link(
                    "OpenStreetMap contributors",
                    destination: URL(string: "https://www.openstreetmap.org/copyright")!)
            }
        }.navigationTitle("Eksperimen")
    }
}

extension Interest {
    fileprivate var title: String {
        switch self {
        case .coffee: "Kopi"
        case .reading: "Membaca"
        case .quiet: "Suasana tenang"
        case .indoor: "Indoor"
        case .outdoor: "Outdoor"
        case .culture: "Budaya dan museum"
        case .food: "Kuliner"
        case .photography: "Fotografi"
        }
    }
}
extension VisitWindow {
    fileprivate var title: String {
        switch self {
        case .morning: "Pagi · usulan"
        case .midday: "Siang · usulan"
        case .afternoon: "Sore · usulan"
        case .evening: "Malam · usulan"
        case .any: "Tidak ada jendela khusus yang terbukti"
        case .unknown: "Belum cukup informasi"
        }
    }
}
