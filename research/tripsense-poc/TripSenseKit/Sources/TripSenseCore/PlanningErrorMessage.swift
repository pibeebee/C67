import Foundation
import FoundationModels

public extension PlanningError {
    /// ToolCallError descriptions include tool state, including origin coordinates.
    /// User-facing text must come from the underlying known error or a safe default.
    static func userMessage(for error: any Error) -> String {
        if let toolError = error as? LanguageModelSession.ToolCallError {
            return userMessage(for: toolError.underlyingError)
        }
        if let planningError = error as? PlanningError { return planningError.localizedDescription }
        if error is CancellationError { return "Trip planning was canceled." }
        return "Trip planning could not finish. Please try again or simplify your request."
    }
}
