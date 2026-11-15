import PreferenceLearning
import SwiftUI

struct PreferenceLabView: View {
    @State private var model = PreferenceLabModel()
    @State private var showResults = false
    @State private var confirmReset = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Tempat yang semakin sesuai dengan Anda").font(.title2.bold())
                    Text(
                        "Pilih minat atau sukai beberapa tempat. Bandingkan pencocokan kategori dengan makna deskripsinya."
                    )
                    Text(
                        "Eksperimen 02 · profil lokal + embeddings. Tidak membuat rute atau informasi jam kunjung."
                    ).font(.caption).foregroundStyle(.secondary)
                }
                Section("Sumber tempat") {
                    Picker(
                        "Katalog",
                        selection: Binding(
                            get: { model.catalogID }, set: { id in Task { await model.switchCatalog(id) } })
                    ) {
                        Text("MapKit langsung · Jakarta").tag("mapkit-live-v1")
                        Text("Sintetis · atribut ilustrasi").tag("synthetic-v1")
                        Text("MapKit · snapshot 5 Nov").tag("mapkit-snapshot-v1")
                    }.accessibilityIdentifier("preference-catalog")
                    if model.catalogID == "mapkit-live-v1" {
                        Text(
                            "Setiap perbandingan mencari tempat baru melalui MapKit di Jakarta. Profil diproses lokal; MapKit menerima query aktivitas pencarian."
                        ).font(.caption)
                        if ProcessInfo.processInfo.arguments.contains("--preference-live-fixture") {
                            Text("Mode uji UI · provider replay snapshot, tidak ada pencarian live.").font(
                                .caption
                            ).foregroundStyle(.orange)
                        }
                    } else if let catalog = model.catalog {
                        Text(
                            catalog.id == "synthetic-v1"
                                ? "Semua tempat dan atribut pada katalog ini fiktif. Koordinat hanya ilustrasi Jakarta."
                                : "Data nyata yang tersimpan dari pengujian 5 November. Tidak melakukan pencarian baru; fasilitas dan jam buka belum diketahui."
                        )
                        .font(.caption).foregroundStyle(.orange)
                    }
                }
                Section("Minat · opsional") {
                    PreferenceTagGrid(
                        selected: model.profile.interests, toggle: model.toggleInterest,
                        prefix: "prefer-interest")
                    TextField(
                        "Contoh: ingin ngopi sambil membaca", text: $model.profile.text, axis: .vertical
                    )
                    .lineLimit(2 ... 3).autocorrectionDisabled().accessibilityIdentifier("preference-text")
                    Text(
                        "Bahasa Indonesia atau Inggris · maksimal 400 karakter. Arahan ini hanya digunakan pada eksperimen lokal."
                    ).font(.caption).foregroundStyle(.secondary)
                    if model.profile.textNeedsAvoidControls {
                        Text(
                            "Larangan dalam teks belum diterapkan otomatis. Gunakan pilihan ‘Hal yang dihindari’ agar kategori tersebut dikeluarkan."
                        ).font(.caption).foregroundStyle(.orange)
                    }
                    DisclosureGroup("Hal yang dihindari") {
                        PreferenceTagGrid(
                            selected: model.profile.avoids, toggle: model.toggleAvoid, prefix: "prefer-avoid")
                        Text(
                            "Mengeluarkan kandidat dengan atribut tersebut yang diketahui. Atribut yang belum diketahui tetap belum terverifikasi."
                        ).font(.caption)
                    }
                }
                Section {
                    Button(
                        model.catalogID == "mapkit-live-v1"
                            ? "Cari dan rekomendasikan tempat" : "Bandingkan rekomendasi"
                    ) {
                        model.compare()
                        showResults = true
                    }.disabled(model.busy)
                        .accessibilityIdentifier("compare-preferences")
                    if model.catalogID == "mapkit-live-v1" {
                        Text(
                            "Pencarian dibatasi Jakarta. Jam buka, suasana dan fasilitas hanya diketahui jika ada data; tidak ada rute baru yang dihitung."
                        ).font(.caption).foregroundStyle(.secondary)
                    }
                    if model.busy {
                        ProgressView(model.progress)
                        Button("Batalkan") { model.cancel() }.accessibilityIdentifier(
                            "cancel-preference-comparison")
                    }
                    if !model.error.isEmpty { Text(model.error).font(.caption).foregroundStyle(.red) }
                    Text(
                        "Pilihan tersimpan otomatis di lab ini. Menyukai tempat yang sama berulang kali tidak menambah bobot."
                    ).font(.caption).foregroundStyle(.secondary)
                }
                if let catalog = model.catalog {
                    let learned = model.profile.learnedWeights(catalog: catalog)
                    Section("Profil dari pilihan Anda") {
                        if learned.isEmpty {
                            Text(
                                "Belum ada profil kategori. Anda boleh mulai dari teks atau menyukai satu tempat."
                            ).font(.caption)
                        } else {
                            Text(
                                learned.sorted { $0.key.rawValue < $1.key.rawValue }.map { $0.key.title }.joined(
                                    separator: ", "))
                            Text(
                                "Gabungan minat eksplisit dan atribut tempat yang disukai; bukan kesimpulan pasti tentang Anda."
                            ).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section("Sukai tempat · maksimal enam") {
                        if model.feedbackPlaces.isEmpty {
                            Text(
                                "Mulai dari minat atau arahan, lalu sukai tempat pada hasil pencarian. Pilihan akan tetap diingat pada pencarian berikutnya."
                            ).font(.caption)
                        }
                        ForEach(model.feedbackPlaces) { place in
                            PreferenceFeedbackRow(place: place, feedback: model.profile.feedback[place.id]) {
                                model.feedback(place, $0)
                            }
                        }
                    }
                }
                Section {
                    NavigationLink("Hasil, riwayat dan detail eksperimen") {
                        PreferenceExperimentView(model: model)
                    }
                    Button("Reset preferensi lab", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Preferensi lokal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        model.compare()
                        showResults = true
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .disabled(model.busy || model.catalog == nil)
                    .accessibilityLabel("Bandingkan preferensi").accessibilityIdentifier(
                        "compare-preferences-toolbar")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        PreferenceExperimentView(model: model)
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Riwayat dan eksperimen preferensi").accessibilityIdentifier(
                        "preference-experiments")
                }
            }
            .navigationDestination(isPresented: $showResults) { PreferenceResultsView(model: model) }
            .task { await model.load() }
            .confirmationDialog(
                "Reset pilihan pada katalog ini? Riwayat eksperimen tetap tersimpan.",
                isPresented: $confirmReset
            ) {
                Button("Reset preferensi", role: .destructive) { model.reset() }
            }
        }
    }
}
private struct PreferenceTagGrid: View {
    let selected: Set<PreferenceTag>
    let toggle: (PreferenceTag) -> Void
    let prefix: String
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
            ForEach(PreferenceTag.allCases) { tag in
                Button {
                    toggle(tag)
                } label: {
                    Label(tag.title, systemImage: selected.contains(tag) ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.bordered).accessibilityIdentifier("\(prefix)-\(tag.rawValue)")
            }
        }
    }
}
private struct PreferenceFeedbackRow: View {
    let place: PreferencePlace
    let feedback: PlaceFeedback?
    let choose: (PlaceFeedback) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(place.name).font(.headline)
            Text(place.description).font(.footnote)
            HStack {
                Button {
                    choose(.liked)
                } label: {
                    Label("Suka", systemImage: feedback == .liked ? "heart.fill" : "heart")
                }
                .accessibilityIdentifier("like-\(place.id)")
                Button {
                    choose(.disliked)
                } label: {
                    Label(
                        "Tidak tertarik",
                        systemImage: feedback == .disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                }
                .accessibilityIdentifier("dislike-\(place.id)")
            }.buttonStyle(.bordered)
            if feedback != nil {
                Text("Ketuk pilihan yang sama untuk membatalkan.").font(.caption).foregroundStyle(
                    .secondary)
            }
        }.padding(.vertical, 4)
    }
}
private struct PreferenceResultsView: View {
    @Bindable var model: PreferenceLabModel
    var body: some View {
        List {
            if model.busy {
                ProgressView(model.progress)
                Button("Batalkan") { model.cancel() }.accessibilityIdentifier("cancel-live-preferences")
            } else if let run = model.run {
                Section {
                    Text(run.catalog.title).font(.headline)
                        .accessibilityIdentifier("preference-result-title")
                    Text(
                        "\(run.elapsedSeconds, specifier: "%.2f") detik · kandidat yang sama untuk dua metode"
                    ).font(.caption)
                    Text(
                        run.status == "general_not_personalized"
                            ? "Belum ada sinyal kesukaan. Daftar ini masih umum, belum personal."
                            : "Usulan untuk ditinjau. Skor kemiripan bukan persentase kecocokan atau jaminan kualitas tempat."
                    )
                    if run.profile.textNeedsAvoidControls {
                        Text("Larangan dalam teks membutuhkan pilihan kategori eksplisit.").foregroundStyle(
                            .orange)
                    }
                    if let search = run.search {
                        Text("\(search.provider) · \(search.fetchedAt)").font(.caption)
                            .accessibilityIdentifier("live-search-provenance")
                        Text(
                            "\(search.receivedCount) hasil diterima · \(search.filteredCount) kandidat unik di Jakarta"
                        ).font(.caption)
                        Text("Query: " + search.choices.map(\.query).joined(separator: "; ")).font(.caption)
                        ForEach(search.errors, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                    }
                    if run.status == "search_failed" || run.status == "search_empty" {
                        Text(
                            run.status == "search_failed"
                                ? "Pencarian belum berhasil. Coba kembali; hasil lama tidak dipakai sebagai pencarian baru."
                                : "Tidak ditemukan kandidat di wilayah Jakarta. Ubah preferensi atau coba kembali."
                        )
                        .accessibilityIdentifier("live-search-empty-state")
                    }
                }
                Section("Pembanding · kategori") {
                    ForEach(run.categoryRanking.prefix(3)) { row in
                        PreferenceRankingRow(
                            row: row, semantic: false, feedback: model.profile.feedback[row.id]
                        ) { model.feedback(row.place, $0) }
                    }
                    if run.categoryRanking.isEmpty { Text("Tidak ada kandidat setelah filter pilihan Anda.") }
                    if run.categoryRanking.first?.score == 0 {
                        Text("Belum ada kategori yang cocok; urutan pembanding ini umum.").font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Section("Eksperimen · makna deskripsi") {
                    if run.status == "semantic_completed" {
                        ForEach(run.semanticRanking.prefix(3)) { row in
                            PreferenceRankingRow(
                                row: row, semantic: true, feedback: model.profile.feedback[row.id]
                            ) { model.feedback(row.place, $0) }
                        }
                    } else {
                        Text(
                            run.status == "general_not_personalized"
                                ? "Tambahkan satu minat, arahan atau tempat disukai untuk mencoba personalisasi."
                                : "Embedding belum memberikan hasil. Pembanding kategori tetap tersedia.")
                        if !run.error.isEmpty { Text(run.error).font(.caption).foregroundStyle(.orange) }
                    }
                }
                Section {
                    Text(
                        "Tempat disukai/tidak diminati tidak direkomendasikan ulang. Hal yang dihindari difilter berdasarkan atribut yang tersedia."
                    ).font(.caption)
                    Text(
                        "Usulan kecocokan belum membuktikan pengalaman lapangan. Tidak ada rute atau jam kunjung yang dihasilkan."
                    ).font(.caption)
                    NavigationLink("Sumber, ekspor dan riwayat") { PreferenceExperimentView(model: model) }
                }
            } else {
                ContentUnavailableView(
                    "Preferensi berubah", systemImage: "heart.text.clipboard",
                    description: Text("Kembali dan bandingkan ulang dengan pilihan terbaru."))
            }
            if model.catalogID == "mapkit-live-v1" && !model.busy {
                Button("Cari ulang dengan preferensi terbaru") { model.compare() }
                    .accessibilityIdentifier("refresh-live-preferences")
            }
            if !model.error.isEmpty { Text(model.error).foregroundStyle(.red) }
        }.navigationTitle("Perbandingan")
    }
}
private struct PreferenceRankingRow: View {
    let row: RankedPreferencePlace
    let semantic: Bool
    let feedback: PlaceFeedback?
    let choose: (PlaceFeedback) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.place.name).font(.headline)
            Text(row.place.description).font(.footnote)
            if let address = row.place.address, !address.isEmpty { Text(address).font(.caption) }
            Text(
                semantic
                    ? "Kemiripan relatif: \(row.score.formatted(.number.precision(.fractionLength(3))))"
                    : "Bobot kategori: \(row.score.formatted(.number.precision(.fractionLength(2))))"
            ).font(.caption.monospaced())
            if !row.matchingTags.isEmpty {
                Text("Atribut yang bertemu: " + row.matchingTags.map(\.title).joined(separator: ", ")).font(
                    .caption)
            }
            DisclosureGroup("Sumber dan ketidakpastian") {
                Text(row.place.source + " · " + row.place.observedAt).font(.caption)
                Text("Koordinat \(row.place.latitude.formatted()), \(row.place.longitude.formatted())")
                    .font(.caption)
                Text("Belum diketahui: " + row.place.unknowns.joined(separator: ", ")).font(.caption)
            }
            HStack {
                Button {
                    choose(.liked)
                } label: {
                    Label("Suka", systemImage: feedback == .liked ? "heart.fill" : "heart")
                }
                .accessibilityIdentifier("result-like-\(row.id)")
                Button {
                    choose(.disliked)
                } label: {
                    Label("Tidak tertarik", systemImage: "hand.thumbsdown")
                }
                .accessibilityIdentifier("result-dislike-\(row.id)")
            }.buttonStyle(.bordered)
        }.padding(.vertical, 4)
    }
}
private struct PreferenceExperimentView: View {
    @Bindable var model: PreferenceLabModel
    var body: some View {
        List {
            Section("Tentang eksperimen 02") {
                Text(
                    "E5 multilingual kecil + ONNX Runtime. Inferensi lokal menggunakan model yang dibundel. Mode MapKit langsung mengirim query aktivitas ke layanan peta; profil lengkap tidak dikirim ke API AI."
                )
                Text(model.modelStatus).font(.caption)
                Text(
                    "Eksperimen 01 Foundation Models tetap tersedia pada tab sebelumnya. Profil dan riwayatnya terpisah."
                ).font(.caption)
                Button("Jalankan kategori tanpa embedding") { model.compare(baselineOnly: true) }.disabled(
                    model.busy)
            }
            if let run = model.run {
                Section("Hasil terakhir") {
                    NavigationLink("Buka hasil ini") { PreferenceResultsView(model: model) }
                        .accessibilityIdentifier("open-preference-result")
                    Text(run.id).font(.caption.monospaced())
                    Text(run.status + " · " + run.createdAt).font(.caption)
                    if let info = run.embedding {
                        Text(info.model + "\n" + info.runtime + "\n" + info.revision).font(
                            .caption.monospaced())
                    }
                    Text(run.catalog.provenance).font(.caption)
                    if let search = run.search {
                        DisclosureGroup("Pencarian MapKit dan batasnya") {
                            ForEach(search.choices, id: \.query) { item in
                                Text("\(item.query) · \(item.basis)").font(.caption)
                            }
                            Text(
                                "Pencarian \(search.searchSeconds, specifier: "%.2f") s · ranking \(search.rankingSeconds, specifier: "%.2f") s"
                            ).font(.caption)
                            ForEach(search.notices, id: \.self) { Text($0).font(.caption) }
                            ForEach(search.errors, id: \.self) {
                                Text($0).font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                    DisclosureGroup("Profil dan query") {
                        Text(run.query.isEmpty ? "Tidak ada sinyal personal" : run.query).font(.caption)
                            .textSelection(.enabled)
                    }
                    Button("Siapkan ekspor") { model.export() }.accessibilityIdentifier(
                        "export-preference-run")
                    if let url = model.exportURL {
                        ShareLink("Bagikan JSON", item: url)
                        ShareLink(
                            "Bagikan Markdown",
                            item: url.deletingLastPathComponent().appendingPathComponent("REPORT.md"))
                    }
                }
            }
            Section("Riwayat preferensi lokal") {
                ForEach(model.history) { run in
                    Button("\(run.createdAt) · \(run.catalog.title)") { model.restore(run) }
                }
            }
            Section("Batas operasional Jakarta") {
                Text("Mask geoBoundaries/OSM vintage 2017 · ODbL 1.0; bukan batas survei terbaru.").font(
                    .caption)
                Link("geoBoundaries", destination: URL(string: "https://www.geoboundaries.org/")!)
                Link(
                    "OpenStreetMap contributors",
                    destination: URL(string: "https://www.openstreetmap.org/copyright")!)
            }
        }.navigationTitle("Eksperimen preferensi")
    }
}
