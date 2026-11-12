import Foundation
import FoundationModels
import MapKit

public actor ExperimentEvidence {
    public private(set) var calls = 0
    public private(set) var names: [String] = []
    public init() {}
    func record(_ names: [String]) { calls += 1; self.names += names }
}

public struct ExperimentSearchTool: Tool {
    public let name = "searchPlaces"
    public let description = "Search Apple Maps for real museums in Central Jakarta. Returns place names."
    public let evidence: ExperimentEvidence
    public init(evidence: ExperimentEvidence) { self.evidence = evidence }

    @Generable public struct Arguments {
        @Guide(description: "A short museum search query") public var query: String
    }

    public func call(arguments: Arguments) async throws -> String {
        let names = try await Self.search(query: arguments.query)
        await evidence.record(names)
        return "MapKit results: " + names.joined(separator: "; ")
    }

    @MainActor static func search(query: String) async throws -> [String] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = String(query.prefix(120))
        request.region = MKCoordinateRegion(center: .init(latitude: -6.1754, longitude: 106.8272),
                                            latitudinalMeters: 10000, longitudinalMeters: 10000)
        request.resultTypes = .pointOfInterest
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(3).compactMap(\.name)
    }
}

public enum FeasibilityExperiment {
    @MainActor public static func run() async -> String {
        let model = SystemLanguageModel.default
        var lines = ["Availability: \(model.availability)",
                     "English supported: \(model.supportsLocale(Locale(identifier: "en_US")))",
                     "Indonesian supported: \(model.supportsLocale(Locale(identifier: "id_ID")))",
                     "Languages: \(model.supportedLanguages.map(\.minimalIdentifier).sorted().joined(separator: ", "))"]
        let evidence = ExperimentEvidence()
        guard model.availability == .available else {
            lines.append("SUPPORTED BUT NOT EXECUTED: model unavailable; no tool invocation attempted.")
            return lines.joined(separator: "\n")
        }
        let session = LanguageModelSession(tools: [ExperimentSearchTool(evidence: evidence)], instructions:
            "Use searchPlaces to look up museums in Central Jakarta. Only name places returned by the tool.")
        let start = Date()
        do {
            let response = try await session.respond(to: "Find two real museums in Central Jakarta. Call searchPlaces first.",
                                                     options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 300))
            lines.append("Response: \(response.content)")
        } catch { lines.append("Generation error: \(error)") }
        lines.append("Duration seconds: \(Date().timeIntervalSince(start))")
        lines.append("Actual successful tool calls: \(await evidence.calls)")
        lines.append("Actual MapKit names: \(await evidence.names)")
        lines.append("Transcript: \(session.transcript)")
        return lines.joined(separator: "\n")
    }
}
