#if DEBUG
    import Foundation
    import CryptoKit
    import PocketEngine

    /// Opt-in Simulator harness. The same model methods are used by the visible app.
    @MainActor
    enum SimulatorAcceptance {
        private struct Input: Decodable { var briefs: [Brief] }
        private struct Brief: Decodable {
            var id: String
            var categories: [String]
            var preferences: [String: String]
            var queryByInterest: [String: String]?
        }
        static func runIfRequested(model: PocketModel) async {
            guard ProcessInfo.processInfo.arguments.contains("--pocket-acceptance") else { return }
            let folder = URL.documentsDirectory
            do {
                let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: folder.appending(path: "acceptance-input.json")))
                let catalogURL = folder.appending(path: "acceptance-catalog.json")
                let independent = try Codec.decoder().decode(Catalog.self, from: Data(contentsOf: catalogURL)).validated()
                let reviewedURL = folder.appending(path: "acceptance-reviewed-catalog.json")
                let reviewed = FileManager.default.fileExists(atPath: reviewedURL.path)
                    ? try Codec.decoder().decode(Catalog.self, from: Data(contentsOf: reviewedURL)).validated() : nil
                if let reviewed, Set(reviewed.venues.map(\.id)) != Set(independent.venues.map(\.id)) {
                    throw EngineError.invalid("Katalog dengan bukti harus memakai identitas yang sama.")
                }
                var results: [[String: Any]] = []
                for brief in input.briefs {
                    var profile = Profile(); profile.categories = Set(brief.categories)
                    for (key, value) in brief.preferences {
                        guard let field = Facet(rawValue: key), let preference = Preference(rawValue: value) else {
                            throw EngineError.invalid("Input benchmark memiliki preferensi yang tidak dikenal.")
                        }
                        profile.preferences[field] = preference
                    }
                    model.profile = profile
                    // One Apple response feeds both arms. The reference never enters this process.
                    model.catalog = Catalog(schemaVersion: 1, generatedAt: .now, attribution: "Benchmark Apple session", venues: [])
                    model.discover(queries: brief.queryByInterest ?? [:])
                    while model.isDiscovering { try await Task.sleep(for: .milliseconds(150)) }
                    let apple = model.recommendations
                    let appleElapsed = model.discoverySeconds
                    let supplementalStarted = Date()
                    model.catalog = independent
                    let combined = model.recommendations
                    let supplementalElapsed = Date().timeIntervalSince(supplementalStarted)
                    func project(_ values: [Assessment]) -> [[String: Any]] {
                        values.prefix(12).map { value in
                            let name = CandidatePool.normalizedName(value.venue.name)
                            let digest = SHA256.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined()
                            return ["id": value.id.hasPrefix("apple-session-") ? "apple-" + digest : value.id,
                                    "nameHash": digest, "categories": value.venue.effectiveCategories(at: .now), "score": value.score,
                                    "requiredSatisfied": profile.preferences.filter { $0.value == .required }.keys.allSatisfy { value.venue.status($0) == .supported }]
                        }
                    }
                    var output: [String: Any] = ["id": brief.id, "apple": project(apple), "combined": project(combined),
                                                 "appleCount": apple.count, "combinedCount": combined.count,
                                                 "appleQueries": model.discoveryRequests, "appleSeconds": appleElapsed,
                                                 "supplementalSeconds": supplementalElapsed, "notice": model.discoveryNotice,
                                                 "missingInterests": model.missingInterests,
                                                 "combinedAllIDs": combined.map { $0.id.hasPrefix("apple-session-") ? "apple-session" : $0.id }]
                    if let reviewed {
                        model.catalog = reviewed
                        let enriched = model.recommendations
                        output["reviewed"] = project(enriched)
                        output["reviewedCount"] = enriched.count
                    }
                    results.append(output)
                    try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
                        .write(to: folder.appending(path: "acceptance-output.json"), options: .atomic)
                }
                model.message = "Benchmark Simulator selesai — \(results.count) skenario."
            } catch {
                try? Data(error.localizedDescription.utf8).write(to: folder.appending(path: "acceptance-error.txt"), options: .atomic)
                model.message = "Benchmark gagal — " + error.localizedDescription
            }
        }
    }
#endif
