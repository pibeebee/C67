import CoreLocation
import Foundation
import MapKit

@MainActor public final class MapKitBuswayWalking: BuswayWalking {
    private static var nextRequest = Date.distantPast
    public private(set) var requests = 0
    public let synthetic = false
    public private(set) var failures: [String] = []
    private var operation: MKDirections?
    private var operationID: UUID?
    private var continuation: CheckedContinuation<BuswayWalk?, any Error>?
    private var timeoutTask: Task<Void, Never>?
    // Internal seams exercise missing and late callbacks without provider traffic.
    var requestTimeout: Duration = .seconds(25)
    var maximumAttempts = 2
    private var transientFailure = false
    var startRequest: @MainActor (MKDirections, @escaping @Sendable (MKDirections.ETAResponse?, (any Error)?) -> Void) -> Void = { operation, handler in
        operation.calculateETA(completionHandler: handler)
    }
    public init() {}
    public func cancel() {
        if let token = operationID { finish(token, result: .failure(CancellationError())) }
    }

    private func finish(_ token: UUID, result: Result<BuswayWalk?, any Error>) {
        guard operationID == token, let continuation else { return }
        self.continuation = nil
        operationID = nil
        timeoutTask?.cancel(); timeoutTask = nil
        let completed = operation; operation = nil
        completed?.cancel()
        continuation.resume(with: result)
    }

    public func walk(from: PlacePin, to: PlacePin, departure: Date) async throws -> BuswayWalk? {
        for attempt in 0 ..< maximumAttempts {
            transientFailure = false
            let result = try await attemptWalk(from: from, to: to, departure: departure)
            if result != nil || !transientFailure || attempt + 1 == maximumAttempts { return result }
        }
        return nil
    }

    private func attemptWalk(from: PlacePin, to: PlacePin, departure: Date) async throws -> BuswayWalk? {
        try Task.checkCancellation()
        guard requests < 128 else {
            failures.append("Batas 128 request walking per perhitungan tercapai.")
            return nil
        }
        let reserved = max(Date.now, Self.nextRequest)
        Self.nextRequest = reserved.addingTimeInterval(1.2)
        let delay = reserved.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
        request.transportType = .walking
        request.departureDate = departure
        let operation = MKDirections(request: request)
        let token = UUID()
        requests += 1
        do {
            let value = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<BuswayWalk?, any Error>) in
                    guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                    self.operation = operation; operationID = token; self.continuation = continuation
                    timeoutTask = Task { @MainActor [weak self] in
                        do { try await Task.sleep(for: self?.requestTimeout ?? .seconds(25)) } catch { return }
                        self?.finish(token, result: .failure(URLError(.timedOut)))
                    }
                    startRequest(operation) { [weak self] response, error in
                        // Transfer only Sendable values from MapKit's completion callback.
                        let result = Result<BuswayWalk?, any Error> {
                            if let error { throw error }
                            guard let response, response.transportType.contains(.walking), response.expectedTravelTime.isFinite,
                                  response.expectedTravelTime >= 0, response.distance.isFinite, response.distance >= 0 else {
                                throw IntegrationError.invalid("Respons walking MapKit tidak valid.")
                            }
                            return BuswayWalk(from: from, to: to, seconds: ceil(response.expectedTravelTime),
                                              distanceMeters: response.distance, provider: "mapkit_walking")
                        }
                        Task { @MainActor in self?.finish(token, result: result) }
                    }
                }
            } onCancel: { [weak self] in
                Task { @MainActor in self?.finish(token, result: .failure(CancellationError())) }
            }
            try Task.checkCancellation()
            return value
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            let code = (error as? URLError)?.code
            transientFailure = code == .timedOut || code == .networkConnectionLost || code == .cannotConnectToHost
            failures.append("\(from.name) → \(to.name): \(ProviderDiagnostics.message(error))")
            return nil
        }
    }
}

/// Authored walking timings for replay and regression tests only.
@MainActor public final class BuswayReplayWalking: BuswayWalking {
    public private(set) var requests = 0
    public let synthetic = true
    public let failures: [String] = []
    public init() {}
    public func cancel() {}
    public func walk(from: PlacePin, to: PlacePin, departure: Date) async throws -> BuswayWalk? {
        try Task.checkCancellation()
        requests += 1
        let distance = WeatherPolicy.distance(from, to)
        return .init(from: from, to: to, seconds: ceil(distance / 1.2),
                     distanceMeters: distance, provider: "synthetic_walking")
    }
}
