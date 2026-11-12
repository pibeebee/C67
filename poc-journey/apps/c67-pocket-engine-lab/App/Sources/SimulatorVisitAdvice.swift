#if DEBUG
    import Foundation
    import FoundationModels

    @Generable
    private struct VisitAdviceChoice {
        var slotID: String
    }

    @MainActor
    enum SimulatorVisitAdvice {
        private struct Input: Decodable {
            var instructions: String
            var cases: [Case]
        }
        private struct Case: Decodable {
            var id: String
            var prompt: String
        }
        static func runIfRequested() async {
            guard ProcessInfo.processInfo.arguments.contains("--pocket-visit-advice") else { return }
            let folder = URL.documentsDirectory
            do {
                let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: folder.appending(path: "visit-advice-input.json")))
                let model = SystemLanguageModel.default
                var results: [[String: Any]] = []
                for item in input.cases {
                    let start = ContinuousClock.now
                    var row: [String: Any] = ["id": item.id]
                    switch model.availability {
                    case .available:
                        do {
                            let session = LanguageModelSession(instructions: input.instructions)
                            row["slotID"] = try await session.respond(to: item.prompt, generating: VisitAdviceChoice.self).content.slotID
                        } catch { row["error"] = error.localizedDescription }
                    case .unavailable(let reason):
                        row["unavailable"] = String(describing: reason)
                    }
                    let duration = start.duration(to: .now).components
                    row["elapsedMs"] = Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
                    results.append(row)
                }
                try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
                    .write(to: folder.appending(path: "visit-advice-output.json"), options: .atomic)
            } catch {
                try? Data(error.localizedDescription.utf8).write(to: folder.appending(path: "visit-advice-error.txt"), options: .atomic)
            }
        }
    }
#endif
