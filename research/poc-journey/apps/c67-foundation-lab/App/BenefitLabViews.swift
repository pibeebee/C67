import PreferenceQuality
import SwiftUI

struct BenefitLabView: View {
    @State private var model = BenefitLabModel()
    @State private var showingHistory = false
    var body: some View {
        NavigationStack {
            Form {
                Section("05 · Nilai tambah embeddings") {
                    Text("Bandingkan kategori, kata kunci dan E5 pada arahan serta bukti tempat yang sama.")
                    Text(
                        "Katalog bersumber 5 November 2026 · 19 area / 16 venue. Eksperimen ini tidak menghitung rute atau menjamin tempat dapat dikunjungi sekarang."
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                }
                if let dataset = model.dataset {
                    Section("Kasus yang dibekukan sebelum inferensi") {
                        Picker("Pilih kasus", selection: $model.selectedID) {
                            ForEach(dataset.cases) { item in Text(item.title).tag(item.id) }
                        }.accessibilityIdentifier("benefit-case")
                        Button("Parafrasa: sejarah uang") { model.selectedID = "currency-paraphrase" }
                            .accessibilityIdentifier("benefit-preset-currency")
                        Button("Kategori sudah cukup: membaca hening") {
                            model.selectedID = "focused-study-paraphrase"
                        }
                        .accessibilityIdentifier("benefit-preset-category")
                        Button("Tidak ada bukti: kopi + baca + hening") {
                            model.selectedID = "safety-combination"
                        }
                        .accessibilityIdentifier("benefit-preset-impossible")
                        Button("Negasi belum dikonfirmasi") { model.selectedID = "safety-negation" }
                            .accessibilityIdentifier("benefit-preset-review")
                        if let item = model.selected {
                            Text(item.profile.direction).textSelection(.enabled)
                                .accessibilityIdentifier("benefit-direction")
                            Text("Wajib: " + item.profile.must.map(\.label).sorted().joined(separator: ", "))
                                .font(.footnote)
                            if !item.profile.prefer.isEmpty {
                                Text(
                                    "Diutamakan: " + item.profile.prefer.map(\.label).sorted().joined(separator: ", ")
                                )
                                .font(.footnote)
                            }
                        }
                        Button("Bandingkan empat metode") { model.compare() }
                            .disabled(model.busy).accessibilityIdentifier("benefit-compare")
                        if model.busy {
                            ProgressView(model.progress)
                            Button("Batalkan") { model.invalidate() }.accessibilityIdentifier("benefit-cancel")
                        }
                    }
                }
                if !model.error.isEmpty { Section("Informasi") { Text(model.error).foregroundStyle(.red) } }
                if let run = model.run {
                    BenefitResultSections(run: run)
                    Section("Bukti eksperimen") {
                        Button("Ekspor JSON dan Markdown") { model.export() }
                            .accessibilityIdentifier("benefit-export")
                        if let folder = model.exportFolder {
                            ShareLink("Bagikan JSON", item: folder.appendingPathComponent("run.json"))
                            ShareLink("Bagikan laporan", item: folder.appendingPathComponent("REPORT.md"))
                        }
                    }
                }
            }
            .navigationTitle("Nilai tambah E5")
            .toolbar {
                Button("Riwayat", systemImage: "clock.arrow.circlepath") { showingHistory = true }
                    .accessibilityIdentifier("benefit-history")
            }
            .sheet(isPresented: $showingHistory) {
                NavigationStack {
                    List(model.history) { run in
                        Button {
                            model.restore(run)
                            showingHistory = false
                        } label: {
                            VStack(alignment: .leading) {
                                Text(run.input.title)
                                Text(run.createdAt, style: .date).font(.caption)
                            }
                        }.accessibilityIdentifier("benefit-history-" + run.id.uuidString)
                    }.navigationTitle("Riwayat eksperimen")
                        .toolbar { Button("Tutup") { showingHistory = false } }
                }
            }
            .task { await model.load() }
        }
    }
}

private struct BenefitResultSections: View {
    let run: BenefitRun
    var body: some View {
        Section("Hasil") {
            Text(run.status).accessibilityIdentifier("benefit-result").textSelection(.enabled)
            Text(
                "Durasi run ini: \(run.totalSeconds, format: .number.precision(.fractionLength(3))) detik")
            Text(
                "Arahan teks adalah minat lunak. Kemiripan tidak membuktikan fasilitas, harga, suasana atau ketersediaan."
            )
            .font(.footnote).foregroundStyle(.secondary)
            if run.status == "no_verified_match" {
                Text("Belum ada area yang memenuhi semua syarat wajib dengan bukti yang tersedia.")
            }
            if run.status == "preference_review_required" {
                Text("Negasi atau syarat belum dikonfirmasi. Embeddings tidak menentukan artinya.")
            }
            if !run.error.isEmpty { Text(run.error).font(.footnote) }
        }
        if run.input.family != "safety", !run.rankings.isEmpty {
            Section("Penilaian kasus, bukan skor kepuasan") {
                Text(
                    "NDCG@3 memakai relevansi yang ditulis pengembang sebelum inferensi. Seri dihitung sebagai nilai harapan; urutan alfabet di layar tidak memberi keuntungan pada metrik."
                )
                .font(.footnote)
                ForEach(run.rankings) { ranking in
                    if let metrics = ranking.metrics {
                        LabeledContent(label(ranking.id), value: String(format: "%.3f", metrics.ndcgAt3))
                    }
                }
            }
        }
        ForEach(run.rankings) { ranking in
            Section(label(ranking.id)) {
                ForEach(Array(ranking.rows.prefix(3).enumerated()), id: \.element.id) { index, row in
                    if let candidate = run.catalog.candidates.first(where: { $0.id == row.id }),
                       let document = run.documents.first(where: { $0.id == row.id })
                    {
                        BenefitCandidateView(
                            position: index + 1, candidate: candidate,
                            document: document, sources: run.catalog.sources)
                    }
                }
            }
        }
    }
    private func label(_ id: String) -> String {
        switch id {
        case "category": "Kategori"
        case "lexical": "Kategori + kata kunci BM25"
        case "e5": "Kategori + E5"
        default: "Gabungan 60/40"
        }
    }
}

private struct BenefitCandidateView: View {
    let position: Int
    let candidate: QualityCandidate
    let document: BenefitDocument
    let sources: [QualitySource]
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(position). \(candidate.name)").font(.headline)
            Text(candidate.scope).font(.caption).foregroundStyle(.secondary)
            Button(expanded ? "Sembunyikan bukti" : "Lihat bukti") { expanded.toggle() }
                .accessibilityIdentifier("benefit-source-" + candidate.id)
            if expanded {
                Text(document.text).font(.subheadline).textSelection(.enabled)
                ForEach(sources.filter { document.sourceIDs.contains($0.id) }) { source in
                    Link(source.title, destination: source.url).font(.footnote)
                    Text("Diperiksa \(source.checkedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
