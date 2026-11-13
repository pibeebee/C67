import Foundation
import Observation
import SwiftUI
import PlaceContextEngine
import DynamicTripContracts

struct ContextRunConfig: Decodable {
    var baseURL: URL
    var token: String
}

@MainActor final class ContextAPI {
    private let config: ContextRunConfig
    private let session: URLSession
    private let namespace: String
    init(namespace: String = "context") throws {
        guard ["context", "recommendation"].contains(namespace) else { throw ContextError.invalid("Namespace lab tidak valid") }
        self.namespace = namespace
        guard let url = Bundle.main.url(forResource: "RunConfig", withExtension: "json") else {
            throw ContextError.invalid("Konfigurasi server lokal belum tersedia")
        }
        config = try JSONDecoder().decode(ContextRunConfig.self, from: Data(contentsOf: url))
        let settings = URLSessionConfiguration.ephemeral
        settings.timeoutIntervalForRequest = 180; settings.timeoutIntervalForResource = 190
        settings.urlCache = nil; settings.httpCookieStorage = nil
        session = URLSession(configuration: settings)
    }
    func request<Input: Encodable, Output: Decodable>(_ path: String, body: Input?, as: Output.Type, timeout: Double? = nil) async throws -> Output {
        var request = URLRequest(url: config.baseURL.appendingPathComponent("v1/lab/" + namespace + "/" + path))
        if let timeout { request.timeoutInterval = max(0.1, timeout) }
        request.setValue("Bearer " + config.token, forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try ContextJSON.encoder().encode(body)
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, data.count <= 5 * 1024 * 1024 else { throw ContextError.response }
        guard response.statusCode == 200 else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw ContextError.invalid((object?["reason"] as? String) ?? "Server HTTP \(response.statusCode)")
        }
        return try ContextJSON.decoder().decode(Output.self, from: data)
    }
}

struct ChosenPlace: Identifiable, Codable {
    var prepared: DynamicPreparedPlace
    var apple: DynamicAppleCandidate
    var id: UUID { prepared.id }
    var endpoint: DynamicEndpoint { .init(preparedID: prepared.id, appleCandidateID: apple.id) }
}
struct StopDraft: Identifiable, Codable {
    var place: ChosenPlace
    var durationMinutes = 60
    var exposure = ActivityExposure.unknown
    var afternoon = false
    var avoidRain = false
    var id: UUID { place.id }
    var input: DynamicStopInput {
        .init(endpoint: place.endpoint, durationMinutes: durationMinutes, exposure: exposure,
              preferredTime: afternoon ? .init(earliest: 900, latest: 960) : nil, avoidRain: avoidRain)
    }
}
struct LiveSelection: Codable {
    var origin: ChosenPlace
    var stops: [StopDraft]
    var day: Date
    var departureMinute: Int
    var deadlineMinute: Int
}
struct AcquisitionObservation: Codable {
    var phase: String
    var identifier: String
    var clientSeconds: Double
    var count: Int
}
struct ControlledClientObservation: Codable {
    var repetition: Int
    var clientSeconds: Double
    var response: ContextExperimentResponse
}
struct LiveClientObservation: Codable {
    var label: String
    var repetition: Int
    var clientSeconds: Double
    var input: DynamicPlanInput
    var operatingBounds: [String: [OperatingInterval]]
    var response: DynamicPlanResponse
}

@MainActor @Observable final class ContextLabModel {
    var query = ""
    var results: [VenuePlace] = []
    var pending: DynamicPreparedPlace?
    var appleQuery = ""
    var choosingOrigin = false
    var origin: ChosenPlace?
    var stops: [StopDraft] = []
    var day = ContextClock.calendar.startOfDay(for: Date()).addingTimeInterval(86400)
    var departureMinute = 540
    var deadlineMinute = 1140
    var waitingMinutes = 30
    var grid = 5
    var policy = ContextSearchPolicy.firstFeasible
    var status = "Server lokal siap"
    var error: String?
    var busy = false
    var output: DynamicPlanResponse?
    var scenarios: [ContextScenario] = []
    var controlled: [ControlledClientObservation] = []
    var live: [LiveClientObservation] = []
    var acquisition: [AcquisitionObservation] = []
    var benchmarkComplete = false
    var benchmarkProgress = "Belum dijalankan"
    var selectedTab = 0
    var task: Task<Void, Never>?

