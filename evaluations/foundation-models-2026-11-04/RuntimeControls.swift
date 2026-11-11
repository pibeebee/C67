// Compile together with the frozen Evaluator.swift definitions, excluding Runner.
@main
struct RuntimeControls {
    static func main() async throws {
        let package = "/Users/neuhendra/Downloads/foundation-models-evaluation-2026-11-04/"
        let lines = try String(contentsOfFile: package + "inputs.jsonl", encoding: .utf8).split(separator: "\n")
        let cases = try lines.map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
        guard let sample = cases.first(where: { $0["id"] as? String == "LANG-01" }),
              let context = sample["context"] as? [String: Any], let message = sample["userMessage"] as? String else {
            throw HarnessError.invalidRequest
        }
        let source = try String(contentsOfFile: package + "model-instructions.txt", encoding: .utf8)
        let instructions = source.replacingOccurrences(of: "{{LOCALE}}", with: "en_US")
            .replacingOccurrences(of: "{{OUTPUT_LANGUAGE}}", with: "English")
        let contextData = try JSONSerialization.data(withJSONObject: context, options: [.sortedKeys])
        let prompt = "Application context (synthetic):\n\(String(decoding: contextData, as: UTF8.self))\nUser message:\n\(message)"
        let model = SystemLanguageModel.default
        var result: [String: Any] = ["model": "SystemLanguageModel.default", "mode": CommandLine.arguments.dropFirst().first ?? "tokens"]
        switch CommandLine.arguments.dropFirst().first ?? "tokens" {
        case "tokens":
            result["contextSize"] = model.contextSize
            result["instructionsTokens"] = try await model.tokenCount(for: instructions)
            result["promptTokens"] = try await model.tokenCount(for: prompt)
            result["schemaTokens"] = try await model.tokenCount(for: Suggestion.generationSchema)
            let ledger = FixtureLedger(fixtures: Data(), traceURL: URL(fileURLWithPath: "/tmp/c67-control-unused"))
            result["weatherToolTokens"] = try await model.tokenCount(for: [WeatherTool(ledger: ledger)])
            result["note"] = "Counts are per component for one English sample; their sum excludes framework overhead and output tokens."
        case "long":
            let longPrompt = prompt + "\n" + String(repeating: "synthetic itinerary context and constraints ", count: 12000)
            result["contextSize"] = model.contextSize
            result["promptTokens"] = try await model.tokenCount(for: longPrompt)
            let session = LanguageModelSession(model: model, tools: [], instructions: instructions)
            do {
                _ = try await session.respond(to: longPrompt, generating: Suggestion.self,
                                              options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 1400))
                result["outcome"] = "response"
            } catch {
                result["outcome"] = "error"
                result["errorType"] = String(reflecting: type(of: error))
                result["error"] = String(describing: error)
            }
        case "cancel":
            let session = LanguageModelSession(model: model, tools: [], instructions: instructions)
            let task = Task {
                try await session.respond(to: prompt, generating: Suggestion.self,
                                          options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 1400))
            }
            try await Task.sleep(for: .milliseconds(250))
            task.cancel()
            do {
                _ = try await task.value
                result["canceledRequest"] = "returned response after cancellation"
            } catch {
                result["canceledRequest"] = "error"
                result["cancelErrorType"] = String(reflecting: type(of: error))
                result["cancelError"] = String(describing: error)
            }
            result["isRespondingAfterCancel"] = session.isResponding
            let fresh = LanguageModelSession(model: model, tools: [], instructions: instructions)
            do {
                let response = try await fresh.respond(to: prompt, generating: Suggestion.self,
                                                       options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 1400))
                result["freshSession"] = "response"
                result["freshSessionRaw"] = response.rawContent.jsonString
            } catch {
                result["freshSession"] = "error"
                result["freshSessionError"] = String(describing: error)
            }
        default:
            throw HarnessError.invalidRequest
        }
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
