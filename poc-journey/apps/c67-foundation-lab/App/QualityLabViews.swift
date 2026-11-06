import PreferenceQuality
import SwiftUI

struct QualityLabView: View {
    @State private var model = QualityLabModel()
    @State private var showHistory = false
    var body: some View {
        NavigationStack {
            List {
                QualityIntroSection()
                QualityBriefSection(model: model)
                QualityControlsSection(model: model)
                if model.busy {
                    Section {
                        ProgressView(model.progress)
                        Button("Batalkan") { model.cancel() }.accessibilityIdentifier("quality-cancel")
                    }
                }
                if !model.progress.isEmpty { Text(model.progress).font(.footnote) }
                if !model.error.isEmpty { Text(model.error).font(.footnote).foregroundStyle(.red) }
                if let run = model.run {
                    QualityResultSection(run: run, model: model)
                    Section("Identitas MapKit dan ekspor") {
                        Button("Periksa maksimal 3 saran di MapKit") { model.verifyMap() }
                            .disabled(model.busy).accessibilityIdentifier("quality-map")
                        Text(
                            "Pemeriksaan identitas baru; atribut area tetap berasal dari publikasi. Maksimal tiga pencarian, tanpa perubahan ranking atau routing."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        ForEach(model.mapChecks) { check in
                            Text("\(check.candidateID): \(check.status) · \(check.mapName ?? "")").font(.caption)
                        }
                        Button("Siapkan ekspor") { Task { await model.export() } }
                            .accessibilityIdentifier("quality-export")
                        if let folder = model.exportFolder {
                            ShareLink("Bagikan JSON", item: folder.appendingPathComponent("run.json"))
                            ShareLink("Bagikan Markdown", item: folder.appendingPathComponent("REPORT.md"))
                        }
                    }
                }
            }
            .navigationTitle("Kecocokan")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Bandingkan", systemImage: "list.bullet.rectangle") { model.compare() }
                        .disabled(model.busy).accessibilityIdentifier("quality-compare")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Riwayat", systemImage: "clock.arrow.circlepath") { showHistory = true }
                        .accessibilityIdentifier("quality-history")
                }
            }
            .sheet(isPresented: $showHistory) {
                NavigationStack {
                    List(model.history) { run in
                        Button {
                            model.restore(run)
                            showHistory = false
                        } label: {
                            VStack(alignment: .leading) {
                                Text("\(run.status) · \(run.profile.must.count) syarat wajib")
                                Text(run.createdAt.formatted()).font(.caption)
                            }
                        }.accessibilityIdentifier("quality-history-\(run.id)")
                    }
                    .navigationTitle("Riwayat kecocokan")
                    .toolbar { Button("Tutup") { showHistory = false } }
                }
            }
            .task { await model.load() }
            .onDisappear { model.stopPending() }
        }
    }
}

