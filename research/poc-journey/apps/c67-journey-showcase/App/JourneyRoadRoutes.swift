import CoreLocation
import Foundation
import MapKit
import Observation
import TripIntegration

struct JourneyRoadSegment: Identifiable, Sendable {
    var from: PlacePin
    var to: PlacePin
    var walking: Bool
    var id: String { "\(walking):\(from.latitude),\(from.longitude)>\(to.latitude),\(to.longitude)" }

    static func segments(plan: IntegratedPlan?, focusedLegID: String?) -> [Self] {
        guard let plan else { return [] }
        var segments: [Self] = []
        for (index, leg) in plan.legs.enumerated() where leg.providerStatus == "available" && (focusedLegID == nil || leg.id == focusedLegID) {
            if let journey = leg.busway {
                segments += journey.walks.filter { WeatherPolicy.distance($0.from, $0.to) > 1 }
                    .map { .init(from: $0.from, to: $0.to, walking: true) }
            } else {
                guard plan.feasible else { continue }
                let origin = plan.prepared.locations.first { $0.id == "origin" }?.selected
                let from = index == 0 ? origin : (plan.stops.indices.contains(index - 1) ? plan.stops[index - 1].pin : nil)
                let to = plan.stops.indices.contains(index) ? plan.stops[index].pin : origin
                if let from, let to { segments.append(.init(from: from, to: to, walking: leg.mode == "walking")) }
            }
        }
        var seen = Set<String>()
        return segments.filter { seen.insert($0.id).inserted }
    }
}

@MainActor @Observable final class JourneyRoadRoutes {
    private(set) var paths: [String: [BuswayMapPoint]] = [:]
    private(set) var failures: [String: String] = [:]
    private var consumers: [UUID: Set<String>] = [:]
    private var work: [String: Task<Void, Never>] = [:]
    private var generations: [String: UUID] = [:]
    private var nextRequest = Date.distantPast
    private let replay: Bool
    var sourceLabel: String { replay ? "Jalur tes sintetis" : "Jalur jalan MapKit" }
    private let fetch: @MainActor (JourneyRoadSegment) async throws -> [BuswayMapPoint]

    init(replay: Bool = false, fetch: @escaping @MainActor (JourneyRoadSegment) async throws -> [BuswayMapPoint] = { segment in
        try await JourneyRoadOperation().calculate(segment)
    }) {
        self.replay = replay
        self.fetch = fetch
    }

    func subscribe(_ owner: UUID, segments: [JourneyRoadSegment]) {
        consumers[owner] = Set(segments.map(\.id))
        cancelUnused()
        for segment in segments where paths[segment.id] == nil && failures[segment.id] == nil && work[segment.id] == nil {
            let token = UUID()
            generations[segment.id] = token
            let reserved = max(Date.now, nextRequest)
            nextRequest = reserved.addingTimeInterval(replay ? 0 : 1.2)
            work[segment.id] = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let delay = reserved.timeIntervalSinceNow
                    if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
                    try Task.checkCancellation()
                    let points = try await fetch(segment)
                    try Task.checkCancellation()
                    try Self.validate(points, for: segment)
                    guard generations[segment.id] == token else { return }
                    paths[segment.id] = points
                } catch is CancellationError {
                } catch {
                    if generations[segment.id] == token { failures[segment.id] = "\(segment.from.name) → \(segment.to.name). \(error.localizedDescription)" }
                }
                if generations[segment.id] == token { work[segment.id] = nil }
            }
        }
    }

    func release(_ owner: UUID) {
        consumers[owner] = nil
        cancelUnused()
    }

    func cancel() {
        for task in work.values { task.cancel() }
        work = [:]; generations = [:]; consumers = [:]
        nextRequest = .distantPast
    }

    func retry(_ owner: UUID, segments: [JourneyRoadSegment]) {
        for segment in segments { failures[segment.id] = nil }
        subscribe(owner, segments: segments)
    }

    private func cancelUnused() {
        let needed = consumers.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        for key in Array(work.keys) where !needed.contains(key) {
            work[key]?.cancel(); work[key] = nil; generations[key] = nil
        }
        if work.isEmpty { nextRequest = .distantPast }
    }

    static func validate(_ points: [BuswayMapPoint], for segment: JourneyRoadSegment) throws {
        guard (2 ... 100_000).contains(points.count), points.allSatisfy({
            $0.latitude.isFinite && $0.longitude.isFinite && (-90 ... 90).contains($0.latitude) && (-180 ... 180).contains($0.longitude)
        }), let first = points.first, let last = points.last else {
            throw IntegrationError.invalid("Geometri rute jalan tidak valid.")
        }
        let start = CLLocation(latitude: first.latitude, longitude: first.longitude)
        let finish = CLLocation(latitude: last.latitude, longitude: last.longitude)
        guard start.distance(from: .init(latitude: segment.from.latitude, longitude: segment.from.longitude)) <= 250,
              finish.distance(from: .init(latitude: segment.to.latitude, longitude: segment.to.longitude)) <= 250 else {
            throw IntegrationError.invalid("Ujung rute jalan tidak cocok dengan ruas perjalanan.")
        }
    }

    static func testReplay() -> JourneyRoadRoutes {
        JourneyRoadRoutes(replay: true) { segment in
            // Explicit test geometry, isolated from normal Demo/Live presentation.
            [.init(latitude: segment.from.latitude, longitude: segment.from.longitude),
             .init(latitude: segment.from.latitude, longitude: segment.to.longitude),
             .init(latitude: segment.to.latitude, longitude: segment.to.longitude)]
        }
    }
}

