import Foundation
import MapKit

public enum JakartaBoundary {
    private static let polygons: [[[[Double]]]] = {
        guard let url = Bundle.module.url(forResource: "jakarta", withExtension: "geojson"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        let geometry: [String: Any]?
        if let features = root["features"] as? [[String: Any]] {
            geometry = features.first?["geometry"] as? [String: Any]
        } else {
            geometry = root["geometry"] as? [String: Any] ?? root
        }
        if geometry?["type"] as? String == "Polygon",
           let rings = geometry?["coordinates"] as? [[[Double]]]
        {
            return [rings]
        }
        return geometry?["coordinates"] as? [[[[Double]]]] ?? []
    }()
    public static func contains(latitude y: Double, longitude x: Double) -> Bool {
        guard y.isFinite, x.isFinite, (-90 ... 90).contains(y), (-180 ... 180).contains(x) else {
            return false
        }
        func ringContains(_ ring: [[Double]]) -> Bool {
            guard ring.count >= 3, ring.allSatisfy({ $0.count >= 2 }) else { return false }
            var inside = false
            for i in ring.indices {
                let a = ring[i]
                let b = ring[(i + 1) % ring.count]
                let cross = (x - a[0]) * (b[1] - a[1]) - (y - a[1]) * (b[0] - a[0])
                if abs(cross) < 1e-10 && x >= min(a[0], b[0]) && x <= max(a[0], b[0])
                    && y >= min(a[1], b[1]) && y <= max(a[1], b[1])
                {
                    return true
                }
                if (a[1] > y) != (b[1] > y), x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0] {
                    inside.toggle()
                }
            }
            return inside
        }
        return polygons.contains { rings in
            guard let shell = rings.first, ringContains(shell) else { return false }
            return !rings.dropFirst().contains(where: ringContains)
        }
    }
}

