import Foundation
import TripIntegration

private struct ProbeRow: Codable {
    var id: String
    var query: String
    var rawResults: [PlacePin]
    var review: LocationReview?
    var error: String?
}

@main struct MapKitProbe {
    @MainActor static func main() async throws {
        let blokM = CommandLine.arguments.contains("--blok-m")
        let catalog = try IntegrationCatalog.load(blokM: blokM)
        let customOrigins = CommandLine.arguments.contains("--custom-origins")
        let search = MapKitTripSearch(includeAddresses: customOrigins)
        var rows: [ProbeRow] = []
        let ids = blokM ? catalog.quality.candidates.map(\.id) : ["bdt-rbbj", "cikini", "erasmus", "gbk", "ragunan"]
        let center: [(String, String, [String], String?)] = blokM
            ? [("center", "MRT Blok M BCA Jakarta", ["blok", "m"], nil)] : []
        var definitions: [(String, String, [String], String?)] = [("origin", "Bundaran HI Jakarta", ["bundaran", "hi"], nil)] + center
            + ids.compactMap { id in
                guard let c = catalog.candidate(id) else { return nil }
                return (id, c.mapQuery, c.matchWords, id == "cikini" ? "cikini" : id == "bdt-rbbj" ? "tebet" : nil)
            }
        if customOrigins {
            definitions = ["Stasiun Cikini Jakarta", "Senayan Jakarta", "Jalan Wijaya II Jakarta Selatan"].map { ("origin", $0, [], nil) }
        }
        for (id, query, words, branch) in definitions {
            do {
                let results = try await search.search(query: query)
                let review = PlaceIdentityPolicy.review(id: id, query: query, words: words, branch: branch, results: results, region: id == "center" ? nil : catalog.region)
                rows.append(.init(id: id, query: query, rawResults: results, review: review))
            } catch { rows.append(.init(id: id, query: query, rawResults: [], error: ProviderDiagnostics.message(error))) }
        }
        struct Probe: Codable { var evidence = "live Mac MapKit only; not iPhone or WeatherKit evidence"; var at = Date(); var os = ProcessInfo.processInfo.operatingSystemVersionString; var rows: [ProbeRow] }
        let data = try IntegrationJSON.encoder().encode(Probe(rows: rows))
        if let path = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("--") }) { try data.write(to: URL(filePath: path), options: .atomic) }
        else { print(String(decoding: data, as: UTF8.self)) }
    }
}