/// Owns native cancellation and a timeout even when the directions callback never arrives.
@MainActor final class JourneyRoadOperation {
    private var requestID: UUID?
    private var directions: MKDirections?
    private var continuation: CheckedContinuation<[BuswayMapPoint], any Error>?
    private var timeoutTask: Task<Void, Never>?
    var timeout: Duration = .seconds(25)
    var start: @MainActor (MKDirections, @escaping @Sendable (Result<[BuswayMapPoint], any Error>) -> Void) -> Void = { directions, completion in
        directions.calculate { response, error in
            let result = Result<[BuswayMapPoint], any Error> {
                if let error { throw error }
                guard let route = response?.routes.first, (2 ... 100_000).contains(route.polyline.pointCount) else {
                    throw IntegrationError.invalid("MapKit belum menyediakan jalur jalan untuk ruas ini.")
                }
                let points = route.polyline.points()
                return (0 ..< route.polyline.pointCount).map { index in
                    let coordinate = points[index].coordinate
                    return .init(latitude: coordinate.latitude, longitude: coordinate.longitude)
                }
            }
            completion(result)
        }
    }

    func calculate(_ segment: JourneyRoadSegment) async throws -> [BuswayMapPoint] {
        try Task.checkCancellation()
        guard continuation == nil else { throw IntegrationError.invalid("Permintaan rute jalan masih berjalan.") }
        let token = UUID()
        let request = MKDirections.Request()
        request.source = MKMapItem(location: .init(latitude: segment.from.latitude, longitude: segment.from.longitude), address: nil)
        request.destination = MKMapItem(location: .init(latitude: segment.to.latitude, longitude: segment.to.longitude), address: nil)
        request.transportType = segment.walking ? .walking : .automobile
        request.requestsAlternateRoutes = false
        let operation = MKDirections(request: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation; directions = operation; requestID = token
                timeoutTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: self?.timeout ?? .seconds(25)) } catch { return }
                    self?.finish(token, .failure(URLError(.timedOut)))
                }
                start(operation) { [weak self] result in
                    Task { @MainActor in self?.finish(token, result) }
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.finish(token, .failure(CancellationError())) }
        }
    }

    private func finish(_ token: UUID, _ result: Result<[BuswayMapPoint], any Error>) {
        guard requestID == token, let continuation else { return }
        self.continuation = nil; requestID = nil
        timeoutTask?.cancel(); timeoutTask = nil
        directions?.cancel(); directions = nil
        continuation.resume(with: result)
    }
}
