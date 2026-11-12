import SwiftUI
import PreferenceCore
import PreferenceLearning

private struct Connection: Decodable { var baseURL: String; var token: String }
private struct SavedDiscoveryContext: Codable {
    var area: String; var checkVisitTime: Bool; var visitDate: Date; var checkDuration: Bool; var visitMinutes: Int
    var catalogEnabled: Bool?
}
private struct SavedSession: Codable {
    var state: PreferenceState
    var history: [PreferenceState]
    var context: SavedDiscoveryContext?
    var advisorProvider: String?
}
struct PlaceResults: Decodable {
    struct Place: Decodable, Identifiable {
        struct Name: Decodable { var text: String? }
        var id: String; var displayName: Name?; var formattedAddress: String?; var googleMapsUri: String?
    }
    var query: String; var places: [Place]; var notice: String
}
@MainActor @Observable final class LabModel {
    var state = PreferenceState()
    var questions: [Clarification] = []
    var examples: [Experience] = []
    var ready = false
    var screen = "interests"
    var mode = "rules"
    var visibleLimit = 12
    var illustrationMode = false
    var question: Clarification?
    var status = ""
    var busy = false
    var showConsent = false
    var showSummary = false
    var showExperiments = false
    var placeResults: PlaceResults?
    var placeBusy = false
    var area = "Jakarta Pusat"
    var liveResults: LivePlaceResponse?
    var catalogEnabled = true
    var catalogResults: CatalogResponse?
    var catalogRequestSeconds: Double?
    var catalogNames: [String: String] = [:]
    var knownPlaces: [String: LivePlace] = [:]
    var checkVisitTime = false
    var visitDate = Date.now.addingTimeInterval(86400)
    var checkDuration = false
    var visitMinutes = 60
    var error: String?
    var semantic: [String: Double] = [:]
    var embeddingStatus = "Belum dimuat"
    var auditStatus = ""
    var lastDecision: AdvisorDecision?
    private var history: [PreferenceState] = []
    private let embedding = E5Embedding()
    private let storage: URL
    private var adviceTask: Task<Void, Never>?
    private var adviceID: UUID?
    private var liveTask: Task<Void, Never>?
    private var liveID: UUID?
    init() {
        let args = ProcessInfo.processInfo.arguments
        let illustrations = args.contains("--illustrations") || args.contains("--e5-audit")
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let name = args.contains("--ui-test") ? (illustrations ? "preference-ui-test.json" : "preference-live-ui-test.json") : "preference-state.json"
        storage = base.appendingPathComponent(name)
        illustrationMode = illustrations
        if args.contains("--reset-state") {
            try? FileManager.default.removeItem(at: storage)
            try? FileManager.default.removeItem(at: base.appendingPathComponent("PreferenceLab/catalog-client-timing.json"))
        }
        if let d = try? Data(contentsOf: storage) {
            if let session = try? JSONDecoder().decode(SavedSession.self, from: d), session.state.version == 1 {
                state = session.state; history = session.history
                if session.advisorProvider != "luna-provider.example" {
                    state.aiConsent = false
                    for index in history.indices { history[index].aiConsent = false }
                }
                if let c = session.context, ["Jakarta Pusat", "Jakarta Selatan", "Jakarta Utara", "Jakarta Barat", "Jakarta Timur"].contains(c.area), (1 ... 480).contains(c.visitMinutes) {
                    area = c.area; checkVisitTime = c.checkVisitTime; visitDate = c.visitDate; checkDuration = c.checkDuration; visitMinutes = c.visitMinutes
                    catalogEnabled = c.catalogEnabled ?? true
                }
            } else if let old = try? JSONDecoder().decode(PreferenceState.self, from: d), old.version == 1 { state = old; state.aiConsent = false }
            ready = !state.interests.isEmpty; screen = ready ? "experiences" : "interests"
        }
        do {
            questions = try LabData.questions()
            var seen = Set<String>()
            examples = try LabData.cases().flatMap(\.candidates).filter { seen.insert($0.id).inserted }
        } catch { self.error = error.localizedDescription }
        if args.contains("--broad") { mode = "broad" }
        if args.contains("--google-places") { catalogEnabled = false }
        refreshQuestion()
    }
    var rows: [RankedExperience] { PreferenceEngine.rank(examples, state: state, semantic: semantic) }
    var eligible: [Clarification] {
        illustrationMode ? PreferenceEngine.eligible(questions, items: examples, state: state) : PreferenceEngine.intentQuestions(questions, state: state)
    }
    var summary: [String] { PreferenceEngine.summary(state, questions: questions) }
    func save() {
        let context = SavedDiscoveryContext(area: area, checkVisitTime: checkVisitTime, visitDate: visitDate, checkDuration: checkDuration, visitMinutes: visitMinutes, catalogEnabled: catalogEnabled)
        do { try JSONEncoder().encode(SavedSession(state: state, history: Array(history.suffix(20)), context: context, advisorProvider: "luna-provider.example")).write(to: storage, options: [.atomic, .completeFileProtectionUnlessOpen]) }
        catch { self.error = "Pilihan belum tersimpan. Coba lagi." }
    }
    func toggleInterest(_ id: String) {
        adviceTask?.cancel(); history.append(state)
        if state.interests.contains(id) { state.interests.removeAll { $0 == id } } else { state.interests.append(id) }
        let allowed = Set(questions.filter { !Set($0.interests).isDisjoint(with: state.interests) }.map(\.axis))
        state.trip = state.trip.filter { allowed.contains($0.key) }
        state.reusable = state.reusable.filter { allowed.contains($0.key) }
        state.asked = []; state.skipped = []; state.revision += 1; save(); semantic = [:]; invalidatePlaces()
    }
    func begin() {
        ready = true; screen = "experiences"; save(); refreshQuestion()
        if illustrationMode { Task { await updateEmbedding() } }
        else if question == nil { discover() }
    }
    func refreshQuestion() { question = mode == "broad" ? nil : eligible.first }
    func answer(_ q: Clarification, _ id: String) {
        adviceTask?.cancel(); busy = false; history.append(state)
        do {
            try state.answer(q, choiceID: id); save(); status = "Pilihan diperbarui"; refreshQuestion()
            if illustrationMode { Task { await updateEmbedding() } } else { invalidatePlaces(); discover(debounce: true) }
        }
        catch { self.error = error.localizedDescription }
    }
    func skip() {
        guard let q = question else { return }; adviceTask?.cancel(); busy = false
        history.append(state); state.skip(q.id); save(); question = nil; status = "Bisa diperjelas nanti"
        if !illustrationMode { invalidatePlaces(); discover() }
    }
    func undo() {
        guard let prior = history.popLast() else { return }; adviceTask?.cancel(); busy = false
        state = prior; state.revision += 1; save(); semantic = [:]; refreshQuestion(); invalidatePlaces()
        if !illustrationMode { discover(debounce: true) }
    }
    func keep(_ id: String) {
        history.append(state)
        if state.savedIDs.contains(id) { state.savedIDs.removeAll { $0 == id } } else { state.savedIDs.append(id) }
        state.revision += 1; save()
    }
    func newTrip() { adviceTask?.cancel(); history.append(state); state.newTrip(); checkVisitTime = false; checkDuration = false; save(); semantic = [:]; placeResults = nil; invalidatePlaces(); refreshQuestion() }
    func remember(_ axis: String) { history.append(state); state.remember(axis); save() }
    func toggleMust(_ axis: String) {
        guard var v = state.trip[axis] ?? state.reusable[axis] else { return }
        history.append(state); v.must.toggle(); state.trip[axis] = v; state.revision += 1; save(); invalidatePlaces()
        if !illustrationMode { discover(debounce: true) }
    }
    func remove(_ axis: String) {
        history.append(state); state.trip[axis] = nil; state.reusable[axis] = nil
        if let q = questions.first(where: { $0.axis == axis }) { state.asked.removeAll { $0 == q.id }; state.skipped.removeAll { $0 == q.id } }
        state.revision += 1; save(); refreshQuestion(); invalidatePlaces()
    }
    func requestAdvice() {
        guard state.aiConsent else { showConsent = true; return }
        guard !eligible.isEmpty, !busy else { status = "Tidak ada pertanyaan tambahan yang berguna"; return }
        let snapshot = state, input = AdvisorRequest(state: state, questions: eligible)
        busy = true; status = "Memilih pertanyaan yang relevan…"
        adviceID = input.requestID
        adviceTask = Task { @MainActor in
            defer { if adviceID == input.requestID { busy = false; adviceID = nil } }
            do {
                let decision: AdvisorDecision = try await api("/advisor", input, as: AdvisorDecision.self, timeout: 35)
                try Task.checkCancellation(); try decision.validate(for: input, current: state)
                lastDecision = decision; mode = "adaptive"
                question = eligible.first { $0.id == decision.questionID }
                status = decision.mode == "llm" ? "Klarifikasi siap" : "Klarifikasi lokal siap; AI belum tersedia"
            } catch is CancellationError { }
            catch {
                guard state.revision == snapshot.revision else { return }
                refreshQuestion(); status = "AI belum tersedia. Pilihan lokal tetap bisa digunakan."
            }
        }
    }
    func api<T: Encodable, R: Decodable>(_ path: String, _ body: T, as: R.Type, timeout: Double = 12) async throws -> R {
        guard let url = Bundle.main.url(forResource: "RunConfig", withExtension: "json") else { throw LabError.invalid("Service connection missing") }
        let config = try JSONDecoder().decode(Connection.self, from: Data(contentsOf: url))
        var r = URLRequest(url: URL(string: config.baseURL + path)!); r.httpMethod = "POST"; r.timeoutInterval = timeout
        r.setValue("Bearer " + config.token, forHTTPHeaderField: "Authorization"); r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: r)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LabError.invalid("Service unavailable") }
        return try JSONDecoder().decode(R.self, from: data)
    }
    func updateEmbedding() async {
        guard illustrationMode else { return }
        let snapshot = state
        do {
            let query = try await embedding.encode(PreferenceEngine.english(snapshot, questions: questions), query: true)
            var scores: [String: Double] = [:]
            for item in examples where !Set(item.interests).isDisjoint(with: snapshot.interests) {
                let vector = try await embedding.encode(item.english, query: false)
                scores[item.id] = Double(zip(query, vector).reduce(Float(0)) { $0 + $1.0 * $1.1 })
            }
            guard snapshot.revision == state.revision else { return }
            semantic = scores; embeddingStatus = "E5 English · lokal"
        } catch { embeddingStatus = "Pencocokan aturan lokal" }
    }
    func invalidatePlaces() { liveTask?.cancel(); liveID = nil; placeBusy = false; liveResults = nil; catalogResults = nil }
    func discover(more: Bool = false, debounce: Bool = false) {
        if catalogEnabled && !illustrationMode { discoverCatalog(debounce: debounce); return }
        guard !state.interests.isEmpty, !more || !(liveResults?.pageTokens.isEmpty ?? true) else { return }
        liveTask?.cancel()
        let id = UUID(); liveID = id; placeBusy = true; error = nil
        let input = LivePlaceRequest(state: state, area: area, visitAt: checkVisitTime ? visitDate : nil,
                                     durationMinutes: checkVisitTime && checkDuration ? visitMinutes : nil,
                                     pageTokens: more ? liveResults?.pageTokens : nil)
        liveTask = Task { @MainActor in
            defer { if liveID == id { placeBusy = false } }
            do {
                if debounce { try await Task.sleep(for: .milliseconds(650)) }
                let result: LivePlaceResponse = try await api("/discover", input, as: LivePlaceResponse.self, timeout: 22)
                try Task.checkCancellation()
                guard liveID == id, result.requestID == input.requestID else { return }
                if more, liveResults != nil { liveResults?.append(result) } else { liveResults = result }
                for place in result.places { knownPlaces[place.id] = place }
            } catch is CancellationError { }
            catch {
                guard liveID == id else { return }
                self.error = "Tempat belum berhasil dimuat. Pilihan Anda tetap tersimpan; coba lagi."
            }
        }
    }
    func discoverCatalog(debounce: Bool = false) {
        guard !state.interests.isEmpty else { return }
        liveTask?.cancel()
        let id = UUID(); liveID = id; placeBusy = true; error = nil
        let began = ProcessInfo.processInfo.systemUptime
        let input = LivePlaceRequest(state: state, area: area, visitAt: checkVisitTime ? visitDate : nil,
                                     durationMinutes: checkVisitTime && checkDuration ? visitMinutes : nil)
        liveTask = Task { @MainActor in
            defer { if liveID == id { placeBusy = false } }
            do {
                if debounce { try await Task.sleep(for: .milliseconds(350)) }
                let result = try await api("/catalog/discover", input, as: CatalogResponse.self)
                try Task.checkCancellation()
                guard liveID == id, result.requestID == input.requestID, result.revision == input.revision else { return }
                catalogResults = result
                catalogRequestSeconds = ProcessInfo.processInfo.systemUptime - began
                if ProcessInfo.processInfo.arguments.contains("--ui-test"), let seconds = catalogRequestSeconds {
                    let folder = storage.deletingLastPathComponent().appendingPathComponent("PreferenceLab")
                    let file = folder.appendingPathComponent("catalog-client-timing.json")
                    var previous: [[String: Any]] = []
                    if let bytes = try? Data(contentsOf: file),
                       let rows = try? JSONSerialization.jsonObject(with: bytes) as? [[String: Any]] {
                        previous = rows
                    }
                    let observation: [String: Any] = ["requestID": input.requestID.uuidString, "runID": result.runID,
                                                      "clientSeconds": seconds, "serverSeconds": result.seconds, "includesDebounce": debounce,
                                                      "count": result.places.count, "timingMeaning": "Request until model state update, excluding frame rendering"]
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    if let bytes = try? JSONSerialization.data(withJSONObject: Array((previous + [observation]).suffix(20)), options: [.prettyPrinted, .sortedKeys]) {
                        try? bytes.write(to: file, options: .atomic)
                    }
                }
                for place in result.places { catalogNames[place.id] = place.name }
            } catch is CancellationError { }
            catch {
                guard liveID == id else { return }
                self.error = "Katalog belum berhasil dimuat. Pilihan Anda tetap tersimpan."
            }
        }
    }
    func searchPlaces() {
        let selected = state.values.sorted { $0.key < $1.key }.first
        let axis = selected?.key ?? "readingActivity", value = selected?.value.value ?? "onsite"
        placeBusy = true; error = nil
        struct Query: Encodable { var area: String; var axis: String; var value: String }
        let input = Query(area: area, axis: axis, value: value)
        Task { @MainActor in
            defer { placeBusy = false }
            do { placeResults = try await api("/places", input, as: PlaceResults.self) }
            catch { self.error = "Pencarian tempat belum tersedia. Preferensi Anda tetap tersimpan." }
        }
    }
    func exportIntent() -> String {
        struct Export: Encodable { var version: Int; var interests: [String]; var trip: [String: PreferenceValue]; var reusable: [String: PreferenceValue] }
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? String(decoding: e.encode(Export(version: 1, interests: state.interests, trip: state.trip, reusable: state.reusable)), as: UTF8.self)) ?? "{}"
    }
    func runEmbeddingAudit() async {
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        auditStatus = "E5 audit running"
        do {
            let start = Date(); let metadata = try await embedding.metadata(); let cold = Date().timeIntervalSince(start)
            let qs = questions, cases = try LabData.cases()
            var states: [String: PreferenceState] = [:]
            for item in cases {
                var initial = PreferenceState(); initial.interests = item.interests
                states[PreferenceEngine.english(initial, questions: qs)] = initial
                for q in PreferenceEngine.eligible(qs, items: item.candidates, state: initial) {
                    for c in q.choices { var s = initial; try s.answer(q, choiceID: c.id); states[PreferenceEngine.english(s, questions: qs)] = s }
                }
            }
            let encodingStart = Date()
            var passages: [String: [Float]] = [:]
            for item in examples { passages[item.id] = try await embedding.encode(item.english, query: false) }
            var output: [String: [String: Double]] = [:]
            for (text, s) in states.sorted(by: { $0.key < $1.key }) {
                let query = try await embedding.encode(text, query: true)
                var scores: [String: Double] = [:]
                for item in examples where !Set(item.interests).isDisjoint(with: s.interests) {
                    scores[item.id] = Double(zip(query, passages[item.id]!).reduce(Float(0)) { $0 + $1.0 * $1.1 })
                }
                output[text] = scores
            }
            let warmStart = Date()
            for text in states.keys { _ = try await embedding.encode(text, query: true) }
            let audit: [String: Any] = ["model": metadata.model, "revision": E5Embedding.revision, "representation": "en-v2-owned-activities",
                                        "scoresByQuery": output, "coldSeconds": cold, "encodingSeconds": Date().timeIntervalSince(encodingStart),
                                        "warmCachedQuerySeconds": Date().timeIntervalSince(warmStart), "queries": output.count, "passages": passages.count,
                                        "runtime": metadata.runtime, "dimensions": metadata.dimensions]
            let folder = storage.deletingLastPathComponent().appendingPathComponent("PreferenceLab")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: audit, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("e5-audit.json"), options: .atomic)
            auditStatus = "E5 audit complete"
        } catch { auditStatus = "E5 audit failed: " + error.localizedDescription }
    }
}

