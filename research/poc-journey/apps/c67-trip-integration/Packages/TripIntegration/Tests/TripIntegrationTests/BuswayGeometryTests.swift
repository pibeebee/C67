import Foundation
import Testing
@testable import TripIntegration

@Suite("GTFS geometry preserves route occurrences")
struct BuswayGeometryTests {
    @Test func networkGeometryPreservesCoverageAndOrderedEndpoints() throws {
        let feed = try BuswayFeed.network()
        let geometry = try BuswayGeometryCatalog.load(network: true)
        try geometry.validate(feed: feed)
        #expect(geometry.patterns.count == 542)
        #expect(Set(feed.patterns.map(\.id)).subtracting(geometry.patterns.map(\.id)) == ["JAK.59-R03", "3H-R06"])
        let pattern = try #require(feed.patterns.first { $0.effectiveRouteID == "2" })
        let first = try #require(pattern.calls.first)
        let last = try #require(pattern.calls.last)
        let board = try #require(feed.stops.first { $0.id == first.stopID })
        let alight = try #require(feed.stops.first { $0.id == last.stopID })
        let day = TripClock.calendar.startOfDay(for: feed.source.checkedAt)
        let ride = BuswayRide(pattern: pattern, patternID: pattern.id, headsign: pattern.headsign, directionID: pattern.directionID,
                              board: board, alight: alight, boardSequence: first.sequence, alightSequence: last.sequence,
                              boardOffset: first.departureOffset, alightOffset: last.arrivalOffset,
                              service: feed.services.first { $0.id == pattern.serviceID }!, serviceDay: day,
                              frequency: pattern.frequencies[0], boardAt: day, alightAt: day)
        let segment = try geometry.segment(for: ride, source: feed.source)
        #expect(segment.points.count > 2)
        #expect(segment.stops.first?.id == board.id && segment.stops.last?.id == alight.id)
    }
    @Test func allPatternsHaveBoundedOrderedShapeMatches() throws {
        let feed = try BuswayFeed.load()
        let geometry = try BuswayGeometryCatalog.load()
        try geometry.validate(feed: feed)
        #expect(geometry.patterns.count == 18)
        #expect(geometry.patterns.reduce(0) { $0 + $1.points.count } == 4366)
    }
    @Test func mismatchedSourceAndBackwardProjectionAreRejected() throws {
        let feed = try BuswayFeed.load()
        var geometry = try BuswayGeometryCatalog.load()
        geometry.sourceSHA256 = String(repeating: "0", count: 64)
        #expect(throws: (any Error).self) { try geometry.validate(feed: feed) }
        geometry = try .load()
        geometry.patterns[0].calls[0].pointIndex = geometry.patterns[0].points.count - 1
        #expect(throws: (any Error).self) { try geometry.validate(feed: feed) }
    }
    @Test func loopReturnsDifferentGeometryForRepeatedStopOccurrences() throws {
        let feed = try BuswayFeed.load()
        let geometry = try BuswayGeometryCatalog.load()
        let pattern = try #require(feed.patterns.first { $0.id == "1-P28" })
        let mapped = try #require(geometry.patterns.first { $0.id == pattern.id })
        let visits = mapped.calls.filter { $0.stopID == "P00017" }
        #expect(visits.count == 2)
        #expect(visits[0].pointIndex < visits[1].pointIndex)
        let board = try #require(feed.stops.first { $0.id == "G00031" })
        let alight = try #require(feed.stops.first { $0.id == "P00017" })
        let day = TripClock.calendar.startOfDay(for: feed.source.checkedAt)
        let ride = BuswayRide(pattern: pattern, patternID: pattern.id, headsign: pattern.headsign, directionID: pattern.directionID,
                              board: board, alight: alight, boardSequence: 17, alightSequence: 27,
                              boardOffset: 3360, alightOffset: 5389,
                              service: feed.services.first { $0.id == pattern.serviceID }!, serviceDay: day,
                              frequency: pattern.frequencies[0], boardAt: day, alightAt: day)
        let segment = try geometry.segment(for: ride, source: feed.source)
        #expect(segment.stops.first?.id == board.id)
        #expect(segment.stops.last?.id == alight.id)
        #expect(segment.stops.count == 11)
        #expect(segment.points.first == mapped.points[mapped.calls.first { $0.sequence == 17 }!.pointIndex])
        #expect(segment.points.last == mapped.points[visits[1].pointIndex])
    }
}