    func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        error = nil; busy = true
        task = Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = true
            defer { busy = false; UIApplication.shared.isIdleTimerDisabled = false }
            do { try await operation() }
            catch is CancellationError { status = "Dibatalkan" }
            catch { self.error = error.localizedDescription; status = "Perlu diperiksa" }
        }
    }
    func search() {
        let value = query
        perform {
            self.status = "Mencari \(value)…"
            let began = ContinuousClock.now
            self.results = try await ContextAPI().request("search", body: DynamicSearchInput(query: value), as: [VenuePlace].self)
            self.acquisition.append(.init(phase: "search", identifier: value, clientSeconds: Self.seconds(began), count: self.results.count))
            try self.save(self.acquisition, name: "acquisition-observations.json")
            self.status = "\(self.results.count) hasil dari Apple Maps"
        }
    }
    func prepare(_ id: String) {
        perform {
            self.status = "Mengambil jam buka dan mencari lokasi Apple…"
            let began = ContinuousClock.now
            self.pending = try await ContextAPI().request("prepare", body: DynamicPrepareInput(placeID: id,
                                                                                               day: ContextClock.label(self.day), appleQuery: self.appleQuery.isEmpty ? nil : self.appleQuery, forOrigin: self.choosingOrigin), as: DynamicPreparedPlace.self)
            self.acquisition.append(.init(phase: "prepare", identifier: id, clientSeconds: Self.seconds(began), count: self.pending?.appleCandidates.count ?? 0))
            try self.save(self.acquisition, name: "acquisition-observations.json")
            self.status = "Konfirmasi lokasi Apple untuk routing"
        }
    }
    func confirm(_ candidate: DynamicAppleCandidate) {
        guard let pending else { return }
        let chosen = ChosenPlace(prepared: pending, apple: candidate)
        if choosingOrigin { origin = chosen }
        else if stops.count < 6 && !stops.contains(where: { $0.place.prepared.placeID == pending.placeID }) {
            stops.append(.init(place: chosen))
        }
        self.pending = nil; results = []; query = ""; appleQuery = ""
        status = choosingOrigin ? "Lokasi awal dipilih" : "\(stops.count) tujuan dipilih"
    }
    func planInput() throws -> DynamicPlanInput {
        guard let origin, !stops.isEmpty else { throw ContextError.invalid("Pilih lokasi awal dan minimal satu tujuan") }
        let base = ContextClock.calendar.startOfDay(for: day)
        return .init(origin: origin.endpoint, stops: stops.map(\.input), departure: base.addingTimeInterval(Double(departureMinute * 60)),
                     deadline: base.addingTimeInterval(Double(deadlineMinute * 60)), maximumWaitingMinutes: waitingMinutes,
                     startStepMinutes: grid, policy: policy, maxTravelCalls: 64)
    }
    func plan() {
        perform {
            self.status = "Menghitung itinerary dan ETA aktual…"
            let input = try self.planInput()
            let began = ContinuousClock.now
            let result = try await ContextAPI().request("plan", body: input, as: DynamicPlanResponse.self)
            self.output = result
            try self.recordLive(label: "manual", repetition: 1, input: input, response: result, seconds: Self.seconds(began))
            self.status = result.itinerary.visits.isEmpty ? "Belum ditemukan jadwal. Periksa detail." : "Itinerary siap ditinjau"
        }
    }
    func runControlled() {
        perform {
            self.selectedTab = 1; self.benchmarkComplete = false; self.controlled = []
            let api = try ContextAPI()
            self.scenarios = try await api.request("scenarios", body: Optional<DynamicSearchInput>.none, as: [ContextScenario].self)
            for repetition in 1 ... 3 {
                for scenario in self.scenarios {
                    try Task.checkCancellation()
                    self.benchmarkProgress = "\(self.controlled.count + 1)/\(self.scenarios.count * 3) · \(scenario.title)"
                    let began = ContinuousClock.now
                    let response = try await api.request("experiment", body: ContextExperimentInput(scenario: scenario.id), as: ContextExperimentResponse.self)
                    self.controlled.append(.init(repetition: repetition, clientSeconds: Self.seconds(began), response: response))
                    try self.save(self.controlled, name: "controlled-observations.json")
                    self.output = response.output
                }
            }
            self.benchmarkComplete = true
            self.benchmarkProgress = "Selesai · \(self.controlled.count) pengujian terkontrol"
            self.status = "Pengujian terkontrol selesai"
        }
    }
    func runSelectedBenchmark() {
        perform {
            self.benchmarkComplete = false
            let originalGrid = self.grid
            defer { self.grid = originalGrid }
            let api = try ContextAPI()
            let requested = Int(ProcessInfo.processInfo.environment["CONTEXT_LIVE_REPETITIONS"] ?? "3") ?? 3
            for repetition in 1 ... max(1, min(3, requested)) {
                for step in [15, 5] {
                    let counters = try await api.request("counters", body: Optional<DynamicSearchInput>.none, as: [String: Int].self)
                    guard (counters["etaCells"] ?? 720) + 64 <= 720 else { throw ContextError.invalid("Campaign ETA safety budget reached; saved earlier observations") }
                    self.grid = step
                    let input = try self.planInput()
                    self.benchmarkProgress = "Live \(self.stops.count) tujuan · grid \(step) · ulang \(repetition)"
                    let began = ContinuousClock.now
                    let response = try await api.request("plan", body: input, as: DynamicPlanResponse.self)
                    let seconds = Self.seconds(began)
                    self.output = response
                    try self.recordLive(label: "selected-\(self.policy.rawValue)-grid\(step)", repetition: repetition, input: input, response: response, seconds: seconds)
                }
            }
            self.benchmarkComplete = true; self.benchmarkProgress = "Selesai · benchmark live tersimpan"
        }
    }
    func loadSelectionIfRequested() {
        guard let filename = ProcessInfo.processInfo.environment["CONTEXT_SELECTION_FILE"],
              ["selection-three.json", "selection-five.json"].contains(filename) else { return }
        do {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
            let selection = try ContextJSON.decoder().decode(LiveSelection.self, from: Data(contentsOf: url))
            try FileManager.default.removeItem(at: url)
            origin = selection.origin; stops = selection.stops; day = selection.day
            departureMinute = selection.departureMinute; deadlineMinute = selection.deadlineMinute
            if let value = ProcessInfo.processInfo.environment["CONTEXT_LIVE_POLICY"], let method = ContextSearchPolicy(rawValue: value) { policy = method }
            status = "Pilihan runtime siap · \(stops.count) tujuan"
        } catch { self.error = error.localizedDescription }
    }
    private func recordLive(label: String, repetition: Int, input: DynamicPlanInput, response: DynamicPlanResponse, seconds: Double) throws {
        // Preserve prior-case checkpoints when a UI test or the user relaunches the app.
        if live.isEmpty {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ContextBenchmark/live-observations.json")
            if FileManager.default.fileExists(atPath: url.path) {
                live = try ContextJSON.decoder().decode([LiveClientObservation].self, from: Data(contentsOf: url))
            }
        }
        var sanitized = response
        let bounds = Dictionary(uniqueKeysWithValues: response.itinerary.contexts.map { ($0.placeID, $0.hours.intervals) })
        sanitized.itinerary.contexts = []
        live.append(.init(label: label, repetition: repetition, clientSeconds: seconds, input: input, operatingBounds: bounds, response: sanitized))
        try save(live, name: "live-observations.json")
    }
    func save<T: Encodable>(_ value: T, name: String) throws {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("ContextBenchmark")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try ContextJSON.encoder().encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
    }
    static func seconds(_ began: ContinuousClock.Instant) -> Double {
        let value = began.duration(to: .now).components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }
    static func time(_ date: Date) -> String {
        let c = ContextClock.calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }
}
