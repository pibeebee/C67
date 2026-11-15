import Foundation
import Testing
@testable import TripIntegration

@Suite("Shared TJ routing facade", .serialized) @MainActor struct BuswayRoutingServiceTests {
    @Test func directWalkingAndUnavailableDirectionReuseExistingRules() async throws {
        let helper = BuswayTests(); let (feed, now, departure) = try helper.context()
        let selected = helper.restricted(feed, patternID: "1-P97")
        let routing = try BuswayRoutingService(feed: selected, walking: BuswayReplayWalking(), now: now)
        let direct = try #require(try await routing.route(from: helper.pin(feed, "G00031"), to: helper.pin(feed, "P00017"), departure: departure))
        #expect(direct.rides.count == 1); try direct.validate()
        let reverse = try await routing.route(from: helper.pin(feed, "P00017"), to: helper.pin(feed, "G00031"), departure: departure)
        #expect(reverse == nil)
        let walking = try #require(try await routing.route(from: helper.pin(feed, "G00031"), to: helper.pin(feed, "G00031"), departure: departure))
        #expect(walking.rides.isEmpty)
        #expect(throws: (any Error).self) { try BuswayRoutingService(feed: feed, walking: BuswayReplayWalking(), now: now.addingTimeInterval(8 * 86400)) }
    }
}
