import Foundation
import MapKit

public struct NativeRouteValue: Sendable {
    public var seconds: Double
    public var meters: Double
    public var points: [RoutingPoint]
    public init(seconds: Double, meters: Double, points: [RoutingPoint]) { self.seconds = seconds; self.meters = meters; self.points = points }
}

/// Actual Apple Maps requests through native MapKit, independent of REST keys.
/// One operation owns its cancellation, deadline and callback identity.
@MainActor public final class AppleNativeRoutingProvider: RoutingProvider {
    public let name = "apple_mapkit_live"
    public private(set) var requests = 0
    public private(set) var lastPacingSeconds = 0.0
    private let limit: Int
    private let spacing: Duration
    private var nextRequest: ContinuousClock.Instant?
    private var busy = false
    private var token: UUID?
    private var directions: MKDirections?
    private var continuation: CheckedContinuation<NativeRouteValue, any Error>?
    private var timeoutTask: Task<Void, Never>?
    public var timeout: Duration = .seconds(25)
    public var start: @MainActor (MKDirections, @escaping @Sendable (Result<NativeRouteValue, RoutingFailure>) -> Void) -> Void = { operation, completion in
        operation.calculate { response, error in
            if let error {
                if let mapError = error as? MKError {
                    if mapError.code == .loadingThrottled { completion(.failure(.throttled)); return }
                    if mapError.code == .directionsNotFound { completion(.failure(.unavailable)); return }
                }
                completion(.failure(.transport)); return
            }
            guard let route = response?.routes.first, (2 ... 100000).contains(route.polyline.pointCount) else { completion(.failure(.unavailable)); return }
            let buffer = route.polyline.points()
            let points = (0 ..< route.polyline.pointCount).map { i in
                let c = buffer[i].coordinate; return RoutingPoint(c.latitude, c.longitude)
            }
            completion(.success(.init(seconds: route.expectedTravelTime, meters: route.distance, points: points)))
        }
    }
    public init(limit: Int = 320, spacing: Duration = .milliseconds(1200)) { self.limit = limit; self.spacing = spacing }
    public func route(_ query: RoutingQuery) async throws -> RoutingResult? {
        guard !busy else { throw RoutingFailure.invalidInput }
        busy = true; defer { busy = false }; lastPacingSeconds = 0
        try Task.checkCancellation(); try query.validate()
        guard let from = query.from.point, let to = query.to.point, token == nil else { throw RoutingFailure.invalidInput }
        guard requests < limit else { throw RoutingFailure.budgetExhausted }
        let pacingStart = ContinuousClock.now
        if let nextRequest { try await Task.sleep(until: nextRequest, clock: .continuous) }
        lastPacingSeconds = RoutingFixtures.seconds(pacingStart)
        try Task.checkCancellation()
        guard token == nil, requests < limit else { throw RoutingFailure.budgetExhausted }
        nextRequest = .now.advanced(by: spacing)
        requests += 1
        let request = MKDirections.Request()
        request.source = MKMapItem(location: .init(latitude: from.latitude, longitude: from.longitude), address: nil)
        request.destination = MKMapItem(location: .init(latitude: to.latitude, longitude: to.longitude), address: nil)
        request.transportType = query.mode == .walking ? .walking : .automobile
        request.departureDate = query.departure; request.requestsAlternateRoutes = false
        let operation = MKDirections(request: request), id = UUID()
        let value = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NativeRouteValue, any Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation; token = id; directions = operation
                timeoutTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: self?.timeout ?? .seconds(25)) } catch { return }
                    self?.finish(id, .failure(RoutingFailure.deadlineExceeded))
                }
                start(operation) { [weak self] result in
                    Task { @MainActor in self?.finish(id, result.mapError { $0 as any Error }) }
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.finish(id, .failure(CancellationError())) }
        }
        try Task.checkCancellation()
        guard let first = value.points.first, let last = value.points.last,
              first.distance(to: from) <= 100, last.distance(to: to) <= 100 else { throw RoutingFailure.invalidResponse }
        return try .init(query: query, seconds: value.seconds, meters: value.meters, snappedFrom: first, snappedTo: last, geometry: query.geometry ? value.points : [], source: name, traffic: "Apple expectedTravelTime at requested departure; field accuracy not measured")
    }
    private func finish(_ id: UUID, _ result: Result<NativeRouteValue, any Error>) {
        guard token == id, let continuation else { return }
        token = nil; self.continuation = nil
        timeoutTask?.cancel(); timeoutTask = nil
        directions?.cancel(); directions = nil
        continuation.resume(with: result)
    }
}