private struct QualityIntroSection: View {
    var body: some View {
        Section {
            Text("Preferensi → bukti → rekomendasi").font(.headline)
            Text(
                "12 kandidat area dari 9 tempat nyata Jakarta. Fakta diperiksa 5 November 2026; belum inspeksi lokasi."
            )
            .font(.subheadline).foregroundStyle(.secondary)
            Text(
                "Semua metode memakai kandidat dan aturan wajib yang sama. Kategori 60% + kemiripan 40% adalah bobot eksperimen, bukan probabilitas."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
private struct QualityBriefSection: View {
    let model: QualityLabModel
    var body: some View {
        Section("Mulai dari kebutuhan") {
            Button("Kopi sambil membaca") { model.preset("coffee-reading") }
                .accessibilityIdentifier("quality-preset-combo")
            Button("Membaca, utamakan zona hening") { model.preset("reading-soft-silent") }
                .accessibilityIdentifier("quality-preset-soft")
            Button("Membaca tanpa kopi") { model.preset("reading-avoid-coffee") }
                .accessibilityIdentifier("quality-preset-avoid")
            Button("Kopi + membaca + zona hening") { model.preset("coffee-silent-reading") }
                .accessibilityIdentifier("quality-preset-impossible")
            Button("Alam di luar ruang") { model.preset("outdoor-nature") }
            Button("Mulai tanpa preferensi") { model.profile = .init() }
            if let id = model.profile.likedID, let feature = model.profile.likedFeature {
                Text("Sinyal like: \(id) → \(feature.label). Atribut lain tidak ikut diasumsikan.")
                    .font(.caption).accessibilityIdentifier("quality-like-summary")
                Button("Hapus sinyal like") {
                    var value = model.profile
                    value.likedID = nil
                    value.likedFeature = nil
                    model.profile = value
                }
            }
        }
    }
}
private struct QualityControlsSection: View {
    @Bindable var model: QualityLabModel
    var body: some View {
        Section("Koreksi preferensi") {
            DisclosureGroup("Syarat wajib, preferensi dan avoid") {
                ForEach(QualityFeature.allCases) { feature in
                    Menu {
                        Button("Wajib") { model.set(feature, mode: "must") }
                        Button("Diutamakan") { model.set(feature, mode: "prefer") }
                        Button("Hindari") { model.set(feature, mode: "avoid") }
                        Button("Tidak ditentukan") { model.set(feature, mode: "unknown") }
                    } label: {
                        LabeledContent(feature.label, value: selection(feature))
                    }.accessibilityIdentifier("quality-feature-\(feature.rawValue)")
                }
            }
            TextField(
                "Arahan opsional Indonesia / Inggris",
                text: Binding(
                    get: { model.profile.direction },
                    set: { text in
                        var value = model.profile
                        value.direction = text
                        value.directionConfirmed = false
                        model.profile = value
                    }), axis: .vertical
            )
            .accessibilityIdentifier("quality-direction")
            if !model.profile.direction.isEmpty && !model.profile.directionConfirmed {
                Button("Tinjau arahan") { model.reviewDirection() }
                    .accessibilityIdentifier("quality-review")
                if let proposal = model.proposal {
                    Text("Usulan wajib: \(proposal.must.map(\.label).sorted().joined(separator: ", "))")
                        .font(.caption)
                    Button("Gunakan usulan pilihan") { model.acceptProposal() }
                        .accessibilityIdentifier("quality-accept-proposal")
                }
                Button("Pilihan terstruktur saya sudah mewakili arahan") { model.confirmControls() }
                    .accessibilityIdentifier("quality-confirm-controls")
            }
            Text(
                "Zona hening berarti aturan resmi, bukan hasil pengukuran keramaian. Negasi dan koreksi teks perlu konfirmasi pilihan."
            )
            .font(.caption).foregroundStyle(.secondary)
            Text("Wajib: \(model.profile.must.map(\.label).sorted().joined(separator: ", "))")
                .font(.caption).accessibilityIdentifier("quality-must-summary")
            Text(
                "Diutamakan: \(model.profile.softFeatures.map(\.label).sorted().joined(separator: ", "))"
            )
            .font(.caption)
            Text("Hindari: \(model.profile.avoid.map(\.label).sorted().joined(separator: ", "))")
                .font(.caption)
        }
    }
    private func selection(_ feature: QualityFeature) -> String {
        if model.profile.must.contains(feature) { return "Wajib" }
        if model.profile.avoid.contains(feature) { return "Hindari" }
        if model.profile.prefer.contains(feature) { return "Diutamakan" }
        return "Belum ditentukan"
    }
}
private struct QualityResultSection: View {
    let run: QualityRun
    let model: QualityLabModel
    var body: some View {
        Section("Hasil perbandingan") {
            Text(run.status).font(.headline).accessibilityIdentifier("quality-result")
            Text(
                "Terverifikasi \(run.category.count); perlu dicek \(run.decisions.filter { $0.state == "needs_check" }.count)"
            )
            .font(.caption)
            if run.status == "general_not_personalized" {
                Text("Penjelajahan umum; belum personal.")
            }
            if run.status == "no_supported_preference" {
                Text(
                    "Belum ada aspek yang disukai dengan bukti cukup. Daftar kategori hanya alternatif umum.")
            }
            QualityRankingGroup(title: "Kategori", rows: run.category, run: run, model: model)
            QualityRankingGroup(title: "Embeddings", rows: run.semantic, run: run, model: model)
            QualityRankingGroup(title: "Gabungan", rows: run.combined, run: run, model: model)
            DisclosureGroup("Kandidat yang belum memenuhi bukti") {
                ForEach(run.decisions.filter { $0.state != "eligible" }) { decision in
                    VStack(alignment: .leading) {
                        Text("\(decision.candidate.name) / \(decision.candidate.scope)").font(.subheadline)
                        Text(decision.state).font(.caption)
                        Text(decision.reasons.joined(separator: " ")).font(.caption)
                        if !decision.unknown.isEmpty {
                            Text("Belum terverifikasi: \(decision.unknown.map(\.label).joined(separator: ", "))")
                                .font(.caption)
                        }
                    }
                }
            }
            ForEach(run.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            Text(
                "Input \(run.inputChanges), koreksi setelah hasil \(run.userCorrections), tinjau arahan \(run.followupQuestions). Counter bukan bukti pengurangan beban pengguna."
            )
            .font(.caption)
        }
    }
}
private struct QualityRankingGroup: View {
    @State private var expanded = false
    let title: String
    let rows: [QualityRow]
    let run: QualityRun
    let model: QualityLabModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                expanded.toggle()
            } label: {
                Label(
                    "\(title) · \(min(rows.count, 3)) saran",
                    systemImage: expanded ? "chevron.down" : "chevron.right")
            }
            .buttonStyle(.borderless)
            .accessibilityValue(expanded ? "Terbuka" : "Tertutup")
            .accessibilityIdentifier("quality-ranking-\(title)")
            if expanded {
                if rows.isEmpty { Text("Belum ada hasil pada metode ini.").font(.caption) }
                ForEach(Array(rows.prefix(3))) { row in
                    if let candidate = run.catalog.candidates.first(where: { $0.id == row.id }) {
                        QualityCandidateCard(candidate: candidate, row: row, catalog: run.catalog, model: model)
                    }
                }
            }
        }
    }
}
private struct QualityCandidateCard: View {
    let candidate: QualityCandidate
    let row: QualityRow
    let catalog: QualityCatalog
    let model: QualityLabModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(candidate.name).font(.headline)
            Text(candidate.scope).font(.subheadline)
            Text(candidate.address).font(.caption)
            Text(scoreSummary).font(.caption)
            Text("Preferensi didukung: \(row.supportedPreferences.map(\.label).joined(separator: ", "))")
                .font(.caption)
            if row.supportedPreferences.isEmpty {
                Text("Belum ada preferensi lunak yang terbukti pada area ini.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            factDisclosure
            Menu("Saya suka aspek…") {
                ForEach(candidate.claims.filter { $0.value == .yes }, id: \.feature) { claim in
                    Button(claim.feature.label) { model.like(candidate.id, feature: claim.feature) }
                }
            }.accessibilityIdentifier("quality-like-\(candidate.id)")
            Button("Lewati kandidat ini") { model.dismiss(candidate.id) }
                .accessibilityIdentifier("quality-dismiss-\(candidate.id)")
        }.padding(.vertical, 4)
    }

    private var scoreSummary: String {
        var parts: [String] = ["Kategori " + String(format: "%.3f", row.categoryScore)]
        if let score = row.semanticScore { parts.append("cosine " + String(format: "%.3f", score)) }
        if let score = row.combinedScore { parts.append("gabungan " + String(format: "%.3f", score)) }
        return parts.joined(separator: " · ")
    }

    private var factDisclosure: some View {
        DisclosureGroup("Fakta dan sumber area ini") {
            ForEach(candidate.claims, id: \.feature) { claim in
                Text("\(claim.feature.label): \(claim.value.rawValue)").font(.caption.bold())
                Text(claim.statement).font(.caption)
            }
            Text("Atribut lain tetap unknown; makanan/minuman tidak otomatis boleh di semua area.")
                .font(.caption)
            ForEach(catalog.sources.filter { candidate.sourceIDs.contains($0.id) }) { source in
                Link(source.title, destination: source.url).font(.caption)
                Text(
                    "Diperiksa \(QualityPipeline.date(source.checkedAt)); publikasi \(source.publishedDate ?? "tanggal tidak tercantum")"
                )
                .font(.caption)
            }
        }
    }
}
