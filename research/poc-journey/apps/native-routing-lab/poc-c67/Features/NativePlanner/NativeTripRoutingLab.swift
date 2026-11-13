import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable final class NativeTripRoutingLabModel {
    var dataset = "static"
    var count = 8
    var repetitions = 1
    var configuration = TripRoutingConfiguration()
    var requestLimit = 96
    private(set) var problem: TripRoutingProblem?
    private(set) var results: [TripRoutingResult] = []
    private(set) var busy = false
    private(set) var phase = ""
    private(set) var error: String?
    private(set) var requests = 0
    private(set) var acquisitionSeconds = 0.0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var services: NativeTripAppleServices?
    @ObservationIgnored private var identity = UUID()
    let logs = NativeTripLogStore.shared

    func cancel() {
        if busy {
            logs.record(
                "routing.comparison_cancelled", category: "optimizer", operationID: identity.uuidString,
                fields: ["phase": phase])
        }
        task?.cancel()
        services?.cancel()
        identity = UUID()
        busy = false
    }
    func run(_ draft: NativeTripDraft) {
        cancel()
        error = nil
        results = []
        problem = nil
        requests = 0
        busy = true
        let token = identity
        logs.recordJSON(
            "input.snapshot", category: "input", operationID: token.uuidString, value: draft)
        let config = configuration
        let selected = dataset
        let size = count
        let repeats = repetitions
        let provider = NativeTripAppleServices(
            operationID: token.uuidString, requestLimit: requestLimit)
        services = provider
        task = Task { [weak self] in
            do {
                let started = Date()
                let problem: TripRoutingProblem
                if selected == "mapkit" {
                    try draft.validate()
                    let forecasts = try await provider.forecasts(points: draft.allPoints, draft: draft) {
                        [weak self] in self?.phase = $0
                    }
                    problem = try await NativeTripRoutingBridge.snapshot(
                        draft, services: provider, forecasts: forecasts
                    ) { [weak self] in self?.phase = $0 }
                } else {
                    problem = TripRoutingFixtures.make(
                        count: size, dynamic: selected == "dynamic", seed: config.seed)
                }
                try Task.checkCancellation()
                guard let self, self.identity == token else { return }
                self.problem = problem
                self.requests = provider.directionRequests
                self.acquisitionSeconds = Date().timeIntervalSince(started)
                self.logs.record(
                    "routing.comparison_started", category: "optimizer", operationID: token.uuidString,
                    fields: [
                        "problemID": problem.id, "kind": problem.kind, "requests": String(self.requests),
                        "acquisitionSeconds": String(self.acquisitionSeconds),
                    ])
                let worker = TripRoutingWorker()
                for repetition in 0 ..< repeats {
                    var current = config
                    current.seed &+= UInt64(repetition)
                    for algorithm in TripRoutingAlgorithm.native {
                        try Task.checkCancellation()
                        self.phase = "\(algorithm.title) · seed \(current.seed)"
                        let result = try await worker.solve(algorithm, problem: problem, configuration: current)
                        guard self.identity == token, !Task.isCancelled else { return }
                        self.results.append(result)
                        self.logs.recordJSON(
                            "routing.comparison_result", category: "optimizer", operationID: token.uuidString,
                            value: result)
                    }
                }
                self.busy = false
                self.phase = "Selesai · snapshot yang sama untuk semua metode"
                // Keep the complete snapshot/results, because individual JSONL fields have a size limit.
                do {
                    let directory = FileManager.default.urls(
                        for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("NativeTripRouting", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let comparison = TripRoutingComparisonExport(
                        problem: problem, results: self.results, requests: self.requests,
                        acquisitionSeconds: self.acquisitionSeconds,
                        statistics: TripRoutingStatistics.make(self.results))
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try encoder.encode(comparison).write(
                        to: directory.appendingPathComponent("last-comparison.json"), options: .atomic)
                    self.logs.record(
                        "routing.comparison_saved", category: "optimizer", operationID: token.uuidString)
                } catch {
                    self.logs.record(
                        "routing.comparison_save_failed", category: "optimizer", level: "warning",
                        operationID: token.uuidString, fields: NativeTripLogStore.errorFields(error))
                }
            } catch {
                guard let self, self.identity == token, !Task.isCancelled else { return }
                self.busy = false
                self.error = error.localizedDescription
                self.logs.record(
                    "routing.comparison_failed", category: "optimizer", level: "error",
                    operationID: token.uuidString, fields: NativeTripLogStore.errorFields(error))
            }
        }
    }

    func importResult(_ data: Data) throws {
        guard let problem, !busy else {
            throw TripRoutingFailure.invalid("Jalankan pembandingan dahulu.")
        }
        let result = try TripRoutingImport.result(data, problem: problem, configuration: configuration)
        results.removeAll { $0.algorithm == .ortools }
        results.append(result)
        logs.recordJSON("routing.ortools_imported", category: "optimizer", value: result)
    }

    var optimum: Double? {
        results.first {
            $0.algorithm == .exact && $0.proof == "exhaustive_fixed_evaluator"
                && $0.best?.feasible == true
        }?.best?.finish
    }
    var summary: String {
        let native = results.filter { $0.best?.feasible == true && $0.best?.fullTour == true }
        return native.min { TripRoutingEvaluator.better($0.best!, $1.best!) }.map {
            "Durasi trip model terbaik: \($0.algorithm.title) · \(Int($0.best!.finish / 60)) menit"
        } ?? "Belum ada kandidat lengkap yang memenuhi batas pada data ini."
    }
}

struct NativeTripRoutingJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct NativeTripRoutingLabView: View {
    let draft: NativeTripDraft
    @State private var model = NativeTripRoutingLabModel()
    @State private var importing = false
    @State private var exporting = false
    @State private var document: NativeTripRoutingJSONDocument?
    @State private var fileName = "C67-routing-case.json"
    @State private var fileError: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Data", selection: $model.dataset) {
                    Text("Sintetis · statis").tag("static")
                    Text("Sintetis · berubah waktu").tag("dynamic")
                    Text("Tempat saya · MapKit").tag("mapkit")
                }
                if model.dataset != "mapkit" {
                    Stepper("\(model.count) tujuan sintetis", value: $model.count, in: 1 ... 20)
                } else {
                    Text(
                        "Snapshot ETA pada jam berangkat. Data yang tidak terambil tetap unknown. Ini belum validasi seluruh rundown live."
                    ).font(.footnote)
                }
                Text("Data sintetis menguji algoritme; bukan rekomendasi tempat atau perjalanan nyata.")
                    .font(.footnote).foregroundStyle(.secondary)
                Stepper(
                    "Seed: \(model.configuration.seed)", value: $model.configuration.seed, in: 0 ... 1_000_000)
                Stepper("Pengulangan: \(model.repetitions)", value: $model.repetitions, in: 1 ... 5)
                Stepper(
                    "Beam: \(model.configuration.beamWidth)", value: $model.configuration.beamWidth,
                    in: 1 ... 32)
                Stepper(
                    "CPU: \(Int(model.configuration.secondsLimit)) detik/metode",
                    value: $model.configuration.secondsLimit, in: 1 ... 15)
                Stepper(
                    "Evaluasi: \(model.configuration.evaluationLimit)",
                    value: $model.configuration.evaluationLimit, in: 1000 ... 100_000, step: 1000)
                Stepper(
                    "Batas ETA: \(model.requestLimit)", value: $model.requestLimit, in: 32 ... 1024, step: 32)
            }.disabled(model.busy)
            if model.dataset == "mapkit" {
                Section("Jam operasional input") {
                    Text(
                        "\(NativeTripOpening.dateKey(draft.departure, timeZone: draft.timeZone)) · \(draft.timeZoneID). Ubah jam melalui detail tujuan di Rencana."
                    ).font(.footnote)
                    ForEach(draft.stops.filter { $0.role == .visit }) { stop in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(stop.point.title)
                            Text(stop.opening?.summary ?? "Belum diisi; ketersediaan saat tiba belum dipastikan.")
                                .font(.caption).foregroundStyle(.secondary)
                            if let note = stop.opening?.sourceNote { Text(note).font(.caption) }
                            if let issue = stop.opening?.issue(for: draft.departure, timeZone: draft.timeZone) {
                                Text(issue).font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                    Text(
                        "Jam yang diketahui dipakai untuk waktu menunggu dan pemeriksaan jam tutup. Prioritas optimasi elapsed_v2: kelayakan, lalu total durasi trip termasuk menunggu dan singgah."
                    ).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                if model.dataset == "mapkit" {
                    ForEach(draft.locationWarnings, id: \.self) {
                        Text($0).font(.footnote).foregroundStyle(.orange)
                    }
                    Text("Moda: \(draft.modes.map(\.title).joined(separator: ", "))")
                        .font(.footnote)
                }
                if model.busy {
                    ProgressView(model.phase)
                    Button("Batalkan") { model.cancel() }
                } else {
                    Button("Bandingkan semua metode native") { model.run(draft) }
                }
                if let error = model.error ?? fileError { Text(error).foregroundStyle(.red) }
            }
            if let problem = model.problem {
                Section("Kelengkapan ETA") {
                    let coverage = problem.coverage
                    Text(
                        "\(coverage.availablePairs)/\(coverage.requiredPairs) pasangan berarah punya moda yang bisa dipakai pada jam berangkat."
                    )
                    ForEach(coverage.modes) { mode in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(
                                "\(NativeTripMode(rawValue: mode.mode)?.title ?? mode.mode): \(mode.available)/\(mode.sampled) tersedia"
                            )
                            Text(
                                mode.statuses.keys.sorted().map { "\($0): \(mode.statuses[$0]!)" }.joined(
                                    separator: " · ")
                            )
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !coverage.blockedPairs.isEmpty {
                        Text(
                            "\(coverage.unsampledPairs) pasangan belum diminta. Periksa pin, cakupan moda, dan batas berjalan. Semua ruas yang tidak tersedia tetap tidak bisa dipakai."
                        )
                        .font(.footnote)
                        DisclosureGroup("Ruas tanpa moda yang bisa dipakai") {
                            ForEach(coverage.blockedPairs) { pair in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(problem.nodes[pair.from].name) → \(problem.nodes[pair.to].name)")
                                    Text(pair.reasons.joined(separator: "\n")).font(.caption)
                                }
                            }
                        }
                    }
                }
                Section("Kasus") {
                    Text(problem.label)
                    Text(
                        "\(model.requests) request ETA bersama · akuisisi \(model.acquisitionSeconds, specifier: "%.2f") dtk"
                    ).font(.caption)
                    Text(model.summary).font(.footnote)
                    if problem.weatherSources?.values.contains("open_meteo") == true {
                        NativeTripOpenMeteoAttribution()
                    }
                    if let optimum = model.optimum {
                        Text("Acuan enumerasi model: \(optimum / 60, specifier: "%.1f") menit").font(.footnote)
                    }
                    Text(
                        "Satu model untuk semua metode; CPU diukur terpisah dari pengambilan ETA. Hasil model belum membuktikan optimum rute dunia nyata."
                    ).font(.footnote)
                }
                if model.repetitions > 1 {
                    Section("Ringkasan pengulangan") {
                        ForEach(TripRoutingStatistics.make(model.results)) { statistic in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(statistic.algorithm.title)
                                Text(
                                    "\(statistic.feasibleRuns)/\(statistic.runs) layak · median CPU \(statistic.medianCPU, specifier: "%.3f") dtk"
                                ).font(.caption)
                                if let median = statistic.medianElapsed, let low = statistic.minimumElapsed,
                                   let high = statistic.maximumElapsed
                                {
                                    Text(
                                        "Durasi trip median \(median / 60, specifier: "%.1f") menit · rentang \(low / 60, specifier: "%.1f")–\(high / 60, specifier: "%.1f")"
                                    ).font(.caption)
                                }
                            }
                        }
                    }
                }
                Section("Hasil") {
                    ForEach(model.results) { result in
                        NavigationLink {
                            NativeTripRoutingResultView(result: result, problem: problem, optimum: model.optimum)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.algorithm.title)
                                if let best = result.best, best.complete {
                                    Text(
                                        "\(best.finish / 60, specifier: "%.1f") menit · \(best.feasible && best.fullTour ? "layak pada model" : "belum layak/lengkap")"
                                    )
                                }
                                if result.best?.complete == false {
                                    Text("Durasi belum lengkap").font(.caption).foregroundStyle(.orange)
                                }
                                Text(
                                    "seed \(result.configuration.seed) · \(result.evaluations) evaluasi · \(result.elapsed, specifier: "%.3f") dtk · \(result.termination)"
                                ).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("OR-Tools · helper Mac") {
                    Button("Ekspor kasus OR-Tools (.json)") { export(problem) }
                    Button("Impor hasil OR-Tools (.json)") { importing = true }
                    Text(
                        "Jalankan scripts/solve-routing-ortools.py pada Mac, lalu impor hasil untuk dinilai ulang di sini. OR-Tools tidak dibundel di iPhone."
                    ).font(.footnote)
                    Button("Ekspor seluruh perbandingan (.json)") {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        do {
                            let report = TripRoutingComparisonExport(
                                problem: problem, results: model.results, requests: model.requests,
                                acquisitionSeconds: model.acquisitionSeconds,
                                statistics: TripRoutingStatistics.make(model.results))
                            document = .init(data: try encoder.encode(report))
                            fileName = "C67-routing-comparison.json"
                            exporting = true
                        } catch { fileError = error.localizedDescription }
                    }
                }.disabled(model.busy)
            }
        }
        .navigationTitle("Bandingkan algoritme").navigationBarTitleDisplayMode(.inline)
        .toolbar { NavigationLink("Log") { NativeTripLogView(store: model.logs) } }
        .onDisappear { model.cancel() }
        .onChange(of: scenePhase) { _, value in if value != .active { model.cancel() } }
        .fileExporter(
            isPresented: $exporting, document: document, contentTypes: [.json], defaultFilename: fileName,
            onCompletion: { result in
                if case .failure(let error) = result { fileError = error.localizedDescription }
            }
        )
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1_000_000 else {
                    throw TripRoutingFailure.invalid("File terlalu besar.")
                }
                try model.importResult(Data(contentsOf: url))
                fileError = nil
            } catch { fileError = error.localizedDescription }
        }
    }
    private func export(_ problem: TripRoutingProblem) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            document = .init(data: try encoder.encode(problem))
            fileName = "C67-routing-case-\(problem.id.prefix(8)).json"
            exporting = true
        } catch { fileError = error.localizedDescription }
    }
}

