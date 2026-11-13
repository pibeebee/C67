import Foundation
import PreferenceLearning

@main struct PreferenceEval {
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            let model = E5Embedding()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if args.contains("--parity") {
                struct Sample: Codable {
                    var text: String
                    var query: Bool
                    var tokens: [Int]
                    var vector: [Float]
                }
                var samples: [Sample] = []
                for (text, query) in [
                    ("Saya ingin ngopi sambil membaca", true),
                    ("A quiet cafe with books and reading tables.", false),
                ] {
                    samples.append(
                        .init(
                            text: text, query: query, tokens: try await model.tokenIDs(text, query: query),
                            vector: try await model.encode(text, query: query)))
                }
                print(String(decoding: try encoder.encode(samples), as: UTF8.self))
                return
            }
            if args.contains("--tokens") {
                var values: [String: [Int]] = [:]
                for text in [
                    "Coffee and reading", "Saya ingin ngopi sambil membaca", "Seni dan budaya", "quiet café",
                    "  kopi\n buku  ", "東京のカフェ", "kopi ☕ dan buku 📚",
                ] {
                    values[text] = try await model.tokenIDs(text, query: true)
                }
                print(String(decoding: try encoder.encode(values), as: UTF8.self))
                return
            }
            let catalog = try PreferenceCatalog.load(
                args.contains("--snapshot") ? "mapkit-snapshot-v1" : "synthetic-v1")
            var profile = LocalPreferenceProfile()
            if !args.contains("--cold") {
                profile.text =
                    args.contains("--culture")
                        ? "Saya ingin menikmati lukisan dan pameran seni"
                        : "Saya ingin ngopi sambil membaca di tempat yang tenang"
            }
            if args.contains("--learned"), catalog.id == "synthetic-v1" {
                profile.text = ""
                profile.feedback = ["A": .liked]
            }
            if args.contains("--avoid-lively") { profile.avoids.insert(.lively) }
            if let i = args.firstIndex(of: "--profile"), args.indices.contains(i + 1) {
                profile = try JSONDecoder().decode(
                    LocalPreferenceProfile.self, from: Data(contentsOf: URL(fileURLWithPath: args[i + 1])))
            }
            let run: PreferenceComparisonRun
            if args.contains("--live") || args.contains("--replay-search") {
                let provider: any PreferencePlaceSearching =
                    args.contains("--replay-search") ? PreferenceReplaySearch() : MapKitPreferenceSearch()
                run = try await PreferenceDiscoveryPipeline(embedding: model, search: provider).run(
                    profile: profile, useEmbedding: !args.contains("--baseline"))
            } else {
                run = try await PreferenceRanker(embedding: model).compare(
                    profile: profile, catalog: catalog, useEmbedding: !args.contains("--baseline"))
            }
            let data = try encoder.encode(run)
            if let i = args.firstIndex(of: "--out"), args.indices.contains(i + 1) {
                let dir = URL(fileURLWithPath: args[i + 1])
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try data.write(to: dir.appendingPathComponent("run.json"), options: .atomic)
                try run.markdown.write(
                    to: dir.appendingPathComponent("REPORT.md"), atomically: true, encoding: .utf8)
            }
            print(String(decoding: data, as: UTF8.self))
        } catch {
            FileHandle.standardError.write(Data("ERROR: \(error)\n".utf8))
            exit(1)
        }
    }
}
