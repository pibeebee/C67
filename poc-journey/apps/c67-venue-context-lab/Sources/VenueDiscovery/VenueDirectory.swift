import CryptoKit
import Foundation
import PlaceContextEngine
import PlannerEngine

@MainActor public final class VenueDirectory {
    private struct AppleResponse: Decodable {
        struct Item: Decodable {
            struct Coordinate: Decodable { var latitude: Double; var longitude: Double }
            var id: String?
            var name: String
            var coordinate: Coordinate
            var formattedAddressLines: [String]?
        }
        var results: [Item]
    }
    private struct Issued {
        var pin: PlacePin
        var expiresAt: Date
    }

    public let venues: [OpenVenue]
    public let enrichment: VenueEnrichment
    private let byID: [String: OpenVenue]
    private let apple: LabAppleREST
    private var issued: [String: Issued] = [:]

    public init(apple: LabAppleREST, enrichment: VenueEnrichment, catalogue: URL? = nil) throws {
        guard let url = catalogue ?? Bundle.module.url(forResource: "pilot-venues", withExtension: "json") else {
            throw ContextError.invalid("Katalog lokasi terbuka belum tersedia.")
        }
        let rows = try JSONDecoder().decode([OpenVenue].self, from: Data(contentsOf: url))
        guard !rows.isEmpty, rows.count <= 100_000, Set(rows.map(\.id)).count == rows.count,
              rows.allSatisfy({ row in
                  VenuePlace.validID(row.id) && (row.id.hasPrefix("osm-") || row.id.hasPrefix("overture-")) &&
                      !row.name.isEmpty && row.name.count <= 200 && row.branch.count <= 200 && row.address.count <= 350 &&
                      Self.inArea(latitude: row.latitude, longitude: row.longitude)
              }) else { throw ContextError.invalid("Identitas atau koordinat katalog terbuka tidak valid.") }
        venues = rows
        byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        self.apple = apple
        self.enrichment = enrichment
    }

    private static func inArea(latitude: Double, longitude: Double) -> Bool {
        (-6.6 ... -5.9).contains(latitude) && (106.5 ... 107.2).contains(longitude)
    }

