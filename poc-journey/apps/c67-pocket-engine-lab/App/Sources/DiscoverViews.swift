import SwiftUI
import MapKit
import PocketEngine

struct DiscoverScreen: View {
    @Bindable var model: PocketModel
    @State private var source: SearchSource = .catalog
    @State private var confirmsExpansion = false
    var body: some View {
        NavigationStack {
            List {
                Section("Rekomendasi untuk Anda") {
                    NavigationLink { AreaSelectionForm(model: model) } label: {
                        Label(model.areaLabel, systemImage: "location")
                    }
                    NavigationLink {
                        PreferencesForm(model: model)
                    } label: {
                        Label("Atur minat dan syarat", systemImage: "slider.horizontal.3")
                    }
                    Button("Cari rekomendasi", systemImage: "sparkle.magnifyingglass") { model.discover() }
                        .disabled(model.isDiscovering || model.area == nil)
                    if model.isDiscovering { ProgressView("Mencari tempat sesuai minat…") }
                    if model.area == nil { Text("Batas area belum tersedia. Muat ulang aplikasi.").foregroundStyle(.orange) }
                    if !model.discoveryNotice.isEmpty { Text(model.discoveryNotice).font(.caption).foregroundStyle(.secondary) }
                    if model.discoveryRan && !model.isDiscovering && model.recommendations.isEmpty {
                        Text("Baru \(model.eligibleCount) tempat yang cocok dan lolos syarat. Diperlukan minimal tiga.")
                        if !model.extendedArea { Button("Perluas area…") { confirmsExpansion = true } }
                        NavigationLink("Ubah syarat") { PreferencesForm(model: model) }
                    }
                    if !model.recommendations.isEmpty && !model.missingInterests.isEmpty {
                        Text("Minat belum terwakili — " + model.missingInterests.map(Interests.title).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(model.recommendations.prefix(12))) { assessment in VenueRow(assessment: assessment, model: model) }
                }
                Section {
                    Picker("Sumber pencarian", selection: $source) { ForEach(SearchSource.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    HStack {
                        TextField("Nama, wilayah, atau kegiatan", text: $model.query).submitLabel(.search).onSubmit { model.search(source) }
                        if model.isSearching { ProgressView() }
                        else { Button("Cari", systemImage: "magnifyingglass") { model.search(source) }.labelStyle(.iconOnly).disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                    }
                    if !model.query.isEmpty { Button("Bersihkan pencarian") { model.query = ""; model.clearSearch() } }
                    if !model.searchNotice.isEmpty { Text(model.searchNotice).font(.caption).foregroundStyle(.secondary) }
                }
                switch source {
                case .catalog:
                    let isSearch = model.localMatches != nil
                    let assessed = model.assessments
                    let places = isSearch ? assessed : []
                    Section(isSearch ? "Hasil pencarian katalog" : "Cari tempat berdasarkan nama") {
                        ForEach(Array(places.prefix(model.shownCount))) { assessment in VenueRow(assessment: assessment, model: model) }
                        if places.isEmpty {
                            if isSearch { ContentUnavailableView.search(text: model.query) }
                            else { Text("Masukkan nama untuk mencari tempat tertentu di katalog.").foregroundStyle(.secondary) }
                        }
                        if places.count > model.shownCount { Button("Lihat lainnya") { model.shownCount += 12 } }
                    }
                case .apple:
                    Section("Hasil Apple Maps · sesi ini") {
                        Text("Pilih titik awal, atau buka padanan katalog yang sudah cocok nama dan lokasinya.").font(.caption).foregroundStyle(.secondary)
                        ForEach(model.appleHits) { hit in AppleResultRow(hit: hit, model: model) }
                    }
                case .tomtom:
                    Section("Pembanding TomTom · melalui server") {
                        Text("Memerlukan konfigurasi TomTom pada server. Hasil provider hanya untuk sesi ini.").font(.caption).foregroundStyle(.secondary)
                        ForEach(model.providerHits) { hit in ProviderResultRow(hit: hit, model: model) }
                        if !model.providerNotice.isEmpty { Text(model.providerNotice).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Section { Text(model.catalog?.attribution ?? "Memuat katalog…").font(.caption2).foregroundStyle(.secondary) }
            }
            .navigationTitle("Jelajah")
            .onChange(of: source) { model.clearSearch() }
            .onChange(of: model.query) { model.clearSearch() }
            .confirmationDialog("Perluas pencarian hingga 5 km dari batas \(model.area?.name ?? "wilayah pilihan")?", isPresented: $confirmsExpansion) {
                Button("Perluas dan cari lagi") { model.extendedArea = true; model.discover() }
                Button("Tetap di wilayah pilihan", role: .cancel) {}
            }
        }
    }
}

struct VenueRow: View {
    let assessment: Assessment
    let model: PocketModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink { VenueDetail(venueID: assessment.id, model: model) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(assessment.venue.name).font(.headline)
                    Text(assessment.venue.branch).font(.subheadline).foregroundStyle(.secondary)
                    Label(assessment.eligible ? "Kandidat · skor \(assessment.score)" : "Syarat belum terpenuhi", systemImage: assessment.eligible ? "sparkles" : "exclamationmark.circle")
                        .font(.caption).foregroundStyle(assessment.eligible ? Color.teal : Color.orange)
                }
            }
            Text(assessment.reasons.first ?? "").font(.caption)
            let selected = model.choices.contains { $0.venueID == assessment.id }
            HStack {
                Button("Titik awal", systemImage: "location") { model.setOrigin(name: assessment.venue.name, point: assessment.venue.coordinate) }
                Spacer()
                Button(selected ? "Dipilih" : "Tambahkan", systemImage: selected ? "checkmark.circle.fill" : "plus.circle") { model.add(assessment.venue) }
                    .disabled(selected || !assessment.eligible)
            }.font(.subheadline).buttonStyle(.borderless)
        }.padding(.vertical, 7)
    }
}

struct AppleResultRow: View {
    let hit: PlaceHit
    let model: PocketModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hit.name).font(.headline)
            Text(hit.address).font(.caption).foregroundStyle(.secondary)
            Map(initialPosition: .region(.init(center: .init(latitude: hit.coordinate.latitude, longitude: hit.coordinate.longitude), span: .init(latitudeDelta: 0.006, longitudeDelta: 0.006)))) {
                Marker(hit.name, coordinate: .init(latitude: hit.coordinate.latitude, longitude: hit.coordinate.longitude))
            }.frame(height: 140).clipShape(.rect(cornerRadius: 12))
            Button("Jadikan titik awal", systemImage: "location") { model.setOrigin(name: hit.name, point: hit.coordinate) }.buttonStyle(.borderless)
            if let match = model.match(name: hit.name, coordinate: hit.coordinate) {
                NavigationLink("Periksa padanan katalog: " + match.name) { VenueDetail(venueID: match.id, model: model) }
            } else { Text("Belum ada satu padanan katalog yang pasti. Fakta cabang tidak digabung otomatis.").font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 5)
    }
}

struct ProviderResultRow: View {
    let hit: ProviderHit
    let model: PocketModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(hit.name).font(.headline)
            Text(hit.address).font(.caption).foregroundStyle(.secondary)
            Text(hit.hoursSummary).font(.caption)
            if let venue = model.match(name: hit.name, coordinate: hit.coordinate) {
                NavigationLink("Periksa padanan katalog") { VenueDetail(venueID: venue.id, model: model) }
            } else { Text("Padanan cabang belum pasti; informasi tetap terpisah dari katalog.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct PreferencesForm: View {
    @Bindable var model: PocketModel
    @State private var selected: Set<PreferenceTheme> = []
    @State private var showDetails = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("What sounds good today?").font(.largeTitle.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 105))], spacing: 12) {
                    ForEach(PreferenceTheme.allCases) { theme in
                        Button {
                            if !selected.insert(theme).inserted { selected.remove(theme) }
                        } label: {
                            Text(theme.title).frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(selected.contains(theme) ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                                .foregroundStyle(selected.contains(theme) ? Color.white : Color.primary)
                        }.buttonStyle(.plain).accessibilityIdentifier(theme.id)
                            .accessibilityAddTraits(selected.contains(theme) ? [.isSelected] : [])
                    }
                }
                Text("Pilih beberapa tema. Pada langkah berikutnya Anda dapat memperinci jenis tempat dan syarat kunjungan.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Next") {
                    let allowed = Set(selected.flatMap(\.categories))
                    model.profile.categories = Set(model.profile.categories.filter { allowed.contains(Interests.canonical($0)) })
                    model.profile.themes = selected
                    showDetails = true
                }.buttonStyle(.borderedProminent).disabled(selected.isEmpty).accessibilityIdentifier("preferences-next")
            }.padding()
        }
        .navigationTitle("Preferensi")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Skip") {
            // Skipping this question preserves existing detailed preferences and mandatory requirements.
            dismiss()
        }.accessibilityIdentifier("preferences-skip") } }
        .onAppear { selected = model.profile.themes }
        .navigationDestination(isPresented: $showDetails) { DetailedPreferencesForm(model: model) }
    }
}

