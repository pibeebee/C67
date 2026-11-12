import Foundation
import Testing
import C67Data
import C67Domain

/// Opt-in only: calls live MapKit and can make one billed Luna request.
@MainActor struct PocketLiveAcceptanceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["C67_LIVE_ACCEPTANCE"] == "1"))
    func realJakartaDiscoveryAndPlanning() async throws {
        let env = ProcessInfo.processInfo.environment
        let url = try #require(env["C67_LIVE_URL"])
        let token = try #require(env["C67_LIVE_READ_TOKEN"])
        let connection = LiveAcceptanceConnection(url: url, token: token)
        let repository = try PocketPlanningRepository(services: .live(connection: connection), connection: connection, storageURL: nil)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Jakarta"))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: .now))
        let start = try #require(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow))
        var input = PlanningInput(title: "Jakarta live acceptance", origin: .init(latitude: -6.24405, longitude: 106.79826),
                                  places: [], preferences: "", startsAt: start, finishBy: start.addingTimeInterval(9 * 3600),
                                  timeZone: calendar.timeZone.identifier, mode: .automobile)
        var nature: [PlanningPlace] = []
        for brief in [("N01", "jakarta-selatan", ["nature"], ["park"]), ("F01", "jakarta-selatan", ["foodie"], ["japanese_cuisine"]),
                      ("C01", "jakarta-selatan", ["culture", "art"], []), ("K01", "kemayoran", ["nature"], ["park"])] {
            var options = PlanningPreferences()
            options.area = brief.1
            options.themes = Set(brief.2)
            options.labels = Set(brief.3)
            input.enginePreferences = options
            let clock = ContinuousClock.now
            do {
                let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .suggest, input: input))
                let result = try #require(job.result)
                print("POCKET_LIVE \(brief.0) candidates=\(result.candidates.count) elapsed=\(clock.duration(to: .now)) warnings=\(result.warnings)")
                for p in result.candidates {
                    print("POCKET_LIVE \(brief.0) place=\(p.name) source=\(p.sourceID ?? "-") categories=\(p.categories) available=\(p.availabilityVerified)")
                }
                #expect(result.synthetic == false)
                #expect(result.candidates.isEmpty || result.candidates.count >= 3)
                #expect(Set(result.candidates.map(\.id)).count == result.candidates.count)
                if brief.0 == "N01" { nature = result.candidates }
            } catch {
                print("POCKET_LIVE \(brief.0) failed=\(error.localizedDescription) elapsed=\(clock.duration(to: .now))")
                if brief.0 == "N01" { Issue.record("Nature discovery could not run") }
            }
        }
        #expect(nature.count >= 3)
        guard nature.count >= 3 else { return }
        var options = PlanningPreferences()
        options.themes = ["nature"]
        options.labels = ["park"]
        options.usesLuna = true
        options.allowsAIProcessing = true
        options.returnToOrigin = true
        options.flexibleDeparture = true
        input.enginePreferences = options
        input.places = Array(nature.prefix(3))
        let clock = ContinuousClock.now
        do {
            let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .plan, input: input))
            let proposal = try #require(job.result?.proposal)
            print("POCKET_LIVE N01 itinerary verifiedStops=\(input.places.filter(\.availabilityVerified).count) elapsed=\(clock.duration(to: .now)) return=\(proposal.returnTravelSeconds ?? -1)")
            for p in proposal.stops { print("POCKET_LIVE N01 stop=\(p.name) visit=\(p.visitStartsAt ?? p.arrivalAt) end=\(p.departureAt) travel=\(p.travelSeconds)") }
            #expect(proposal.stops.count == 3)
            #expect(proposal.finishesAt <= input.finishBy)
            let trip = try await repository.applyProposal(jobID: job.id, expectedRevision: nil, requestID: UUID())
            #expect(await repository.personalTrips().contains(trip))
        } catch {
            print("POCKET_LIVE N01 itinerary blocked=\(error.localizedDescription) elapsed=\(clock.duration(to: .now))")
            Issue.record("Real itinerary did not complete: \(error.localizedDescription)")
        }
    }
}

private struct LiveAcceptanceConnection: PocketConnectionProviding {
    let url: String
    let token: String
    func credentials() async -> PocketCredentials { .init(serverURL: url, token: token) }
    func update(serverURL: String, token: String) async throws { throw PlanningError.unavailable }
}