    public func search(_ query: String, limit: Int = 8, categoryHints: [String] = [],
                       independentOnly: Bool = false, area: String? = nil) async throws -> [VenuePlace] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 240, (1 ... 12).contains(limit) else {
            throw ContextError.invalid("Isi nama tempat atau wilayah pencarian di Jakarta.")
        }
        let now = Date()
        issued = issued.filter { $0.value.expiresAt > now }
        let applePins: [PlacePin]
        do { applePins = try await pins(query) }
        catch {
            try Task.checkCancellation()
            if !independentOnly { throw error }
            applePins = []
        }
        var result: [VenuePlace] = []
        var seen = Set<String>()
        let wanted = Set(categoryHints)
        let areaWords = Set(OpenVenue.normalized(area ?? "").split(separator: " "))
            .subtracting(["jakarta", "di", "indonesia"])
        for pin in applePins {
            if let venue = match(pin) {
                if independentOnly {
                    guard wanted.isEmpty || !wanted.isDisjoint(with: venue.categories) else { continue }
                    let location = OpenVenue.normalized(([pin.address, venue.branch, venue.address] + (venue.areaHints ?? []))
                        .joined(separator: " "))
                    guard areaWords.isSubset(of: Set(location.split(separator: " "))) else { continue }
                }
                guard seen.insert(venue.id).inserted else { continue }
                issued[venue.id] = .init(pin: pin, expiresAt: now.addingTimeInterval(600))
                result.append(Self.place(venue))
            } else if !independentOnly {
                let id = "apple:" + SHA256.hash(data: Data(pin.id.utf8)).prefix(16)
                    .map { String(format: "%02x", $0) }.joined()
                if !seen.insert(id).inserted { continue }
                issued[id] = .init(pin: pin, expiresAt: now.addingTimeInterval(600))
                result.append(.init(id: id, name: pin.name, address: pin.address, latitude: pin.latitude, longitude: pin.longitude))
            }
        }
        if independentOnly {
            let words = Set(OpenVenue.normalized(area ?? query).split(separator: " "))
                .subtracting(["jakarta", "di", "indonesia"])
            let matches = venues.compactMap { row -> (Int, OpenVenue)? in
                guard wanted.isEmpty || !wanted.isDisjoint(with: row.categories) else { return nil }
                let name = OpenVenue.normalized(([row.name, row.branch, row.address] + row.aliases + (row.areaHints ?? [])).joined(separator: " "))
                let tokenHits = words.intersection(name.split(separator: " ")).count
                guard tokenHits == words.count else { return nil }
                return (tokenHits, row)
            }.sorted { $0.0 == $1.0 ? $0.1.id < $1.1.id : $0.0 > $1.0 }
            for (_, venue) in matches where seen.insert(venue.id).inserted { result.append(Self.place(venue)) }
        }
        return Array(result.prefix(limit))
    }

    public func snapshot(id: String, day: String, scheduleEnrichment: Bool = true, now: Date = .now) throws -> PlaceSnapshot {
        if let venue = byID[id] {
            let facts = enrichment.facts(for: id, now: now).filter { $0.value.validThrough.map { day <= $0 } ?? true }
            if scheduleEnrichment { enrichment.enqueue(venue, now: now) }
            var place = Self.place(venue)
            place.evidenceURI = facts[.hours]?.source?.absoluteString ?? facts[.access]?.source?.absoluteString
                ?? facts[.activity]?.source?.absoluteString ?? venue.sourceURLs.first
            let hasEvidence = facts.values.contains { $0.status == "supported" }
            var result = PlaceSnapshot(place: place, fetchedAt: now, fieldMask: "independent venue facts",
                                       source: hasEvidence ? "Sumber publik per cabang" : "OpenStreetMap / Overture")
            result.hoursDay = day
            result.verifiedHours = facts[.hours]?.resolution(day: day)
            result.hoursFreshUntil = facts[.hours]?.freshUntil
            result.publicAccess = facts[.access]?.status
            result.activity = facts[.activity].flatMap { $0.status == "supported" ? $0.quote : nil }
            if let access = facts[.access], access.status == "supported", let quote = access.quote {
                result.verifiedHours?.warnings.append("Syarat akses dari sumber: " + quote)
            }
            return result
        }
        guard let item = issued[id], item.expiresAt > now else {
            throw ContextError.invalid("Pencarian tempat telah kedaluwarsa. Cari kembali.")
        }
        let pin = item.pin
        return PlaceSnapshot(place: .init(id: id, name: pin.name, address: pin.address, latitude: pin.latitude, longitude: pin.longitude),
                             fetchedAt: now, fieldMask: "session pin", source: "Apple Maps Server API")
    }

    public func appleCandidates(id: String, name: String, override: String?) async throws -> [PlacePin] {
        if override == nil, let current = issued[id], current.expiresAt > Date() { return [current.pin] }
        return try await pins(override ?? (name + " Jakarta"))
    }

    public func checkAppleIdentity(for venue: OpenVenue) async throws -> String {
        let query = String([venue.name, venue.branch, "Jakarta"].joined(separator: " ").prefix(240))
        let matches = try await pins(query).filter { match($0)?.id == venue.id }
        let unique = Set(matches.map(\.id))
        if unique.isEmpty { return "unconfirmed" }
        if unique.count != 1 { return "ambiguous" }
        return "matched"
    }

    private static func place(_ venue: OpenVenue) -> VenuePlace {
        .init(id: venue.id, name: venue.name, address: venue.address, latitude: venue.latitude, longitude: venue.longitude,
              types: venue.categories)
    }

    private func pins(_ query: String) async throws -> [PlacePin] {
        var params = [URLQueryItem(name: "q", value: query), .init(name: "searchRegion", value: "-5.9,107.2,-6.6,106.5"),
                      .init(name: "limitToCountries", value: "ID"), .init(name: "lang", value: "id-ID")]
        params.append(.init(name: "resultTypeFilter", value: "poi,address"))
        let data = try await apple.maps(path: "search", params: params)
        return try JSONDecoder().decode(AppleResponse.self, from: data).results.prefix(12).compactMap { item in
            let coordinate = item.coordinate
            guard Self.inArea(latitude: coordinate.latitude, longitude: coordinate.longitude) else { return nil }
            var pin = PlacePin(id: item.id ?? "session:\(item.name):\(coordinate.latitude):\(coordinate.longitude)",
                               name: item.name, address: (item.formattedAddressLines ?? []).joined(separator: ", "),
                               latitude: coordinate.latitude, longitude: coordinate.longitude)
            pin.source = "Apple Maps Server API"
            return pin
        }
    }

    private func match(_ pin: PlacePin) -> OpenVenue? {
        let name = OpenVenue.normalized(pin.name)
        let candidates = venues.filter { venue in
            let exact = ([venue.name] + venue.aliases).contains { OpenVenue.normalized($0) == name }
            guard exact else { return false }
            let reference = PlacePin(id: venue.id, name: venue.name, address: venue.address,
                                     latitude: venue.latitude, longitude: venue.longitude)
            return WeatherPolicy.distance(pin, reference) <= 125
        }
        return candidates.count == 1 ? candidates[0] : nil
    }
}
