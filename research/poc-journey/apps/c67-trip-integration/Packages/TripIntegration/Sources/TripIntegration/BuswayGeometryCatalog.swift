import Foundation

public struct BuswayMapPoint: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude; self.longitude = longitude
    }
}

public struct BuswayMapSegment: Sendable {
    public var points: [BuswayMapPoint]
    public var stops: [BuswayStop]
}

public struct BuswayGeometryCatalog: Codable, Sendable {
    // The immutable bundled snapshot is shared by map redraws, separate from freshness checks.
    private static let bundledFeed = Result { try BuswayFeed.load() }
    private static let bundledNetwork = Result { try BuswayFeed.network() }
    public struct Call: Codable, Sendable {
        public var stopID: String
        public var sequence: Int
        public var pointIndex: Int
    }
    public struct Pattern: Codable, Sendable {
        public var id: String
        public var shapeID: String
        public var points: [BuswayMapPoint]
        public var calls: [Call]
    }
    public var schemaVersion: Int
    public var sourceSHA256: String
    public var patterns: [Pattern]

    public static func load(network: Bool = false) throws -> Self {
        guard let url = Bundle.module.url(forResource: network ? "transjakarta-network-geometry" : "transjakarta-corridor-1-geometry", withExtension: "json") else {
            throw IntegrationError.invalid("Geometri GTFS belum tersedia.")
        }
        let value = try IntegrationJSON.decoder().decode(Self.self, from: Data(contentsOf: url))
        try value.validate(feed: (network ? Self.bundledNetwork : Self.bundledFeed).get())
        return value
    }

    public func validate(feed: BuswayFeed) throws {
        try feed.validate()
        let ids = Set(patterns.map(\.id)), sourceIDs = Set(feed.patterns.map(\.id))
        guard [1, 2].contains(schemaVersion), sourceSHA256 == feed.source.sourceSHA256,
              ids.count == patterns.count, !patterns.isEmpty,
              (schemaVersion == 1 ? ids == sourceIDs : ids.isSubset(of: sourceIDs)) else {
            throw IntegrationError.invalid("Sumber geometri berbeda dari sumber routing GTFS.")
        }
        let stops = Dictionary(uniqueKeysWithValues: feed.stops.map { ($0.id, $0) })
        for pattern in patterns {
            guard let original = feed.patterns.first(where: { $0.id == pattern.id }),
                  pattern.shapeID == original.shapeID, pattern.points.count >= 2,
                  pattern.calls.count == original.calls.count,
                  pattern.points.allSatisfy({ $0.latitude.isFinite && $0.longitude.isFinite
                          && (-6.5 ... -5.9).contains($0.latitude) && (106.5 ... 107.1).contains($0.longitude) }),
                  zip(pattern.calls, pattern.calls.dropFirst()).allSatisfy({ $0.pointIndex <= $1.pointIndex }),
                  zip(pattern.calls, original.calls).allSatisfy({ mapped, source in
                      guard mapped.stopID == source.stopID, mapped.sequence == source.sequence,
                            pattern.points.indices.contains(mapped.pointIndex), let stop = stops[source.stopID] else { return false }
                      let point = pattern.points[mapped.pointIndex]
                      return hypot((point.latitude - stop.latitude) * 111195, (point.longitude - stop.longitude) * 110537) <= 150.01
                  }) else { throw IntegrationError.invalid("Urutan/geometri halte tidak valid: \(pattern.id).") }
        }
    }

    public func segment(for ride: BuswayRide, source: BuswaySource) throws -> BuswayMapSegment {
        let feed = try (schemaVersion == 2 ? Self.bundledNetwork : Self.bundledFeed).get()
        guard source.sourceSHA256 == sourceSHA256,
              let original = feed.patterns.first(where: { $0.id == ride.patternID }),
              original.id == ride.pattern.id, original.shapeID == ride.pattern.shapeID,
              original.calls.map(\.stopID) == ride.pattern.calls.map(\.stopID),
              original.calls.map(\.sequence) == ride.pattern.calls.map(\.sequence),
              original.calls.map(\.arrivalOffset) == ride.pattern.calls.map(\.arrivalOffset),
              original.calls.map(\.departureOffset) == ride.pattern.calls.map(\.departureOffset),
              let pattern = patterns.first(where: { $0.id == ride.patternID }),
              let first = pattern.calls.firstIndex(where: { $0.sequence == ride.boardSequence && $0.stopID == ride.board.id }),
              let last = pattern.calls.firstIndex(where: { $0.sequence == ride.alightSequence && $0.stopID == ride.alight.id }),
              first < last else { throw IntegrationError.invalid("Segmen peta tidak cocok dengan ruas bus.") }
        let start = pattern.calls[first].pointIndex
        let end = pattern.calls[last].pointIndex
        guard start < end, pattern.points.indices.contains(start), pattern.points.indices.contains(end) else {
            throw IntegrationError.invalid("Segmen geometri bus belum tersedia.")
        }
        let stops = Dictionary(uniqueKeysWithValues: feed.stops.map { ($0.id, $0) })
        return .init(points: Array(pattern.points[start ... end]),
                     stops: pattern.calls[first ... last].compactMap { stops[$0.stopID] })
    }
}
