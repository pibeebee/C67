import Foundation

/// A separately labelled routing experiment. Pins come from an archived real provider search.
public struct LabPinSnapshot: Codable, Sendable {
    public var schemaVersion: Int
    public var observedAt: Date
    public var evidence: String
    public var pins: [String: PlacePin]
    public var queries: [String: String]
    public func validate(now: Date) throws {
        guard schemaVersion == 1, now.timeIntervalSince(observedAt) >= -300,
              now.timeIntervalSince(observedAt) < 86400,
              Set(pins.keys) == Set(["origin", "cikini", "bdt-rbbj", "erasmus", "ragunan", "gbk"]),
              pins.values.allSatisfy(IntegrationCatalog.contains),
              Set(queries.values) == Set(pins.keys) else { throw IntegrationError.invalid("Invalid/expired shared provider pin snapshot") }
    }
}
@MainActor public final class LabPinnedSearch: TripPlaceSearching {
    let snapshot: LabPinSnapshot
    public init(snapshot: LabPinSnapshot) throws { try snapshot.validate(now: .now); self.snapshot = snapshot }
    public func cancel() {}
    public func search(query: String) async throws -> [PlacePin] {
        try Task.checkCancellation()
        guard let id = snapshot.queries[query], let pin = snapshot.pins[id] else {
            throw IntegrationError.invalid("Shared real pin snapshot does not cover this query")
        }
        return [pin]
    }
}
