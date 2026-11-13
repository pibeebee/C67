import Foundation

/// Read-only live diagnostic. A name match is a proxy, never an operator/human verification.
@MainActor public enum LabDiscoveryProbe {
    struct Query: Codable {
        var id: String; var query: String; var aliases: [[String]]; var sourceURL: String?
        var outsideCatalogue: Bool
    }
    public static func run(directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let catalog = try IntegrationCatalog.load()
        var definitions = [Query(id: "origin", query: "Bundaran HI Jakarta", aliases: [["bundaran", "hi"]], outsideCatalogue: false)]
        for id in ["cikini", "bdt-rbbj", "erasmus", "ragunan", "gbk"] {
            let c = catalog.candidate(id)!
            definitions.append(.init(id: id, query: c.mapQuery, aliases: [c.matchWords], outsideCatalogue: false))
        }
        definitions += [
            .init(id: "museum-bi", query: "Museum Bank Indonesia Jakarta", aliases: [["museum", "bank", "indonesia"]], sourceURL: "https://www.bi.go.id/id/layanan/museum-bi/default.aspx", outsideCatalogue: true),
            .init(id: "museum-nasional", query: "Museum Nasional Indonesia Jakarta", aliases: [["museum", "nasional"], ["national", "museum"]], sourceURL: "https://www.museumnasional.or.id/alamat/", outsideCatalogue: true),
            .init(id: "museum-wayang", query: "Museum Wayang Jakarta", aliases: [["museum", "wayang"], ["puppet", "museum"]], sourceURL: "https://www.jakarta.go.id/index.php/museum", outsideCatalogue: true),
            .init(id: "museum-tekstil", query: "Museum Tekstil Jakarta", aliases: [["museum", "tekstil"], ["textile", "museum"]], sourceURL: "https://www.jakarta.go.id/index.php/museum", outsideCatalogue: true),
            .init(id: "museum-bahari", query: "Museum Bahari Jakarta", aliases: [["museum", "bahari"], ["maritime", "museum"]], sourceURL: "https://www.jakarta.go.id/index.php/museum", outsideCatalogue: true),
            .init(id: "museum-joang", query: "Museum Joang 45 Jakarta", aliases: [["joang", "45"]], sourceURL: "https://www.jakarta.go.id/index.php/museum", outsideCatalogue: true)
        ]
        // Freeze the definitions before the first provider invocation.
        try IntegrationJSON.encoder().encode(definitions).write(to: directory.appendingPathComponent("queries.json"), options: .atomic)
        let budget = LabProviderBudget(callLimit: 32, cellLimit: 0)
        let apple = LabAppleREST(config: try .init(), budget: budget)
        var observations: [[String: Any]] = []
        var consecutiveErrors = 0
        for q in definitions {
            let start = ContinuousClock.now
            var row: [String: Any] = ["id": q.id, "query": q.query, "outsideCatalogue": q.outsideCatalogue,
                                      "identityMetric": "authored name-token proxy; not blind human judgment", "observedAt": Date().ISO8601Format()]
            do {
                let data = try await apple.maps(path: "search", params: LabRESTSearch.parameters(query: q.query))
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                let results = object["results"] as? [[String: Any]] ?? []
                let matched = results.filter { item in
                    let text = PlaceIdentityPolicy.normalize(item["name"] as? String ?? "")
                    return q.aliases.contains { words in words.allSatisfy { text.contains(PlaceIdentityPolicy.normalize($0)) } }
                }
                row["results"] = results; row["resultCount"] = results.count; row["nameProxyMatches"] = matched.count
                row["identityState"] = matched.count == 1 ? "one_name_proxy_match" : matched.isEmpty ? "no_name_proxy_match" : "ambiguous_name_proxy"
                row["returnedFields"] = Array(Set(results.flatMap { $0.keys })).sorted()
                if !q.outsideCatalogue {
                    let pins = results.compactMap { item -> PlacePin? in
                        guard let name = item["name"] as? String, let coordinate = item["coordinate"] as? [String: Double],
                              let lat = coordinate["latitude"], let lon = coordinate["longitude"] else { return nil }
                        return .init(id: name + ":\(lat):\(lon)", name: name, address: (item["formattedAddressLines"] as? [String] ?? []).joined(separator: ", "), latitude: lat, longitude: lon)
                    }
                    let branch = q.id == "cikini" ? "cikini" : q.id == "bdt-rbbj" ? "tebet" : nil
                    let review = PlaceIdentityPolicy.review(id: q.id, query: q.query, words: q.aliases[0], branch: branch, results: pins)
                    row["existingPolicyAutoSelected"] = review.selected != nil
                    row["existingPolicyIssue"] = review.issue ?? "none"
                }
                row["integratedCatalogueCandidatePresent"] = catalog.candidate(q.id) != nil
                // No source-fact adaptation exists for these external IDs. Don't fabricate one.
                row["externalItineraryReady"] = false
                row["externalGate"] = q.outsideCatalogue ? "outside_supported_catalogue; no verified timing/amenity mapping" : "existing_catalogue_path"
                try data.write(to: directory.appendingPathComponent(q.id + "-response.json"), options: .atomic)
                consecutiveErrors = 0
            } catch {
                row["error"] = error.localizedDescription; consecutiveErrors += 1
                observations.append(row)
                try save(observations, directory: directory, budget: budget)
                if case LabRESTError.status(let code, _) = error, [401, 429].contains(code) { throw error }
                if consecutiveErrors >= 2 { throw error }
                continue
            }
            let elapsed = start.duration(to: .now).components
            row["seconds"] = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            observations.append(row)
            try save(observations, directory: directory, budget: budget)
            print("DISCOVERY \(q.id) count=\(row["resultCount"] ?? 0) \(row["identityState"] ?? "unknown")")
        }
    }
    private static func save(_ observations: [[String: Any]], directory: URL, budget: LabProviderBudget) throws {
        let output: [String: Any] = ["observations": observations, "providerCalls": budget.calls, "etaCells": budget.cells,
                                     "scope": "actual Apple REST discovery; authored identity proxy; no field or human relevance validation"]
        try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: directory.appendingPathComponent("discovery.json"), options: .atomic)
    }
}
