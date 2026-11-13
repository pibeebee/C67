import Foundation

public struct EvaluationInput: Codable, Sendable {
    public var id: String
    public var capability: Capability
    public var context: TripContextV1
    public var direction: UserDirection
    public var profile: PreferenceExtraction
    public var candidates: [CandidateV1]
}
public struct EvaluationAttempt: Codable, Sendable {
    public var caseID: String
    public var runtime: ModelRuntime
    public var promptVersion = LabPrompts.version
    public var instructions: String
    public var prompt: String
    public var rawOutput = ""
    public var shapeAndReferencesValid = false
    public var status: String
    public var error = ""
    public var responseSeconds: Double = 0
    public var inputTokens: Int?
    public var humanSemanticReview = "pending"
}
public enum EvaluationRunner {
    public static func attempt(_ input: EvaluationInput, model: any ModelGenerating) async throws
        -> EvaluationAttempt
    {
        try input.context.validate()
        let runtime = await model.runtime()
        let request = try LabPrompts.make(
            input.capability, context: input.context, direction: input.direction,
            profile: input.profile, candidates: input.candidates)
        var result = EvaluationAttempt(
            caseID: input.id, runtime: runtime,
            instructions: LabPrompts.instructions(input.capability), prompt: request.prompt,
            status: "blocked")
        guard runtime.available, runtime.englishSupported else {
            result.error = runtime.availability
            return result
        }
        let start = Date()
        do {
            let generated = try await model.generate(request)
            result.rawOutput = generated.raw
            result.inputTokens = generated.inputTokens
            try OutputValidation.validate(
                generated.raw, capability: input.capability, context: input.context,
                candidates: input.candidates)
            result.shapeAndReferencesValid = true
            result.status = "response"
        } catch is CancellationError { throw CancellationError() } catch {
            result.error = String(describing: error)
            if case LabError.timeout = error {
                result.status = "timeout"
            } else {
                result.status = result.rawOutput.isEmpty ? "error" : "validation_failed"
            }
        }
        result.responseSeconds = Date().timeIntervalSince(start)
        return result
    }
}
