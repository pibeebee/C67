import Foundation
import RoutingBenchmark

@main struct RoutingBenchMain {
    @MainActor static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let command = args.first ?? "preflight"
        let env = ProcessInfo.processInfo.environment
        if ["paired-live", "paired-smoke", "controlled-live", "transit-live"].contains(command), args.count == 3 {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(RoutingManifest.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
            let output = URL(fileURLWithPath: args[2], isDirectory: true); try reserve(output)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let apple = AppleNativeRoutingProvider()
            let valhalla = try ValhallaRoutingProvider(baseURL: URL(string: env["VALHALLA_BASE_URL"] ?? "http://127.0.0.1:8002")!)
            if ["controlled-live", "transit-live"].contains(command) {
                let rows = try await ControlledLiveCampaign.run(manifest: manifest, apple: apple, valhalla: valhalla, transitOnly: command == "transit-live") { snapshot in
                    try encoder.encode(snapshot).write(to: output.appendingPathComponent("controlled-observations.json"), options: .atomic)
                }
                print("Finished \(rows.count) controlled itinerary/TJ comparisons. Google requests: zero."); return
            }
            let result = try await MatchedRoadCampaign.run(manifest: manifest, apple: apple, valhalla: valhalla, smoke: command == "paired-smoke") { snapshot in
                try encoder.encode(snapshot).write(to: output.appendingPathComponent("paired-observations.json"), options: .atomic)
            }
            print("Finished \(result.comparisons.count)/\(result.plannedPairs) matched live pairs. Apple API: \(result.appleAPI). Google requests: zero.")
            return
        }
        if command == "preflight" {
            let checks = ["appleMapsConfigured": ["APPLE_TEAM_ID", "MAPS_KEY_ID", "MAPS_KEY_PATH"].allSatisfy { env[$0]?.isEmpty == false },
                          "googleLiveEnabled": env["ROUTING_GOOGLE_LIVE"] == "1",
                          "googleRoutesConfigured": env["GOOGLE_ROUTES_API_KEY"]?.isEmpty == false,
                          "valhallaConfigured": env["VALHALLA_BASE_URL"]?.isEmpty == false]
            print(String(decoding: try JSONEncoder().encode(checks), as: UTF8.self)); return
        }
        guard args.count >= 2 else {
            print("Usage: routing-bench preflight | synthetic NEW_OUTPUT_DIR | live MANIFEST NEW_OUTPUT_DIR | local-probe MANIFEST NEW_OUTPUT_DIR | paired-smoke MANIFEST NEW_OUTPUT_DIR | paired-live MANIFEST NEW_OUTPUT_DIR | controlled-live MANIFEST NEW_OUTPUT_DIR | transit-live MANIFEST NEW_OUTPUT_DIR")
            return
        }
        let rows: [RoutingObservation]
        let output: URL
        if command == "synthetic" {
            output = URL(fileURLWithPath: args[1], isDirectory: true)
            try reserve(output)
            var collected: [RoutingObservation] = []
            for repetition in 0 ..< 3 {
                let batch = try await RoutingFixtures.run()
                collected += batch.map { value in var row = value; row.caseID += "-r\(repetition)"; return row }
            }
            rows = collected
        } else if ["live", "local-probe"].contains(command), args.count == 3 {
            output = URL(fileURLWithPath: args[2], isDirectory: true)
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(RoutingManifest.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
            try manifest.validate(); try reserve(output)
            rows = try await RoutingLiveCampaign.run(manifest: manifest, environment: env, probe: command == "local-probe")
        } else { throw RoutingFailure.invalidInput }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Only typed safe observations are exportable; provider payloads have no Codable path.
        try encoder.encode(rows).write(to: output.appendingPathComponent("observations.json"), options: .atomic)
        print("Recorded \(rows.count) observations in \(output.path). Provider payloads were not archived.")
    }
    static func reserve(_ output: URL) throws {
        guard !FileManager.default.fileExists(atPath: output.path) else { throw RoutingFailure.invalidInput }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    }
}
