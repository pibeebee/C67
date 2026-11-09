import Foundation
import PlannerEngine
import PlaceContextEngine

/// Bounded diagnostic trace only; no credentials or Google content.
@MainActor final class DiagnosticETA: LabETAProvider {
    let provider: LabRESTETA
    let output: URL
    var observed: [LabETAValue] = []
    var metrics: LabProviderMetrics { provider.metrics }
    init(provider: LabRESTETA, output: URL) { self.provider = provider; self.output = output }
    func values(_ queries: [LabETAQuery]) async throws -> [LabETAValue] {
        let result = try await provider.values(queries)
        observed += result
        try ContextJSON.encoder().encode(observed).write(to: output, options: .atomic)
        return result
    }
}
