import Foundation
import PlaceContextEngine

@main struct PlacesContextCLI {
    @MainActor static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst()); let command = args.first ?? "status"
            func output<T: Encodable>(_ value: T)throws { print(String(decoding: try ContextJSON.encoder().encode(value), as: UTF8.self)) }
            if command == "status" {
                try output(["configured": String((try? PlacesConfiguration()) != nil), "keyVariable": "GOOGLE_PLACES_API_KEY", "liveRequests": "not_attempted", "engine": "Google Places context v1"]); return
            }
            if command == "demo" { try await output(PlaceContextDemo.run()); return }
            let client = GooglePlacesClient(configuration: try .init())
            if command == "verify-live", args.count == 2 {
                let report = try await LiveContextVerification.run(id: args[1], client: client)
                try output(report)
                if !report.passed { exit(2) }; return
            }
            if command == "search", args.count >= 2 {
                try await output(client.search(args.dropFirst().joined(separator: " "))); return
            }
            if command == "evaluate", args.count == 2 {
                let input = try ContextJSON.decoder().decode(GoogleContextEvaluationInput.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
                try await output(GoogleContextService.evaluate(input, client: client)); return
            }
            throw ContextError.invalid("Usage: places-context status | demo | search QUERY | evaluate INPUT.json | verify-live CONFIRMED_PLACE_ID")
        } catch {
            // Error types never contain credentials or raw Google response bodies.
            FileHandle.standardError.write(Data("places-context: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