struct TripRoutingComparisonExport: Codable {
    var problem: TripRoutingProblem
    var results: [TripRoutingResult]
    var requests: Int
    var acquisitionSeconds: Double
    var statistics: [TripRoutingStatistics]
}

private struct NativeTripRoutingResultView: View {
    let result: TripRoutingResult
    let problem: TripRoutingProblem
    let optimum: Double?
    var body: some View {
        List {
            Section {
                Text(result.algorithm.title).font(.headline)
                Text(result.note).font(.footnote)
                LabeledContent("Penghentian", value: result.termination)
                LabeledContent("Bukti", value: result.proof)
                if let best = result.best {
                    LabeledContent(
                        best.complete ? "Perpindahan" : "Perpindahan parsial",
                        value: String(format: "%.1f menit", best.travel / 60))
                    LabeledContent("Menunggu", value: String(format: "%.1f menit", best.waiting / 60))
                    LabeledContent("Singgah", value: String(format: "%.1f menit", best.dwell / 60))
                    if best.complete {
                        LabeledContent(
                            "Selesai sejak berangkat", value: String(format: "+%.1f menit", best.finish / 60))
                    }
                    LabeledContent("Ruas terhitung", value: "\(best.legs.count)/\(problem.targets.count + 1)")
                    LabeledContent("Ruas yang menghentikan evaluasi", value: String(best.missing))
                    if !best.complete, best.missing > 0 {
                        let route = [problem.origin] + best.order + [problem.end]
                        let index = best.legs.count
                        if index + 1 < route.count {
                            Text(
                                "Terhenti pada \(problem.nodes[route[index]].name) → \(problem.nodes[route[index + 1]].name). Ruas selanjutnya belum dievaluasi; angka ini bukan jumlah seluruh ETA yang kosong."
                            )
                            .font(.footnote)
                        }
                    }
                    if let optimum, optimum > 0, best.feasible && best.fullTour {
                        LabeledContent(
                            "Selisih acuan model",
                            value: String(format: "%.2f%%", (best.finish / optimum - 1) * 100))
                    }
                }
            }
            if let best = result.best {
                Section("Urutan model") {
                    ForEach(Array(best.legs.enumerated()), id: \.offset) { index, leg in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(index + 1). \(problem.nodes[leg.to].name)")
                            Text(
                                "\(leg.mode) · tiba +\(Int(leg.arrival / 60)) menit · lanjut +\(Int(leg.leave / 60)) menit"
                            ).font(.caption)
                        }
                    }
                    ForEach(best.conflicts, id: \.self) { Text($0).foregroundStyle(.red) }
                }
            }
            if let weather = TripRoutingEvaluator(problem).weatherChoice(result.alternatives) {
                Section("Alternatif cuaca pada model") {
                    Text(weather.order.map { problem.nodes[$0].name }.joined(separator: " → "))
                    Text(
                        "Paparan berbobot \(weather.rain / 60, specifier: "%.1f") menit; dalam batas tambahan waktu."
                    ).font(.footnote)
                    if problem.weatherSources?.values.contains("open_meteo") == true {
                        NativeTripOpenMeteoAttribution()
                    }
                }
            }
        }.navigationTitle("Detail pembanding").navigationBarTitleDisplayMode(.inline)
    }
}