public enum TripImporter {
    public static func load(_ data: Data, source: String = "Imported routing snapshot") throws
        -> TripContextV1
    {
        guard data.count <= 5_000_000 else { throw LabError.invalid("Berkas melebihi 5 MB.") }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LabError.invalid("JSON harus berupa objek.")
        }
        if root["schemaVersion"] as? Int == 1, root["legs"] != nil, root["source"] != nil {
            let value = try JSONDecoder().decode(TripContextV1.self, from: data)
            try value.validate()
            return value
        }
        let report = root["acceptedReport"] as? [String: Any] ?? root
        guard let draft = report["draft"] as? [String: Any],
              let departure = draft["departure"] as? String,
              let zone = draft["timeZoneID"] as? String,
              let originJSON = draft["origin"] as? [String: Any],
              let stopJSON = draft["stops"] as? [[String: Any]],
              let generated = report["generatedAt"] as? String
        else {
            throw LabError.invalid("Bukan NativeTripReport atau snapshot acceptedReport yang didukung.")
        }
        func point(_ p: [String: Any]) throws -> PlaceV1 {
            guard let id = p["id"] as? String, let title = p["title"] as? String else {
                throw LabError.invalid("Identitas tempat tidak lengkap.")
            }
            return PlaceV1(
                id: id, name: p["resolvedName"] as? String ?? title,
                latitude: p["latitude"] as? Double, longitude: p["longitude"] as? Double,
                address: p["address"] as? String ?? "")
        }
        let origin = try point(originJSON)
        let returns = draft["returnsToOrigin"] as? Bool ?? true
        let endpoint = returns ? origin : try point(draft["end"] as? [String: Any] ?? [:])
        var evidence: [EvidenceV1] = []
        let synthetic = report["simulationKind"] != nil
        let stops = try stopJSON.map { stop -> VisitV1 in
            let place = try point(stop["point"] as? [String: Any] ?? [:])
            let exposure = stop["exposure"] as? String ?? "unknown"
            let dwell =
                stop["role"] as? String == "transfer"
                    ? 0 : stop["dwellOverride"] as? Int ?? draft["defaultDwell"] as? Int ?? 30
            if let opening = stop["opening"] as? [String: Any] {
                let serviceDate = opening["serviceDate"] as? String
                let timeZone = opening["timeZoneID"] as? String
                // Verify the date in the trip's time zone rather than UTC.
                let formatter = DateFormatter()
                formatter.timeZone = TimeZone(identifier: zone)
                formatter.dateFormat = "yyyy-MM-dd"
                let localMatches =
                    serviceDate == nil
                        || Codec.date(departure).map { formatter.string(from: $0) == serviceDate } == true
                if localMatches, timeZone == nil || timeZone == zone {
                    for key in ["opensMinute", "closesMinute"] {
                        if let minute = opening[key] as? Int {
                            guard (0 ... 1440).contains(minute) else {
                                throw LabError.invalid("Jam operasional tidak valid.")
                            }
                            evidence.append(
                                .init(
                                    id: "hours-\(place.id)-\(key)", subjectID: place.id, key: key,
                                    value: String(format: "%02d:%02d", minute / 60, minute % 60),
                                    source: opening["sourceNote"] as? String
                                        ?? "Manual bounds in imported snapshot (not independently verified)",
                                    observedAt: generated, synthetic: synthetic))
                        }
                    }
                }
            }
            evidence.append(
                .init(
                    id: "place-\(place.id)", subjectID: place.id, key: "identity",
                    value: place.name, source: source, observedAt: generated, synthetic: synthetic))
            return VisitV1(place: place, dwellMinutes: dwell, exposure: exposure)
        }
        let candidate =
            report["fastest"] as? [String: Any] ?? (report["candidates"] as? [[String: Any]])?.first
                ?? [:]
        let legs = try (candidate["legs"] as? [[String: Any]] ?? []).enumerated().map {
            index, leg -> LegV1 in
            let from = try point(leg["from"] as? [String: Any] ?? [:])
            let to = try point(leg["to"] as? [String: Any] ?? [:])
            let chosen = leg["chosen"] as? [String: Any]
            let seconds =
                chosen?["status"] as? String == "available" ? chosen?["seconds"] as? Double : nil
            return LegV1(
                id: leg["id"] as? String ?? "leg-\(index)", fromID: from.id, toID: to.id,
                departure: leg["departure"] as? String, arrival: leg["arrival"] as? String,
                visit: leg["visit"] as? String, leave: leg["leave"] as? String,
                travelMinutes: seconds.map { $0 / 60 }, isReturn: leg["isReturn"] as? Bool ?? false)
        }
        let finish = candidate["finish"] as? String
        let complete =
            candidate["complete"] as? Bool == true && finish != nil
                && legs.allSatisfy { $0.arrival != nil && $0.travelMinutes != nil }
                && Set(legs.filter { !$0.isReturn }.map(\.toID)) == Set(stops.map(\.id))
        let conflicts = candidate["conflicts"] as? [String] ?? []
        let elapsed: Double? =
            complete
                ? (candidate["travelMinutes"] as? Double ?? 0) + (candidate["waitingMinutes"] as? Double ?? 0)
                + (candidate["dwellMinutes"] as? Double ?? 0) : nil
        let baseline =
            "Order: \(legs.map(\.toID).joined(separator: ", ")); finish: \(finish ?? "unknown"); deadline: \(draft["finishBy"] as? String ?? "unknown"); complete: \(complete); conflicts: \(conflicts.joined(separator: "; "))"
        evidence.append(
            .init(
                id: "baseline", subjectID: "trip", key: "schedule", value: baseline,
                source: source, observedAt: generated, synthetic: synthetic))
        let forecasts = report["forecasts"] as? [[String: Any]] ?? []
        for (i, f) in forecasts.enumerated() {
            guard let id = f["pointID"] as? String, stops.contains(where: { $0.id == id }) else {
                continue
            }
            // Keep provider status and timestamp; a forecast is not an observation of actual weather.
            if let status = f["status"] as? String {
                evidence.append(
                    .init(
                        id: "forecast-status-\(i)", subjectID: id, key: "forecastStatus",
                        value: "\(status); \(f["note"] as? String ?? "")",
                        source:
                        "Imported \(f["provider"] as? String ?? "unknown provider") forecast; dated snapshot",
                        observedAt: f["fetchedAt"] as? String ?? f["retrievedAt"] as? String ?? generated,
                        synthetic: synthetic))
            }
        }
        var result = TripContextV1(
            id: Codec.hash(data), revision: root["revision"] as? Int ?? 0,
            source: source, synthetic: synthetic, generatedAt: generated, departure: departure,
            timeZoneID: zone, origin: origin, endpoint: endpoint, stops: stops, legs: legs,
            deadline: draft["finishBy"] as? String, complete: complete, conflicts: conflicts,
            uncertainties: candidate["uncertainties"] as? [String] ?? [], evidence: evidence,
            finish: complete ? finish : nil, elapsedMinutes: elapsed)
        if !complete {
            result.uncertainties.append(
                "Incomplete snapshot; no new schedule or feasibility established.")
        }
        try result.validate()
        return result
    }
}

