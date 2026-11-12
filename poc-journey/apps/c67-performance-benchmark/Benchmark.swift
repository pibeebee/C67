import Foundation
import Observation
import PreferenceQuality
#if BENCHMARK_REPLAY
    @testable import TripIntegration
#else
    import TripIntegration
#endif

struct BenchmarkCase: Codable {
    var id: String
    var family: String
    var cacheCondition: String
    var expected: String
    var request: TripRequest
    var revision = false
}

struct BenchmarkResult: Codable {
    var id: String
    var family: String
    var cacheCondition: String
    var expected: String
    var observed: String
    var passed: Bool
    var seconds: Double
    var requestedCount: Int
    var selectedIDs: [String]
    var stopCount: Int
    var stages: [StageMetric]
    var embeddingPresent: Bool
    var weatherProviders: [String]
    var cachedWeatherGroups: Int
    var completeWeather: Bool
    var conflicts: [String]
    var detail: String
    var thermalBefore: String
    var thermalAfter: String
}

enum BenchmarkMatrix {
    static func cases(now: Date) -> [BenchmarkCase] {
        let calendar = TripClock.calendar
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        func request(_ ids: [String], hour: Int = 7) -> TripRequest {
            var value = TripRequest(now: now)
            value.departure = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow)!
            value.deadline = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: tomorrow)!
            value.requiredCandidateIDs = ids; value.desiredCount = ids.count
            value.profile.prefer = [.reading, .culture]
            value.useEmbedding = true; value.allowOpenMeteo = false
            return value
        }
        var output: [BenchmarkCase] = []
        let definitions: [(String, [String], Int)] = [
            ("N1", ["cikini"], 9),
            ("N3", ["cikini", "bdt-rbbj", "erasmus"], 9),
            ("N4", ["cikini", "bdt-rbbj", "erasmus", "ragunan"], 7),
            ("N5", ["cikini", "bdt-rbbj", "erasmus", "ragunan", "gbk"], 7),
        ]
        for (family, ids, hour) in definitions {
            let input = request(ids, hour: hour)
            for repetition in 1 ... 3 {
                output.append(.init(id: "\(family)-R\(repetition)", family: family,
                                    cacheCondition: repetition == 1 ? "fresh_pipeline" : "reused_pipeline",
                                    expected: "ready", request: input))
            }
        }
        let five = definitions.last!.1
        output.append(.init(id: "REV5", family: "revision5", cacheCondition: "reused_pipeline",
                            expected: "ready", request: request(five), revision: true))
        var varied = request(five)
        varied.durationByVenue = ["cikini": 45, "bdt": 90, "erasmus": 45, "ragunan": 60, "gbk": 30]
        output.append(.init(id: "MIX5", family: "mixed_duration5", cacheCondition: "fresh_pipeline",
                            expected: "ready", request: varied))
        var tight = request(five)
        tight.defaultDuration = 90
        tight.deadline = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: tomorrow)!
        output.append(.init(id: "TIGHT5", family: "impossible_deadline5", cacheCondition: "fresh_pipeline",
                            expected: "conflicted", request: tight))
        var six = request([]); six.desiredCount = 6
        output.append(.init(id: "SIX", family: "insufficient_catalog6", cacheCondition: "fresh_pipeline",
                            expected: "needsPlaces", request: six))
        var unknown = request(["cikini"], hour: 9); unknown.profile.must = [.wifi]
        output.append(.init(id: "UNKNOWN", family: "unsupported_requirement", cacheCondition: "fresh_pipeline",
                            expected: "needsPlaces", request: unknown))
        return output
    }
}

