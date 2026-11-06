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
        let catalog = try IntegrationCatalog.load()
        let search = MapKitTripSearch()
        var rows: [ProbeRow] = []
        let definitions: [(String, String, [String], String?)] = [("origin", "Bundaran HI Jakarta", ["bundaran", "hi"], nil)]
            + ["bdt-rbbj", "cikini", "erasmus", "gbk", "ragunan"].compactMap { id in
                guard let c = catalog.candidate(id) else { return nil }
                return (id, c.mapQuery, c.matchWords, id == "cikini" ? "cikini" : id == "bdt-rbbj" ? "tebet" : nil)
            }
        for (id, query, words, branch) in definitions {
            do {
                let results = try await search.search(query: query)
                let review = PlaceIdentityPolicy.review(id: id, query: query, words: words, branch: branch, results: results)
                rows.append(.init(id: id, query: query, rawResults: results, review: review))
            } catch { rows.append(.init(id: id, query: query, rawResults: [], error: ProviderDiagnostics.message(error))) }
        }
        struct Probe: Codable { var evidence = "live Mac MapKit only; not iPhone or WeatherKit evidence"; var at = Date(); var os = ProcessInfo.processInfo.operatingSystemVersionString; var rows: [ProbeRow] }
        let data = try IntegrationJSON.encoder().encode(Probe(rows: rows))
        if let path = CommandLine.arguments.dropFirst().first { try data.write(to: URL(filePath: path), options: .atomic) }
        else { print(String(decoding: data, as: UTF8.self)) }
    }
}
