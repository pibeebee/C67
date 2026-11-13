import SwiftUI
import Observation
import PlannerContracts

private struct RunConfig: Decodable {
    var baseURL: URL; var token: String; var mode: String
}
@MainActor @Observable final class HarnessModel {
    var progress = "Ready — isolated server lab"
    var rows: [LabObservation] = []
    var running = false
    var complete = false
    var selectedVariant = "ABC"
    var evidenceLabel = "Synthetic replay · actual E5"
    var folder: URL?
    private var task: Task<Void, Never>?
    func start() {
        guard !running else { return }
        running = true; complete = false; rows = []
        task = Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = true
            defer { running = false; UIApplication.shared.isIdleTimerDisabled = false }
            do { try await run() }
            catch is CancellationError { progress = "Cancelled. Saved observations preserved."; try? saveStatus() }
            catch { progress = "Stopped: \(error.localizedDescription)"; try? saveStatus() }
        }
    }
    func cancel() { task?.cancel(); progress = "Cancellation requested" }
    func loadLastRun() {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("C67LocalServerLab")
        guard let name = try? String(contentsOf: base.appendingPathComponent("last-run.txt"), encoding: .utf8),
              !name.contains("/"), let data = try? Data(contentsOf: base.appendingPathComponent(name).appendingPathComponent("observations.json")),
              let saved = try? LabJSON.decoder().decode([LabObservation].self, from: data) else { return }
        rows = saved; folder = base.appendingPathComponent(name)
        progress = "Restored \(saved.count) saved observations; proposals remain inspectable locally"
    }
    private func config() throws -> RunConfig {
        let e = ProcessInfo.processInfo.environment
        if let url = e["LAB_URL"], let token = e["LAB_ACCESS_TOKEN"] {
            return RunConfig(baseURL: URL(string: url)!, token: token, mode: e["LAB_PROVIDER_MODE"] ?? "replay")
        }
        guard let url = Bundle.main.url(forResource: "RunConfig", withExtension: "json") else {
            throw LabFailure.invalid("Generate ignored RunConfig.json, or set LAB_URL and LAB_ACCESS_TOKEN in run environment")
        }
        return try JSONDecoder().decode(RunConfig.self, from: Data(contentsOf: url))
    }
    private func saveStatus() throws {
        guard let folder else { return }
        struct Status: Encodable { var progress: String; var complete: Bool; var results: [LabObservation]; var os: String }
        try LabJSON.encoder().encode(Status(progress: progress, complete: complete, results: rows,
                                            os: ProcessInfo.processInfo.operatingSystemVersionString)).write(to: folder.appendingPathComponent("status.json"), options: .atomic)
    }
    private func run() async throws {
        var run = ProcessInfo.processInfo.environment["LAB_RUN_ID"] ?? UUID().uuidString
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if FileManager.default.fileExists(atPath: documents.appendingPathComponent("C67LocalServerLab/\(run)/status.json").path) {
            run += "-attempt-" + UUID().uuidString
        }
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("C67LocalServerLab/\(run)")
        self.folder = folder
        let pointer = folder.deletingLastPathComponent().appendingPathComponent("last-run.txt")
        try FileManager.default.createDirectory(at: pointer.deletingLastPathComponent(), withIntermediateDirectories: true)
        try run.write(to: pointer, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try saveStatus()
        let config = try config()
        let replay = config.mode == "replay"
        evidenceLabel = replay ? "Synthetic replay · actual E5" : "Live providers · actual E5"
        guard replay || (config.mode == "rest" && ProcessInfo.processInfo.environment["LAB_LIVE_APPROVED"] == "frozen-campaign-v1") else {
            throw LabFailure.invalid("Live requires the explicit frozen campaign gate")
        }
        let client = try LabClient(baseURL: config.baseURL, token: config.token)
        let caps = try await client.capabilities()
        guard caps["providerMode"] == config.mode, caps["snapshotHash"] == (try LabSnapshot.hash()) else {
            throw LabFailure.conflict("Server mode or catalogue mismatch")
        }
        let pinSnapshot: LabPinSnapshot?
        if let encoded = ProcessInfo.processInfo.environment["LAB_PIN_SNAPSHOT_BASE64"], let data = Data(base64Encoded: encoded) {
            pinSnapshot = try LabJSON.decoder().decode(LabPinSnapshot.self, from: data)
            try pinSnapshot!.validate(now: .now)
            guard caps["pinSnapshotHash"] == (try LabJSON.hash(pinSnapshot!)) else { throw LabFailure.conflict("Client/server shared pin mismatch") }
            evidenceLabel = "Live ETA/weather · shared real pins"
        } else {
            pinSnapshot = nil
            guard (caps["pinSnapshotHash"] ?? "").isEmpty else { throw LabFailure.conflict("Server pin experiment requires matching client snapshot") }
        }
        var items = replay ? LabCampaign.replay() : LabCampaign.live(now: .now)
        if !replay {
            guard selectedVariant == "ABC" else { throw LabFailure.invalid("Frozen live campaign requires A/B/C") }
            if ProcessInfo.processInfo.environment["LAB_LIVE_SUBSET"] == "fresh_edges" {
                items = items.filter { !["priming", "warm"].contains($0.condition) }
            }
        }
        if ProcessInfo.processInfo.environment["LAB_COMPARISON"] == "CD" {
            items = LabCampaign.fastComparison(now: replay ? LabMatrix.now : .now)
        }
        if ProcessInfo.processInfo.environment["LAB_COMPARISON"] == "DE" {
            items = LabCampaign.decisionComparison(now: .now)
        }
        if let filter = ProcessInfo.processInfo.environment["LAB_CASE_FAMILIES"] {
            let families = Set(filter.split(separator: ",").map(String.init))
            guard families.isSubset(of: Set(items.map { $0.test.family })) else { throw LabFailure.invalid("Unknown campaign family") }
            items = items.filter { families.contains($0.test.family) }
        }
        if let filter = ProcessInfo.processInfo.environment["LAB_CASE_IDS"] {
            let ids = Set(filter.split(separator: ",").map(String.init))
            guard ids.isSubset(of: Set(items.map { $0.test.id })) else { throw LabFailure.invalid("Unknown case ID") }
            items = items.filter { ids.contains($0.test.id) }
        }
        let tests = items.map(\.test)
        try LabJSON.encoder().encode(items).write(to: folder.appendingPathComponent("campaign.json"))
        try LabJSON.encoder().encode(tests).write(to: folder.appendingPathComponent("matrix.json"))
        try LabJSON.encoder().encode(caps).write(to: folder.appendingPathComponent("capabilities.json"))
        let original = OriginalDriver(); var accepted: [String: AcceptedState] = [:]
        var consecutiveUnavailable = 0
        var nativeCalls = Int(ProcessInfo.processInfo.environment["LAB_PROVIDER_CALLS_OFFSET"] ?? "0") ?? 0
        var nativeCells = Int(ProcessInfo.processInfo.environment["LAB_ETA_CELLS_OFFSET"] ?? "0") ?? 0
        for item in items {
            let test = item.test
            let variant = item.variant
            if selectedVariant == "ABC" || selectedVariant == variant {
                try Task.checkCancellation()
                if !replay {
                    let current = try await client.capabilities()
                    let calls = nativeCalls + (Int(current["providerCalls"] ?? "0") ?? 0)
                    let cells = nativeCells + (Int(current["providerCells"] ?? "0") ?? 0)
                    guard calls + 542 <= 3000, cells + 512 <= 6000 else {
                        throw LabFailure.unavailable("campaign_budget_reserve_exhausted; remaining runs unexecuted")
                    }
                }
                progress = "\(test.id) · \(variant) · \(rows.count)/\(items.count)"; try saveStatus()
                let began = ContinuousClock.now
                var value: LabOutcome?; var failure: String?; var baseID: UUID?
                do {
                    if variant == "A" {
                        value = try await original.run(test.request, now: replay ? LabMatrix.now : .now,
                                                       directory: folder.appendingPathComponent("A/\(test.id)"), revision: test.revision,
                                                       replay: replay, reusePipeline: item.condition == "warm", pinSnapshot: pinSnapshot)
                    } else {
                        var request = test.request
                        let baseline = accepted[variant]
                        if test.revision {
                            guard let baseline, let last = baseline.plan.stops.last else { throw LabFailure.conflict("Revision baseline missing") }
                            request = baseline.plan.request; request.revision += 1
                            request.durationByVenue[last.venueID] = last.duration + 30; baseID = baseline.plan.id
                        }
                        let input = JobInput(clientID: run + variant, runID: run,
                                             variant: LabVariant(rawValue: variant)!, snapshotHash: try LabSnapshot.hash(), request: request,
                                             baseRevision: baseline?.revision ?? 0, baseAcceptedID: baseline?.plan.id)
                        let job = try await client.submit(input)
                        value = try await client.wait(job) { _ in }
                    }
                    try LabJSON.encoder().encode(value).write(to: folder.appendingPathComponent("\(test.id)-\(variant)-result.json"), options: .atomic)
                } catch is CancellationError { throw CancellationError() }
                catch { failure = error.localizedDescription }
                rows.append(.init(caseID: test.id, family: test.family, variant: variant, condition: item.condition,
                                  clientSeconds: elapsed(began), outcome: value, error: failure,
                                  thermal: String(describing: ProcessInfo.processInfo.thermalState), baselineID: baseID))
                try LabJSON.encoder().encode(rows).write(to: folder.appendingPathComponent("observations.json"), options: .atomic)
                try saveStatus()
                if !replay {
                    let unavailable = failure != nil || ["provider_unavailable", "incomplete_data"].contains(value?.outcome ?? "")
                    consecutiveUnavailable = unavailable ? consecutiveUnavailable + 1 : 0
                    if variant == "A" {
                        nativeCalls += value?.plan.map { $0.metrics.reduce(0) { $0 + $1.requests } } ?? ((value?.outcome == "needs_places" || value?.outcome == "needs_locations") ? 10 : 542)
                        nativeCells += value?.providerMetrics.cells ?? 512
                    }
                    guard consecutiveUnavailable < 2 else { throw LabFailure.unavailable("two_consecutive_provider_failures; new manifest required to resume") }
                }
                if variant == "A", test.family == "N5" { try await original.acceptBaseline() }
                if variant != "A", test.family == "N5", let plan = value?.plan, plan.feasible {
                    accepted[variant] = try await client.apply(plan, clientID: run + variant, baseRevision: accepted[variant]?.revision ?? 0)
                }
            }
        }
        complete = true; progress = "Finished · \(rows.count) observations · \(replay ? "SYNTHETIC REPLAY" : "LIVE")"
        try saveStatus()
    }
}
@main struct LocalServerHarnessApp: App {
    @State private var model = HarnessModel()
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    Section {
                        Text(model.evidenceLabel).font(.headline)
                        Text(model.evidenceLabel.hasPrefix("Live") ? "A uses native Apple services. B/C use REST on the Mac. Simulator results are distinct from physical iPhone timings." : "A runs on this device. B/C use the Mac HTTP server. These timings do not measure live Maps or WeatherKit.")
                        Picker("Variants", selection: $model.selectedVariant) {
                            ForEach(["ABC", "A", "B", "C", "D"], id: \.self) { Text($0) }
                        }.disabled(model.running)
                        Text(model.progress).accessibilityIdentifier("lab-progress")
                        if model.running {
                            Button(role: .destructive) { model.cancel() } label: {
                                Text("Cancel run").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.bordered)
                        }
                        else {
                            Button { model.start() } label: {
                                Text("Run benchmark campaign").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.borderedProminent).accessibilityIdentifier("lab-run")
                        }
                    }
                    Section("Results") {
                        ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                            VStack(alignment: .leading) {
                                Text("\(row.caseID) · \(row.variant) · \(row.outcome?.outcome ?? "failed")")
                                Text(String(format: "%.3fs · %d calls / %d cells", row.clientSeconds,
                                            row.outcome?.providerMetrics.calls ?? 0, row.outcome?.providerMetrics.cells ?? 0)).font(.caption)
                            }
                        }
                    }
                    if let folder = model.folder { Section("Local export") { Text(folder.lastPathComponent).font(.caption) } }
                }.navigationTitle("C67 Server Lab")
            }.task {
                if ProcessInfo.processInfo.arguments.contains("--lab-auto") { model.start() }
                else { model.loadLastRun() }
            }
        }
    }
}