@MainActor @Observable final class PerformanceBenchmark {
    var progress = "Preparing benchmark"
    var complete = false
    var results: [BenchmarkResult] = []
    let folder: URL
    private var started = false
    private let catalog: IntegrationCatalog
    private let evaluationNow: @MainActor () -> Date
    private var pipeline: IntegrationPipeline?
    private var previousFamily: String?
    private var baseline: IntegratedPlan?
    private var baselineModel: IntegrationModel?
    private var activeModel: IntegrationModel?
    private let clock = ContinuousClock()
    static var evidence: String {
        #if BENCHMARK_REPLAY
            "Mac replay: authored coordinates, time-dependent ETA and weather; actual E5; not provider latency"
        #else
            "iPhone: unchanged app orchestration and packages; actual E5, MapKit and WeatherKit; no fallback"
        #endif
    }
    init(folder: URL, now: @escaping @MainActor () -> Date = { .now }) throws {
        self.folder = folder; self.evaluationNow = now
        catalog = try .load()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    private func save<T: Encodable>(_ value: T, _ name: String) throws {
        try IntegrationJSON.encoder().encode(value).write(to: folder.appendingPathComponent(name), options: .atomic)
    }
    private func status(_ message: String) throws {
        progress = message
        struct Snapshot: Encodable {
            var evidence: String; var progress: String; var complete: Bool
            var os: String; var updatedAt: Date; var results: [BenchmarkResult]
        }
        try save(Snapshot(evidence: Self.evidence, progress: message, complete: complete,
                          os: ProcessInfo.processInfo.operatingSystemVersionString, updatedAt: .now, results: results), "status.json")
        print("C67_PERFORMANCE \(message)")
    }
    private func seconds(_ start: ContinuousClock.Instant) -> Double {
        let value = start.duration(to: clock.now).components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }
    private func makePipeline() throws -> IntegrationPipeline {
        #if BENCHMARK_REPLAY
            let value = IntegrationPipeline(catalog: catalog, search: ReplaySearch(),
                                            weather: TripWeatherCoordinator(provider: ReplayWeather()),
                                            logDirectory: folder.appendingPathComponent("ProviderLogs/\(UUID())"))
            value.replayETA = { from, to, mode, departure in
                try Task.checkCancellation()
                let distance = from.distance(to: to)
                let minute = TripClock.minute(departure)
                let peak = (420 ..< 600).contains(minute) || (960 ..< 1140).contains(minute)
                let duration = (300 + distance / 8) * (peak ? 1.35 : 1)
                return .init(id: "\(from.id)>\(to.id)", mode: mode, seconds: duration, distance: distance,
                             expectedDeparture: departure, expectedArrival: departure.addingTimeInterval(duration),
                             status: "available", note: "Authored distance/time-dependent replay; not observed ETA")
            }
            return value
        #else
            return IntegrationPipeline(catalog: catalog, logDirectory: folder.appendingPathComponent("ProviderLogs/\(UUID())"))
        #endif
    }
    private func settle(_ model: IntegrationModel, started: ContinuousClock.Instant) async throws {
        while model.busy || model.saving {
            if seconds(started) > 240 {
                model.cancel()
                throw IntegrationError.invalid("240s observation limit reached; censored, not a completed itinerary")
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
    private func execute(_ test: BenchmarkCase) async throws -> BenchmarkResult {
        if pipeline == nil || test.cacheCondition == "fresh_pipeline" {
            pipeline = try makePipeline()
        }
        let store = TripStore(directory: folder.appendingPathComponent("Sessions/\(test.id)"))
        let model: IntegrationModel
        if test.revision, let previous = baselineModel { model = previous }
        else {
            model = IntegrationModel(catalog: catalog, pipeline: pipeline!, store: store,
                                     request: test.request, replay: Self.isReplay, clock: evaluationNow)
            await model.load()
        }
        activeModel = model
        let thermalBefore = String(describing: ProcessInfo.processInfo.thermalState)
        let began = clock.now
        var timedError: String?
        if test.revision {
            if let baseline, let stop = baseline.stops.last {
                model.extendAutomatically(stop, plan: baseline)
            } else { timedError = "No feasible five-stop baseline; no replacement generated" }
        } else { model.createItinerary() }
        do { try await settle(model, started: began) }
        catch { timedError = ProviderDiagnostics.message(error) }
        // Stop before benchmark export/auditing: time includes actual app proposal persistence,
        // and at most 50 ms observation polling; excludes load, acceptance and report export.
        let elapsed = seconds(began)
        let plan = test.revision && timedError != nil ? nil : model.session.proposal
        let observed = timedError == nil ? (model.error == nil ? (plan?.status ?? String(describing: model.simpleStep)) : "error") : "censored_or_missing_baseline"
        var passed = observed == test.expected
        var auditNotes: [String] = []
        if let review = model.review { try save(review, "\(test.id)-recommendation.json") }
        if let prepared = model.prepared { try save(prepared, "\(test.id)-locations.json") }
        if let plan {
            try save(plan, "\(test.id)-plan.json")
            do {
                try PlanAudit.validate(plan)
                guard Set(plan.prepared.selectedIDs) == Set(test.request.requiredCandidateIDs),
                      plan.quality.embedding != nil,
                      plan.evidenceMode == (Self.isReplay ? "synthetic_replay" : "live") else {
                    throw IntegrationError.invalid("Selected set, E5 or evidence mode mismatch")
                }
                if !Self.isReplay {
                    guard !plan.weather.isEmpty, plan.weather.allSatisfy({ $0.complete && $0.provider == "weatherkit" }) else {
                        throw IntegrationError.invalid("WeatherKit incomplete; full-provider success not established")
                    }
                }
                if test.expected == "ready" {
                    guard plan.feasible, plan.stops.count == test.request.desiredCount else {
                        throw IntegrationError.invalid("Incomplete/invalid result cannot count as a fast itinerary")
                    }
                }
                if test.revision, let baseline {
                    guard plan.id != baseline.id, plan.baseAcceptedID == baseline.id,
                          model.session.accepted?.id == baseline.id,
                          let stop = baseline.stops.last,
                          plan.request.duration(stop.venueID) == baseline.request.duration(stop.venueID) + 30 else {
                        throw IntegrationError.invalid("Revision lost accepted baseline or duration")
                    }
                }
            } catch { passed = false; auditNotes.append(ProviderDiagnostics.message(error)) }
        } else if test.expected == "needsPlaces" {
            passed = passed && model.prepared == nil && model.selected.isSuperset(of: Set(test.request.requiredCandidateIDs))
        }
        let value = BenchmarkResult(id: test.id, family: test.family, cacheCondition: test.cacheCondition,
                                    expected: test.expected, observed: observed, passed: passed, seconds: elapsed,
                                    requestedCount: test.request.desiredCount, selectedIDs: Array(model.selected).sorted(),
                                    stopCount: plan?.stops.count ?? 0, stages: plan?.metrics ?? [],
                                    embeddingPresent: model.review?.quality.embedding != nil,
                                    weatherProviders: Array(Set(plan?.weather.map(\.provider) ?? [])).sorted(),
                                    cachedWeatherGroups: plan?.weather.filter(\.cached).count ?? 0,
                                    completeWeather: !(plan?.weather.isEmpty ?? true) && (plan?.weather.allSatisfy(\.complete) ?? false),
                                    conflicts: plan?.conflicts ?? [],
                                    detail: ([timedError, model.error].compactMap { $0 } + auditNotes + [model.progress]).joined(separator: " | "),
                                    thermalBefore: thermalBefore, thermalAfter: String(describing: ProcessInfo.processInfo.thermalState))
        // Acceptance is separate from generation latency and only in isolated benchmark storage.
        if test.id == "N5-R3", let plan, plan.feasible {
            model.apply(); try await settle(model, started: clock.now)
            if model.session.accepted?.id == plan.id { baseline = plan; baselineModel = model }
        }
        if test.revision { model.reject(); try await settle(model, started: clock.now) }
        previousFamily = test.family
        activeModel = nil
        return value
    }
    static var isReplay: Bool {
        #if BENCHMARK_REPLAY
            true
        #else
            false
        #endif
    }
    func run() async {
        guard !started else { return }; started = true
        do {
            let tests = BenchmarkMatrix.cases(now: evaluationNow())
            try save(tests, "matrix.json")
            try status("Starting \(tests.count) cases. \(Self.evidence)")
            for test in tests {
                try status("Running \(test.id) (\(results.count + 1)/\(tests.count))")
                let value = try await execute(test)
                results.append(value)
                try save(value, "\(test.id)-result.json")
                try status("\(test.id): \(value.observed), \(String(format: "%.3f", value.seconds))s; audit \(value.passed ? "pass" : "FAIL")")
            }
            complete = true
            try status("Completed \(results.count) cases; \(results.filter(\.passed).count) passed")
        } catch {
            complete = true
            try? status("Harness error: \(ProviderDiagnostics.message(error)); incomplete cases are not passes")
        }
    }
}
