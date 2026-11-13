import Foundation
import PlaceContextEngine
import PlannerEngine
import TripIntegration

@MainActor public final class RESTBuswayWalking: BuswayWalking {
    private let provider: any LabETAProvider
    public private(set) var requests = 0
    public let synthetic: Bool
    public private(set) var failures: [String] = []
    private var cancelled = false
    public init(provider: any LabETAProvider, synthetic: Bool = false) { self.provider = provider; self.synthetic = synthetic }
    public func cancel() { cancelled = true }
    public func walk(from: TripIntegration.PlacePin, to: TripIntegration.PlacePin, departure: Date) async throws -> BuswayWalk? {
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        guard requests < 128 else { failures.append("walking_budget_exhausted"); return nil }
        requests += 1
        let query = LabETAQuery(fromID: from.id, toID: to.id, fromLatitude: from.latitude, fromLongitude: from.longitude, toLatitude: to.latitude, toLongitude: to.longitude, mode: "walking", departure: departure)
        let values = try await provider.values([query])
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        guard values.count == 1, let value = values.first, value.query == query, value.status == "available", let seconds = value.seconds, seconds.isFinite, seconds >= 0, let distance = value.distance, distance.isFinite, distance >= 0 else {
            failures.append("walking_provider_unavailable"); return nil
        }
        return .init(from: from, to: to, seconds: seconds, distanceMeters: distance, provider: synthetic ? "synthetic_walking" : "apple_maps_rest_walking")
    }
}

@MainActor public final class BuswayContextAdapter: MeasuredContextTravelProvider {
    private let identities: [String: PilotIdentity]
    private let routing: BuswayRoutingService
    private let geometry: BuswayGeometryCatalog?
    public private(set) var providerWallSeconds = 0.0
    public init(identities: [PilotIdentity], provider: any LabETAProvider, feed: BuswayFeed? = nil, now: Date = .now, synthetic: Bool = false) throws {
        _ = try AppleContextTravelAdapter(identities: identities, provider: provider, now: now)
        self.identities = Dictionary(uniqueKeysWithValues: identities.map { ($0.internalID, $0) })
        routing = try BuswayRoutingService(feed: try feed ?? BuswayFeed.network(), walking: RESTBuswayWalking(provider: provider, synthetic: synthetic), now: now)
        geometry = try? BuswayGeometryCatalog.load(network: feed == nil)
    }
    public func travel(from: String, to: String, departure: Date) async throws -> ContextTravelTime? {
        let began = ContinuousClock.now
        defer { let d = began.duration(to: .now).components; providerWallSeconds += Double(d.seconds) + Double(d.attoseconds) / 1e18 }
        guard let a = identities[from]?.applePin, let b = identities[to]?.applePin else { throw ContextError.invalid("Missing confirmed Apple identity") }
        func pin(_ value: PlannerEngine.PlacePin) -> TripIntegration.PlacePin {
            .init(id: value.id, name: value.name, address: value.address, latitude: value.latitude, longitude: value.longitude)
        }
        guard let journey = try await routing.route(from: pin(a), to: pin(b), departure: departure) else { return nil }
        try journey.validate()
        func point(_ value: TripIntegration.PlacePin) -> ContextRoutePoint { .init(latitude: value.latitude, longitude: value.longitude) }
        var segments: [ContextRouteSegment] = []
        for (index, walk) in journey.walks.enumerated() {
            let start: Date
            if index == 0 { start = journey.departure }
            else if journey.connection != nil && index == 1 { start = journey.ride!.alightAt.addingTimeInterval(journey.connection!.bufferSeconds) }
            else { start = journey.rides.last?.alightAt ?? journey.departure }
            segments.append(.init(id: "walk-\(index)", kind: "walking", label: "Jalan kaki: \(walk.from.name) → \(walk.to.name)", from: point(walk.from), to: point(walk.to), departure: start, arrival: start.addingTimeInterval(walk.seconds)))
        }
        for (index, ride) in journey.rides.enumerated() {
            let shape = try? geometry?.segment(for: ride, source: journey.source)
            segments.append(.init(id: "bus-\(index)", kind: "bus", label: "TJ \(ride.pattern.effectiveRouteID) · \(ride.headsign): \(ride.board.name) → \(ride.alight.name)", from: point(ride.board.pin), to: point(ride.alight.pin), points: shape?.points.map { .init(latitude: $0.latitude, longitude: $0.longitude) } ?? [], geometryStatus: shape == nil ? "unavailable" : "gtfs_shape", departure: ride.boardAt, arrival: ride.alightAt))
        }
        // Interleave access, rides, transfer walking, and egress for the review/map.
        let ordered: [String] = journey.rides.count == 2 ? ["walk-0", "bus-0", "walk-1", "bus-1", "walk-2"] : (journey.rides.isEmpty ? ["walk-0"] : ["walk-0", "bus-0", "walk-1"])
        segments.sort { ordered.firstIndex(of: $0.id)! < ordered.firstIndex(of: $1.id)! }
        var details = ContextTransportDetails(mode: journey.rides.isEmpty ? "walking" : "transjakarta", walkingSeconds: journey.walkingSeconds, transitWaitingSeconds: max(0, journey.waitingSeconds), summary: journey.summary, segments: segments, sourceSHA256: journey.source.sourceSHA256, searchLimited: routing.searchLimited)
        details.attributionURL = journey.source.attributionURL; details.licenseURL = journey.source.licenseURL
        details.sourceCheckedAt = journey.source.checkedAt; details.sourcePublisher = journey.source.publisher
        return .init(seconds: journey.seconds, departure: departure, source: "TJ attributed GTFS; estimated full headway; " + journey.source.sourceURL.absoluteString, details: details)
    }
}
