import Foundation
import FoundationModels
import Testing
@testable import TripSenseCore

@Suite @MainActor struct SearchBudgetTests {
    private var preferences: TripPreferences { .init(start: Date(timeIntervalSince1970: 1_800_000_000), theme: .mixed, count: 2) }
    private func budgetError() -> LanguageModelSession.ToolCallError {
        let tool = SearchPlacesTool(maps: MapServices(diagnostics: Diagnostics()), origin: preferences.origin)
        return .init(tool: tool, underlyingError: PlanningError.toolBudget)
    }

    @Test func wrappedSearchBudgetFinishesOnceUsingRetrievedPlaces() async throws {
        let places = Array(DemoFixture.places.prefix(2))
        let diagnostics = Diagnostics()
        var finishCalls = 0
        let result = try await ModelPlanner.completeSelection(preferences: preferences, diagnostics: diagnostics,
                                                              retrievedPlaces: { places }, generate: { throw budgetError() }, finishWithoutSearch: { retrieved in
                                                                  finishCalls += 1
                                                                  #expect(retrieved.map(\.id) == places.map(\.id))
                                                                  return ModelSelection(stops: retrieved.map { ModelStop(placeID: $0.id, reason: "Synthetic finishing response") })
                                                              })
        #expect(finishCalls == 1)
        #expect(Set(result.map(\.placeID)) == Set(places.map(\.id)))
        #expect(diagnostics.events.contains { $0.message.contains("without further searches") })
    }

    @Test func insufficientMatchingPlacesDoNotTriggerFinishing() async {
        var finishCalls = 0
        await #expect(throws: PlanningError.searchLimit) {
            _ = try await ModelPlanner.completeSelection(preferences: preferences, diagnostics: Diagnostics(),
                                                         retrievedPlaces: { Array(DemoFixture.places.prefix(1)) }, generate: { throw budgetError() },
                                                         finishWithoutSearch: { _ in finishCalls += 1; return ModelSelection(stops: []) })
        }
        #expect(finishCalls == 0)
    }

    @Test func unrelatedToolFailureDoesNotTriggerFinishing() async {
        var finishCalls = 0
        let tool = SearchPlacesTool(maps: MapServices(diagnostics: Diagnostics()), origin: preferences.origin)
        do {
            _ = try await ModelPlanner.completeSelection(preferences: preferences, diagnostics: Diagnostics(),
                                                         retrievedPlaces: { DemoFixture.places }, generate: {
                                                             throw LanguageModelSession.ToolCallError(tool: tool, underlyingError: PlanningError.throttled)
                                                         }, finishWithoutSearch: { _ in finishCalls += 1; return ModelSelection(stops: []) })
            Issue.record("Expected the original tool failure")
        } catch let error as LanguageModelSession.ToolCallError {
            #expect(error.underlyingError as? PlanningError == .throttled)
        } catch { Issue.record("Unexpected error type") }
        #expect(finishCalls == 0)
    }

    @Test func finishingFailureIsNotRetried() async {
        var finishCalls = 0
        await #expect(throws: PlanningError.invalidIDs) {
            _ = try await ModelPlanner.completeSelection(preferences: preferences, diagnostics: Diagnostics(),
                                                         retrievedPlaces: { DemoFixture.places }, generate: { throw budgetError() },
                                                         finishWithoutSearch: { _ in
                                                             finishCalls += 1
                                                             return ModelSelection(stops: [ModelStop(placeID: "invented", reason: "Invalid synthetic response")])
                                                         })
        }
        #expect(finishCalls == 1)
    }

    @Test func wrappedCancellationIsPreserved() async {
        let tool = SearchPlacesTool(maps: MapServices(diagnostics: Diagnostics()), origin: preferences.origin)
        await #expect(throws: CancellationError.self) {
            _ = try await ModelPlanner.completeSelection(preferences: preferences, diagnostics: Diagnostics(),
                                                         retrievedPlaces: { DemoFixture.places }, generate: {
                                                             throw LanguageModelSession.ToolCallError(tool: tool, underlyingError: CancellationError())
                                                         }, finishWithoutSearch: { _ in Issue.record("Must not finish after cancellation"); return ModelSelection(stops: []) })
        }
    }

    @Test func userMessageDoesNotExposeToolStateOrUnknownErrorDetails() {
        let message = PlanningError.userMessage(for: budgetError())
        #expect(message == PlanningError.toolBudget.localizedDescription)
        #expect(!message.contains("SearchPlacesTool"))
        #expect(!message.contains("latitude"))
        let secretError = NSError(domain: "private diagnostic payload", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "origin coordinates and internal state"])
        #expect(!PlanningError.userMessage(for: secretError).contains("coordinates"))
    }
}
