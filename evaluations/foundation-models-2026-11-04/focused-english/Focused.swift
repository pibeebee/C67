import Foundation
import FoundationModels

@Generable
struct IntentResult: Codable {
    @Guide(.anyOf(["extend", "skip", "deadline", "apply", "clarify", "none"])) var intent: String
    @Guide(description: "Explicit target or current stop when requested; otherwise null.") var target: String?
    @Guide(description: "Explicit extension minutes only; do not calculate times.") var minutes: Int?
    @Guide(description: "Explicit deadline as ISO-8601 only; otherwise null.") var deadline: String?
    @Guide(description: "Explicit proposal ID for apply only; otherwise null.") var proposalID: String?
    @Guide(description: "A single question if intent is ambiguous; otherwise null.") var question: String?
}

@Generable
struct PreferenceResult: Codable {
    @Guide(description: "All and only preferences explicitly expressed.") var preferences: [String]
}

@Generable
struct ExplanationResult: Codable {
    @Guide(description: "Answer using only supplied facts. State uncertainty. Do not propose changes.") var answer: String
    @Guide(description: "IDs of supplied facts supporting the answer.") var evidenceIDs: [String]
}

@Generable
struct RecommendationResult: Codable {
    @Guide(description: "One eligible supplied candidate ID; null if none can be verified.") var candidateID: String?
    @Guide(description: "Explain relevant facts, tradeoffs and unknowns using supplied evidence only.") var answer: String
    var evidenceIDs: [String]
}

@main
struct FocusedRunner {
    static func main() async {
        let start = Date()
        do {
            guard CommandLine.arguments.count == 3,
                  let input = try JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile()) as? [String: Any],
                  let kind = input["kind"] as? String,
                  let message = input["userMessage"] as? String,
                  let context = input["context"] as? [String: Any],
                  let history = input["history"] as? [[String: String]] else { throw HarnessError.invalidRequest }
            let model = SystemLanguageModel.default
            guard model.availability == .available, model.supportsLocale(Locale(identifier: "en_US")) else {
                throw HarnessError.invalidRequest
            }
            let ledger = try FixtureLedger(fixtures: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])),
                                           traceURL: URL(fileURLWithPath: CommandLine.arguments[2]))
            var registered: [any Tool] = []
            for name in input["tools"] as? [String] ?? [] {
                switch name {
                case "readWeather": registered.append(WeatherTool(ledger: ledger))
                case "searchPlaces": registered.append(SearchTool(ledger: ledger))
                case "readOpeningHours": registered.append(HoursTool(ledger: ledger))
                default: throw HarnessError.invalidRequest
                }
            }
            let instructions = """
            You are a trip assistant. Use only supplied synthetic context or actual tool results. Never invent facts.
            Interpret only the user's explicit request, negations and latest correction. Ask when ambiguous.
            A result is only a suggestion. Never claim it was saved or applied. Do not calculate routes, times or feasibility.
            If a tool is needed, call it with the requested arguments; stop if it returns unavailable. Do not invent tool results.
            """
            let contextJSON = String(decoding: try JSONSerialization.data(withJSONObject: context, options: [.sortedKeys]), as: UTF8.self)
            let historyJSON = String(decoding: try JSONSerialization.data(withJSONObject: history, options: [.sortedKeys]), as: UTF8.self)
            let prompt = "Context: \(contextJSON)\nUncommitted history: \(historyJSON)\nUser: \(message)"
            let session = LanguageModelSession(model: model, tools: registered, instructions: instructions)
            let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 450)
            let raw: String
            switch kind {
            case "intent": raw = try await session.respond(to: prompt, generating: IntentResult.self, options: options).rawContent.jsonString
            case "preference": raw = try await session.respond(to: prompt, generating: PreferenceResult.self, options: options).rawContent.jsonString
            case "explanation", "tool": raw = try await session.respond(to: prompt, generating: ExplanationResult.self, options: options).rawContent.jsonString
            case "recommendation": raw = try await session.respond(to: prompt, generating: RecommendationResult.self, options: options).rawContent.jsonString
            default: throw HarnessError.invalidRequest
            }
            let parsed = try JSONSerialization.jsonObject(with: Data(raw.utf8))
            let output: [String: Any] = ["outcome": "response", "parsedFields": parsed, "rawOutput": raw, "modelSeconds": Date().timeIntervalSince(start)]
            print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), as: UTF8.self))
        } catch {
            let output: [String: Any] = ["outcome": "error", "errorType": String(reflecting: type(of: error)), "error": String(describing: error), "modelSeconds": Date().timeIntervalSince(start)]
            if let data = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]) { print(String(decoding: data, as: UTF8.self)) }
        }
    }
}
