import Foundation
import PlaceContextEngine
import PlannerEngine

/// An operator-confirmed association of a venue identity with an independently
/// searched Apple pin. The pin is resolved by Apple Maps.
public struct PilotIdentity: Codable, Sendable {
    public var internalID: String
    public var placeID: String?
    public var applePin: PlacePin
    public var evidence: String
    public var confirmedAt: Date
    public init(internalID: String, placeID: String?, applePin: PlacePin, evidence: String, confirmedAt: Date) {
        self.internalID = internalID; self.placeID = placeID; self.applePin = applePin
        self.evidence = evidence; self.confirmedAt = confirmedAt
    }
}

@MainActor public final class AppleContextTravelAdapter: ContextTravelProvider {
    private let identities: [String: PilotIdentity]
    private let provider: any LabETAProvider
    public private(set) var providerWallSeconds = 0.0
    public var metrics: LabProviderMetrics { provider.metrics }
    public init(identities: [PilotIdentity], provider: any LabETAProvider, now: Date = .now)throws {
        guard Set(identities.map(\.internalID)).count == identities.count,
              identities.allSatisfy({ identity in
                  let pin = identity.applePin
                  return !identity.internalID.isEmpty && !identity.evidence.isEmpty &&
                      pin.source == "Apple Maps Server API" && pin.latitude.isFinite && pin.longitude.isFinite &&
                      (-6.6 ... -5.9).contains(pin.latitude) && (106.5 ... 107.2).contains(pin.longitude) &&
                      identity.confirmedAt <= now && now.timeIntervalSince(identity.confirmedAt) < 86400
              }) else { throw ContextError.invalid("Pilot requires unique, fresh, evidenced Jakarta Apple identities") }
        self.identities = Dictionary(uniqueKeysWithValues: identities.map { ($0.internalID, $0) }); self.provider = provider
    }
    public func travel(from: String, to: String, departure: Date) async throws -> ContextTravelTime? {
        guard let a = identities[from]?.applePin, let b = identities[to]?.applePin else {
            throw ContextError.invalid("Missing explicit Apple identity mapping")
        }
        let query = LabETAQuery(fromID: from, toID: to, fromLatitude: a.latitude, fromLongitude: a.longitude,
                                toLatitude: b.latitude, toLongitude: b.longitude, mode: "automobile", departure: departure)
        let began = ContinuousClock.now
        defer { let c = began.duration(to: .now).components; providerWallSeconds += Double(c.seconds) + Double(c.attoseconds) / 1e18 }
        let values = try await provider.values([query])
        if values.contains(where: { $0.note.contains("HTTP 403") }) {
            throw LabRESTError.status(403, retryAfter: nil)
        }
        guard values.count == 1, let v = values.first, v.query == query, v.status == "available",
              let seconds = v.seconds, seconds.isFinite, seconds >= 0 else { return nil }
        return .init(seconds: seconds, departure: departure, source: "Apple Maps Server API; Automobile; exact leg departure; independent Apple pin")
    }
}

public enum AppleContextWeatherAdapter {
    public static func convert(_ evidence: WeatherEvidence, now: Date = .now) -> VisitWeatherContext? {
        guard evidence.complete, evidence.provider == "weatherkit", evidence.expiresAt > now,
              evidence.retrievedAt <= now.addingTimeInterval(300),
              let credit = evidence.credit else { return nil }
        return .init(source: "WeatherKit; \(credit.name); \(credit.legalURL.absoluteString)",
                     fetchedAt: evidence.fetchedAt, expiresAt: evidence.expiresAt, hours: evidence.hours.map {
                         .init(start: $0.start, rainProbability: $0.rainChance, temperatureC: $0.temperatureC)
                     })
    }
}
