import Foundation

/// Narrow shared entry point: the existing planner retains all TJ search and access rules.
@MainActor public final class BuswayRoutingService {
    private let planner: BuswayPlanner
    public var searchLimited: Bool { planner.searchLimited }
    public init(feed: BuswayFeed, walking: any BuswayWalking, now: Date = .now) throws {
        planner = try BuswayPlanner(feed: feed, walking: walking, now: now)
    }
    public func route(from: PlacePin, to: PlacePin, departure: Date) async throws -> BuswayJourney? {
        try Task.checkCancellation()
        if let walk = try await planner.directWalk(from: from, to: to, departure: departure), walk.seconds <= 900 { return walk }
        return try await planner.bus(from: from, to: to, departure: departure)
    }
}