@main struct C67PreferenceLabApp: App {
    @State private var model = LabModel()
    var body: some Scene {
        WindowGroup {
            LabView(model: model)
                .task {
                    if ProcessInfo.processInfo.arguments.contains("--e5-audit") { await model.runEmbeddingAudit() }
                    else if model.ready && !model.illustrationMode && model.question == nil { model.discover() }
                }
        }
    }
}
private struct LabView: View {
    @Bindable var model: LabModel
    private let columns = [GridItem(.adaptive(minimum: 135))]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if model.screen == "interests" { onboarding }
                    else { experiences }
                    if !model.auditStatus.isEmpty { Text(model.auditStatus).accessibilityIdentifier("audit-status") }
                    if let error = model.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("lab-error") }
                }.padding(22)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(model.screen == "interests" ? "Apa yang Anda suka?" : model.illustrationMode ? "Pengalaman untuk Anda" : "Tempat untuk Anda")
            .toolbar {
                if model.screen != "interests" {
                    ToolbarItem(placement: .topBarLeading) { Button("Minat") { model.screen = "interests" } }
                    ToolbarItem(placement: .topBarTrailing) { Button("Pilihan saya") { model.showSummary = true }.accessibilityIdentifier("open-summary") }
                }
                ToolbarItem(placement: .bottomBar) { Button("Eksperimen") { model.showExperiments = true }.font(.footnote) }
            }
            .sheet(isPresented: $model.showSummary) { summary }
            .sheet(isPresented: $model.showExperiments) { experiments }
            .alert("Gunakan bantuan AI?", isPresented: $model.showConsent) {
                Button("Gunakan AI") { model.state.aiConsent = true; model.save(); model.requestAdvice() }
                Button("Tetap lokal", role: .cancel) { }
            } message: {
                Text("Pilihan minat dan kegiatan dikirim ke luna-provider.example dan penyedia model di belakangnya untuk memilih klarifikasi. Data dapat disimpan penyedia. Nama, lokasi persis, dan riwayat lengkap tidak dikirim. Anda tetap bisa menggunakan pilihan lokal.")
            }
        }.tint(.indigo)
    }
    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Pilih minat sebagai awal. Perjelas kegiatannya, lalu temukan tempat asli.").foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(PreferenceEngine.interests, id: \.0) { id, label in
                    Button { model.toggleInterest(id) } label: {
                        HStack { Text(label); Spacer(); if model.state.interests.contains(id) { Image(systemName: "checkmark.circle.fill") } }
                            .padding().background(model.state.interests.contains(id) ? Color.indigo.opacity(0.15) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain).accessibilityIdentifier("interest-" + id)
                        .accessibilityAddTraits(model.state.interests.contains(id) ? .isSelected : [])
                }
            }
            Text("Ritme perjalanan").font(.headline)
            Picker("Ritme perjalanan", selection: $model.state.pace) {
                Text("Santai").tag("relaxed"); Text("Seimbang").tag("balanced"); Text("Aktif").tag("active")
            }.pickerStyle(.segmented).onChange(of: model.state.pace) { _, _ in model.state.revision += 1; model.save() }
            Button(model.illustrationMode ? "Jelajahi pengalaman" : "Temukan tempat") { model.begin() }.buttonStyle(.borderedProminent)
                .disabled(model.state.interests.isEmpty).accessibilityIdentifier("begin-exploring")
        }
    }
    private var experiences: some View {
        VStack(alignment: .leading, spacing: 20) {
            if model.illustrationMode {
                Text("Contoh pengalaman ilustratif").font(.subheadline).foregroundStyle(.secondary)
                Text("Perjelas maksud Anda melalui pilihan singkat. Contoh ini belum merupakan rekomendasi tempat nyata.").foregroundStyle(.secondary)
            } else {
                Picker("Sumber tempat", selection: $model.catalogEnabled) {
                    Text("Katalog kegiatan").tag(true)
                    Text("Pencarian Google").tag(false)
                }.pickerStyle(.segmented).accessibilityIdentifier("place-source")
                    .onChange(of: model.catalogEnabled) { _, _ in model.save(); model.invalidatePlaces(); model.discover() }
                HStack {
                    Text("Di sekitar").foregroundStyle(.secondary)
                    Picker("Area", selection: $model.area) {
                        ForEach(["Jakarta Pusat", "Jakarta Selatan", "Jakarta Utara", "Jakarta Barat", "Jakarta Timur"], id: \.self) { Text($0) }
                    }.onChange(of: model.area) { _, _ in model.save(); model.invalidatePlaces(); model.discover(debounce: true) }
                }
            }
            if let q = model.question {
                VStack(alignment: .leading, spacing: 12) {
                    Text(q.text).font(.title3.bold()).accessibilityIdentifier("clarification-title")
                    ForEach(q.choices) { c in
                        Button(c.label) { model.answer(q, c.id) }.buttonStyle(.bordered).accessibilityIdentifier("choice-" + c.id)
                    }
                    Button("Belum tahu · lewati") { model.skip() }.font(.subheadline).accessibilityIdentifier("skip-question")
                }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
            }
            if !model.summary.isEmpty {
                ForEach(model.summary, id: \.self) { Text($0).font(.subheadline).accessibilityIdentifier("preference-summary") }
            }
            HStack {
                Button("Bantu perjelas dengan AI") { model.requestAdvice() }.disabled(model.busy || model.eligible.isEmpty).accessibilityIdentifier("ask-ai")
                if model.busy { ProgressView() }
            }
            if !model.status.isEmpty { Text(model.status).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("advisor-status") }
            Text("\(model.state.savedIDs.count) pilihan disimpan").font(.subheadline).accessibilityIdentifier("saved-count")
            if !model.illustrationMode {
                if model.catalogEnabled { CatalogPlaceList(model: model) }
                else { LivePlaceList(model: model) }
            }
            else {
                if model.rows.isEmpty { ContentUnavailableView("Belum ada contoh yang sesuai", systemImage: "sparkle.magnifyingglass", description: Text("Tinjau kebutuhan Anda; syarat wajib tetap dipertahankan.")) }
                ForEach(model.rows.prefix(model.visibleLimit)) { row in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(row.experience.title).font(.headline)
                            Spacer()
                            Button { model.keep(row.id) } label: { Image(systemName: model.state.savedIDs.contains(row.id) ? "heart.fill" : "heart") }
                                .accessibilityLabel(model.state.savedIDs.contains(row.id) ? "Hapus pilihan" : "Simpan pengalaman").accessibilityIdentifier("save-" + row.id)
                        }
                        Text(row.experience.detail).font(.subheadline).foregroundStyle(.secondary)
                        if !row.unknown.isEmpty { Text("Sebagian kebutuhan belum diketahui pada contoh ini").font(.caption).foregroundStyle(.orange) }
                        if !row.contradicted.isEmpty { Text("Ada preferensi tambahan yang belum cocok").font(.caption).foregroundStyle(.secondary) }
                    }.padding().background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                }
                if model.rows.count > model.visibleLimit {
                    Button("Tampilkan contoh lainnya") { model.visibleLimit += 12 }.accessibilityIdentifier("more-examples")
                }
            }
        }
    }
    private var summary: some View {
        NavigationStack {
            List {
                Section("Pemahaman untuk perjalanan ini") {
                    if model.summary.isEmpty { Text("Belum ada rincian kegiatan. Minat umum tetap digunakan.") }
                    ForEach(model.questions.filter { model.state.values[$0.axis] != nil }) { q in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(model.state.values[q.axis].flatMap { v in q.choices.first { $0.value == v.value }?.summary } ?? q.text)
                            HStack {
                                Button(model.state.values[q.axis]?.must == true ? "Wajib" : "Diutamakan") { model.toggleMust(q.axis) }
                                if model.state.trip[q.axis] != nil { Button("Ingat untuk berikutnya") { model.remember(q.axis) } }
                            }.font(.caption).buttonStyle(.bordered)
                            ForEach(q.choices) { c in Button(c.label) { model.answer(q, c.id) }.font(.subheadline) }
                            Button("Hapus rincian", role: .destructive) { model.remove(q.axis) }.font(.caption)
                        }
                    }
                }
                Section("Pilihan tersimpan") {
                    ForEach(model.examples.filter { model.state.savedIDs.contains($0.id) }) { Text($0.title) }
                    ForEach(model.state.savedIDs.filter { model.knownPlaces[$0] != nil }, id: \.self) { id in
                        Text(model.knownPlaces[id]?.name ?? "Pilihan tersimpan")
                    }
                    ForEach(model.state.savedIDs.filter { model.catalogNames[$0] != nil }, id: \.self) { id in
                        Text(model.catalogNames[id] ?? "Pilihan tersimpan")
                    }
                    if !model.illustrationMode && model.state.savedIDs.contains(where: { model.knownPlaces[$0] == nil && model.catalogNames[$0] == nil }) {
                        Text("Pilihan tetap tersimpan. Detail tempat dimuat kembali saat hasil pencarian tersedia.").font(.caption)
                    }
                }
                Section {
                    Button("Batalkan perubahan terakhir") { model.undo() }.accessibilityIdentifier("undo-change")
                    Button("Mulai perjalanan baru") { model.newTrip() }.accessibilityIdentifier("new-trip")
                    ShareLink("Ekspor preferensi", item: model.exportIntent())
                }
                Section("Perjelas sendiri") {
                    Text("Opsional. Anda bisa menambahkan atau mengoreksi kebutuhan meski pertanyaan otomatis sudah selesai.").font(.caption).foregroundStyle(.secondary)
                    ForEach(model.questions.filter { q in
                        ["spending", "walking"].contains(q.axis) || (q.requiresAllInterests
                            ? Set(q.interests).isSubset(of: Set(model.state.interests))
                            : !Set(q.interests).isDisjoint(with: model.state.interests))
                    }) { q in
                        Button(q.text) { model.question = q; model.showSummary = false }
                    }
                }
                if !model.illustrationMode {
                    Section("Waktu kunjungan · opsional") {
                        Toggle("Periksa jam kunjungan", isOn: $model.checkVisitTime)
                        if model.checkVisitTime {
                            DatePicker("Tanggal dan waktu", selection: $model.visitDate)
                            Toggle("Periksa seluruh durasi", isOn: $model.checkDuration)
                            if model.checkDuration { Stepper("\(model.visitMinutes) menit", value: $model.visitMinutes, in: 15 ... 240, step: 15) }
                            Text("Jam layanan tidak memastikan penerimaan terakhir, tiket atau antrean.").font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Terapkan waktu dan cari ulang") { model.save(); model.invalidatePlaces(); model.discover(); model.showSummary = false }
                    }
                } else {
                    Section("Cari tempat nyata · demonstrasi lama") {
                        Picker("Area", selection: $model.area) { ForEach(["Jakarta Pusat", "Jakarta Selatan", "Jakarta Utara", "Jakarta Barat", "Jakarta Timur"], id: \.self) { Text($0) } }
                        Text("Pencarian mengikuti satu kegiatan pada ringkasan. Kecocokan seluruh kebutuhan belum diverifikasi.").font(.caption).foregroundStyle(.secondary)
                        Button("Cari tempat dari pilihan ini") { model.searchPlaces() }.disabled(model.placeBusy).accessibilityIdentifier("search-live-places")
                        if model.placeBusy { ProgressView() }
                        if let results = model.placeResults {
                            Text("Google Maps").font(.headline).accessibilityIdentifier("google-attribution")
                            Text(results.notice).font(.caption)
                            ForEach(results.places) { p in
                                VStack(alignment: .leading) {
                                    Text(p.displayName?.text ?? "Tempat").font(.headline).accessibilityIdentifier("live-place-name")
                                    Text(p.formattedAddress ?? "").font(.caption)
                                    if let s = p.googleMapsUri, let url = URL(string: s) { Link("Sumber di Google Maps", destination: url) }
                                }
                            }
                        }
                        if let e = model.error { Text(e).foregroundStyle(.red) }
                    }
                }
            }.buttonStyle(.borderless).navigationTitle("Pilihan saya").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Selesai") { model.showSummary = false } } }
        }
    }
    private var experiments: some View {
        NavigationStack {
            Form {
                Section("Pembanding") {
                    Picker("Cara memahami", selection: $model.mode) {
                        Text("A · minat umum").tag("broad"); Text("B · klarifikasi lokal").tag("rules"); Text("C · bantuan AI").tag("adaptive")
                    }.onChange(of: model.mode) { _, _ in model.refreshQuestion() }
                    Text("Katalog kegiatan memakai bukti OpenStreetMap yang diproses LLM server dan AnyJev sebelum pencarian. Data Google tidak dikirim ke model. Pembanding ilustratif tersedia melalui --illustrations.").font(.caption)
                }
                Section("Diagnosis") {
                    if let result = model.catalogResults {
                        Text("Server katalog · \(result.pipeline) · \(result.seconds, specifier: "%.3f") detik")
                        if let seconds = model.catalogRequestSeconds { Text("Permintaan aplikasi · \(seconds, specifier: "%.3f") detik") }
                        Text("Generasi " + result.runID).font(.caption)
                    }
                    Text(model.embeddingStatus)
                    if let d = model.lastDecision { Text("\(d.mode) · \(d.model ?? "lokal") · \(d.seconds, specifier: "%.2f") detik") }
                    Button("Audit E5 lokal") { Task { await model.runEmbeddingAudit() } }.accessibilityIdentifier("run-e5-audit")
                    Text(model.auditStatus).accessibilityIdentifier("audit-detail")
                }
            }.navigationTitle("Eksperimen").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Selesai") { model.showExperiments = false } } }
        }
    }
}