public struct CandidateV1: Codable, Identifiable, Sendable {
    public var place: PlaceV1
    public var evidence: [EvidenceV1]
    public var id: String { place.id }
    public init(place: PlaceV1, evidence: [EvidenceV1]) {
        self.place = place
        self.evidence = evidence
    }
}
public struct SearchBatch: Codable, Sendable {
    public var candidates: [CandidateV1]
    public var queries: [String]
    public var errors: [String]
    public var source: String
    public init(
        candidates: [CandidateV1] = [], queries: [String] = [], errors: [String] = [], source: String
    ) {
        self.candidates = candidates
        self.queries = queries
        self.errors = errors
        self.source = source
    }
}
public protocol PlaceSearching: Sendable {
    func search(profile: PreferenceExtraction, context: TripContextV1) async throws -> SearchBatch
}
public enum CandidateFilter {
    public static func clean(_ candidates: [CandidateV1], excluding ids: Set<String> = [])
        -> [CandidateV1]
    {
        var seenIDs = ids
        var seenLocations = Set<String>()
        return candidates.filter { c in
            guard let lat = c.place.latitude, let lon = c.place.longitude,
                  JakartaBoundary.contains(latitude: lat, longitude: lon), !seenIDs.contains(c.id)
            else { return false }
            let key =
                c.place.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    + String(format: "%.4f,%.4f", lat, lon)
            guard seenLocations.insert(key).inserted else { return false }
            seenIDs.insert(c.id)
            return true
        }.prefix(10).map { $0 }
    }
    public static func queries(_ profile: PreferenceExtraction) -> [String] {
        let allowed = profile.interests.filter { !profile.avoids.contains($0) }
        let map: [Interest: String] = [
            .coffee: "coffee shop", .reading: "bookstore", .quiet: "library",
            .indoor: "museum", .outdoor: "park", .culture: "museum", .food: "restaurant",
            .photography: "park",
        ]
        var seen = Set<String>()
        return allowed.compactMap { map[$0] }.filter { seen.insert($0).inserted }.prefix(2).map {
            "\($0), Jakarta"
        }
    }
}
// SDK 26 does not mark MKLocalSearch Sendable. Keep cancellation on the main actor.
@MainActor private final class MapSearchCancellation {
    let search: MKLocalSearch
    init(_ search: MKLocalSearch) { self.search = search }
    func cancel() { search.cancel() }
}

public struct MapKitPlaceSearch: PlaceSearching {
    public init() {}
    public func search(profile: PreferenceExtraction, context: TripContextV1) async throws
        -> SearchBatch
    {
        let queries = CandidateFilter.queries(profile)
        var candidates: [CandidateV1] = []
        var errors: [String] = []
        for query in queries {
            try Task.checkCancellation()
            do {
                let found = try await AsyncDeadline.run(seconds: 20) { try await Self.lookup(query) }
                candidates += found
            } catch is CancellationError { throw CancellationError() } catch {
                errors.append("\(query): \(error.localizedDescription)")
            }
        }
        return SearchBatch(
            candidates: CandidateFilter.clean(candidates, excluding: Set(context.stops.map(\.id))),
            queries: queries, errors: errors,
            source: "MapKit live search; no route feasibility calculated")
    }
    @MainActor static func lookup(_ query: String) async throws -> [CandidateV1] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -6.2, longitude: 106.83),
            latitudinalMeters: 35_000, longitudinalMeters: 35_000)
        let search = MKLocalSearch(request: request)
        let cancellation = MapSearchCancellation(search)
        let response = try await withTaskCancellationHandler {
            try await search.start()
        } onCancel: {
            Task { @MainActor in cancellation.cancel() }
        }
        try Task.checkCancellation()
        let at = Date().ISO8601Format()
        return response.mapItems.map { item in
            let location = item.location.coordinate
            let name = item.name ?? "Unknown place"
            let id =
                item.identifier?.rawValue
                    ?? "mapkit-\(Codec.hash(Data("\(name)|\(location.latitude)|\(location.longitude)".utf8)).prefix(20))"
            let category = item.pointOfInterestCategory?.rawValue ?? "unknown"
            let place = PlaceV1(
                id: id, name: name, latitude: location.latitude, longitude: location.longitude,
                category: category)
            return CandidateV1(
                place: place,
                evidence: [
                    .init(
                        id: "mk-\(id)", subjectID: id, key: "identityCategory",
                        value: "\(name); category: \(category)", source: "MapKit MKLocalSearch", observedAt: at)
                ])
        }
    }
}
