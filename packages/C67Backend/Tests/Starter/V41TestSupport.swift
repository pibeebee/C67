import Foundation
import C67Domain
import PocketEngine
@testable import C67Data

/// Synthetic providers shared by the v4.1 engine and repository tests.
func v41Input(count: Int = 2) throws -> PlanningInput {
    var input = try orderInput(count: count)
    input.startsAt = ISO8601DateFormatter().date(from: "2026-11-30T09:00:00+07:00")!
    input.finishBy = input.startsAt.addingTimeInterval(8 * 3600)
    input.enginePreferences?.orderingMethod = .hybridV41
    input.enginePreferences?.scheduleSource = .manual
    input.enginePreferences?.semanticAssistance = .disabled
    input.enginePreferences?.usesLuna = false
    for index in input.places.indices {
        input.places[index].visitSeconds = 3600
        input.places[index].durationOverridden = true
    }
    return input
}

actor V41Calls {
    var modelIDs: [UUID] = []
    var routeDates: [Date] = []
    var shouldThrottle = false

    func order(_ input: PlanningInput, _ id: UUID) throws -> PlanningExperiencePlan {
        modelIDs.append(id)
        return try PocketIntegrationFixture.experience(input)
    }

    func travel(_ at: Date) throws -> LegQuote {
        routeDates.append(at)
        if shouldThrottle { throw TravelQuoteError.throttled }
        return .init(seconds: 600, meters: 1000)
    }

    func throttle() { shouldThrottle = true }
}

func v41Services(_ calls: V41Calls, model: Bool = true) -> PocketPlanningServices {
    var services = PocketPlanningServices(travel: { _, _, at, _ in try await calls.travel(at) },
                                          weather: { _, _, _ in throw PlanningError.invalidResponse }, advise: { _ in throw PlanningError.invalidResponse })
    if model { services.order = { input, id in try await calls.order(input, id) } }
    return services
}