struct AreaSelectionForm: View {
    @Bindable var model: PocketModel
    var body: some View {
        List {
            ForEach(VisitArea.bundledNames, id: \.self) { name in
                Button(name) { model.selectArea(name) }
                    .accessibilityIdentifier("area." + name)
            }
            Text("Pencarian dibatasi polygon wilayah yang dipilih. Perluasan 5 km hanya dilakukan setelah konfirmasi.")
                .font(.caption).foregroundStyle(.secondary)
            if let area = model.area, let url = URL(string: area.sourceURL) {
                Text(area.attribution).font(.caption)
                Link("Sumber batas wilayah", destination: url)
            }
        }.navigationTitle("Wilayah rekomendasi")
    }
}

struct DetailedPreferencesForm: View {
    @Bindable var model: PocketModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section {
                Text("Jenis yang dipilih di bawah mempersempit tema terkait. Syarat Wajib tetap harus didukung bukti.").font(.caption)
            }
            ForEach(Interests.groups) { group in
                Section(group.title) {
                    ForEach(group.keys, id: \.self) { category in
                        Toggle(Interests.title(category), isOn: Binding(get: {
                            model.profile.categories.contains(category)
                        }, set: { selected in
                            if selected { model.profile.categories.insert(category) }
                            else { model.profile.categories.remove(category) }
                        }))
                    }
                }
            }
            Section("Syarat kegiatan") {
                ForEach(Facet.activityOptions) { facet in
                    Picker(facet.title, selection: Binding(get: { model.profile.preferences[facet] ?? .neutral }, set: { model.profile.preferences[facet] = $0 })) {
                        ForEach(Preference.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
            Section { Text("Syarat wajib yang belum terbukti menahan kandidat. Atribut yang diketahui ada dan dipilih Hindari menggugurkan kandidat; atribut Hindari yang belum diketahui tetap ditampilkan sebagai ketidakpastian.").font(.caption) }
        }
        .navigationTitle("Minat & syarat")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Selesai") { dismiss() } } }
    }
}

struct VenueDetail: View {
    let venueID: String
    let model: PocketModel
    @State private var askingAI = false
    var body: some View {
        List {
            if let venue = model.venue(venueID) {
                let assessment = Recommender.assess(venue, profile: model.profile)
                Section {
                    Text(venue.name).font(.title2.bold())
                    Text([venue.branch, venue.address].joined(separator: " · ")).foregroundStyle(.secondary)
                    Map(initialPosition: .region(.init(center: .init(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude), span: .init(latitudeDelta: 0.008, longitudeDelta: 0.008)))) {
                        Marker(venue.name, coordinate: .init(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude))
                    }.frame(height: 210)
                }
                Section("Kecocokan") {
                    ForEach(model.aiReasons[venueID] ?? assessment.reasons, id: \.self) { Text($0) }
                    ForEach(assessment.blockers, id: \.self) { Label($0, systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
                    if !assessment.unknowns.isEmpty { Text("Belum diketahui: " + assessment.unknowns.joined(separator: ", ")).foregroundStyle(.secondary) }
                    Button("Pilih alasan utama dengan AI Apple", systemImage: "apple.intelligence") {
                        askingAI = true
                        Task { await model.explain(venue); askingAI = false }
                    }.disabled(askingAI)
                }
                Section("Bukti cabang") {
                    ForEach(evidenceFields(for: venue)) { facet in
                        EvidenceRow(venue: venue, facet: facet)
                    }
                }
                Section("Jam operasional") {
                    if let hours = venue.hours {
                        Label(hours.fresh(at: .now) ? "Bukti masih dalam masa berlaku" : "Bukti kedaluwarsa", systemImage: "clock")
                        Text(hours.quote)
                        Text("Diperiksa " + hours.checkedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                        if let url = URL(string: hours.sourceURL), url.scheme == "https" { Link("Sumber jam", destination: url) }
                    } else { Text("Belum tersedia. Untuk merencanakan kunjungan, konfirmasikan jam dan akses pada tujuan di tab Rencana.") }
                }
                Section {
                    Button("Tambahkan ke rencana", systemImage: "plus.circle") { model.add(venue) }
                        .disabled(!assessment.eligible || model.choices.contains { $0.venueID == venue.id })
                    Button("Jadikan titik awal", systemImage: "location") { model.setOrigin(name: venue.name, point: venue.coordinate) }
                }
                Section("Sumber identitas") {
                    Text(venue.license).font(.caption)
                    ForEach(venue.sourceURLs + venue.operatorURLs, id: \.self) { value in
                        if let url = URL(string: value), url.scheme == "https" { Link(value, destination: url).font(.caption) }
                    }
                }
            } else { ContentUnavailableView("Tempat tidak lagi ada pada katalog", systemImage: "mappin.slash") }
        }.navigationTitle("Detail tempat").navigationBarTitleDisplayMode(.inline)
    }

    private func evidenceFields(for venue: Venue) -> [Facet] {
        let categories = Set(venue.facts.map(\.field).filter(\.isCategoryLabel))
        return Facet.activityOptions + categories.sorted { $0.rawValue < $1.rawValue }
    }
}

struct EvidenceRow: View {
    let venue: Venue
    let facet: Facet
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            let status = venue.status(facet)
            LabeledContent(facet.title, value: status == .supported ? "Didukung" : (status == .contradicted ? "Bertentangan" : "Belum diketahui"))
            ForEach(Array(venue.facts.filter { $0.field == facet }.enumerated()), id: \.offset) { _, fact in
                Text(fact.value).font(.caption)
                Text("“" + fact.quote + "”").font(.caption).foregroundStyle(.secondary)
                Text(fact.fresh(at: .now) ? "Diperiksa: " + fact.checkedAt.formatted(date: .abbreviated, time: .omitted) : "Bukti kedaluwarsa").font(.caption2)
                if let url = URL(string: fact.sourceURL), url.scheme == "https" { Link("Lihat sumber", destination: url).font(.caption) }
            }
        }.padding(.vertical, 3)
    }
}
