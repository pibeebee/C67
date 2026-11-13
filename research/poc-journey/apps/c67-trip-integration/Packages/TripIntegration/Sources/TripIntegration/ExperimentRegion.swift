import Foundation

/// Dated experiment boundary and branch anchors, separate from historical Jakarta coverage.
public struct ExperimentRegion: Codable, Sendable {
    public struct VenueAnchor: Codable, Sendable {
        public var candidateID: String
        public var pin: PlacePin
    }
    public var id: String
    public var center: PlacePin
    public var radiusMeters: Double
    public var branchRadiusMeters: Double
    public var anchors: [VenueAnchor]
    public var coordinateEvidence: String

    public func validate(candidateIDs: Set<String>) throws {
        guard !id.isEmpty, radiusMeters == 1500, branchRadiusMeters > 0,
              branchRadiusMeters <= 150, IntegrationCatalog.contains(center),
              Set(anchors.map(\.candidateID)) == candidateIDs, anchors.count == candidateIDs.count,
              anchors.allSatisfy({ IntegrationCatalog.contains($0.pin)
                      && WeatherPolicy.distance(center, $0.pin) <= radiusMeters }) else {
            throw IntegrationError.invalid("Batas atau identitas katalog eksperimen tidak valid.")
        }
    }
    public func contains(_ pin: PlacePin, candidateID: String) -> Bool {
        guard let anchor = anchors.first(where: { $0.candidateID == candidateID }),
              IntegrationCatalog.contains(pin) else { return false }
        return WeatherPolicy.distance(center, pin) <= radiusMeters
            && WeatherPolicy.distance(anchor.pin, pin) <= branchRadiusMeters
    }
}
