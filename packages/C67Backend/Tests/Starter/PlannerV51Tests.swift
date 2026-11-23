import C67Domain
import C67PlannerV5
import Foundation
import Testing
@testable import C67Data

@Suite("Planner v5.1 synthetic fixtures")
struct PlannerV51Tests {
    private static let tourID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    private static let parkID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!

    @Test func sameInputShowsBufferTradeoffAgainstV5() async throws {
        let input = Self.checkInInput()
        let v5 = try await PlannerV5(route: Self.checkInRoutes).plan(input)
        let v51 = try await PlannerV51(route: Self.checkInRoutes).plan(input)
        #expect(v5.schedule?.visits.first?.placeID == Self.parkID)
        #expect(v51.schedule?.visits.first?.placeID == Self.tourID)
        #expect(v51.schedule?.checkIns.first?.bufferMinutes == 15)
        #expect(v51.alternative?.checkIns.first?.bufferMinutes == 3)
        #expect(v51.alternative?.checkIns.first?.shortfallMinutes == 12)
        #expect(v51.comparisonWithFastest?.drivingMinutesDelta == 2)
        #expect(v51.routeQuotes == v5.routeQuotes)
    }

    @Test func targetAndWaitLimitAreIndependent() async throws {
        var input = Self.checkInInput()
        input.trip.enginePreferences?.maximumWaitMinutes = 10
        let planner = PlannerV51(route: Self.checkInRoutes)
        let tight = try await planner.plan(input)
        #expect(tight.schedule?.checkIns.first?.bufferMinutes == 3)
        #expect(tight.issues.contains(.waiting(Self.tourID)))

        input.trip.enginePreferences?.maximumWaitMinutes = 30
        input.checkInBufferMinutes = 3
        let capped = try await planner.plan(input)
        #expect(capped.schedule?.checkIns.first?.shortfallMinutes == 0)
        #expect(capped.schedule?.visits.first?.placeID == Self.parkID)

        input.checkInBufferMinutes = nil
        input.extraTravelMinutes = 0
        let zeroDetour = try await planner.plan(input)
        #expect(zeroDetour.schedule?.visits.first?.placeID == Self.parkID)
        #expect(zeroDetour.alternative?.checkIns.first?.bufferMinutes == 15)
    }

    @Test func prioritizesWorstShortfallAcrossTwoSessions() async throws {
        let secondID = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
        var input = Self.checkInInput()
        var second = Self.place(secondID, longitude: 3, minutes: 10)
        second.activitySession = .init(startsAt: Self.at(9, 55), endsAt: Self.at(10, 5))
        input.trip.places.append(second)
        input.extraTravelMinutes = 13
        input.trip.enginePreferences?.maximumWaitMinutes = 60
        let result = try await PlannerV51 { from, to, time, _ in
            let minutes: Int
            switch (Int(from.longitude), Int(to.longitude)) {
            case (0, 1): minutes = 15
            case (0, 2): minutes = 2
            case (1, 2): minutes = 1
            case (2, 1): minutes = 5
            case (1, 3): minutes = 1
            case (2, 3): minutes = time == Self.at(9, 46) ? 5 : 61
            default: minutes = 61
            }
            return .init(seconds: minutes * 60)
        }.plan(input)
        // A worst shortfall of 11 wins over 12 even though its total shortfall is greater.
        #expect(result.schedule?.checkIns.map(\.shortfallMinutes) == [10, 11])
        #expect(result.schedule?.checkIns.last?.deadline == Self.at(9, 55))
        #expect(result.fastestComparable?.checkIns.map(\.shortfallMinutes) == [12, 0])
    }

    @Test func preservesBetterCheckInWhenOutdoorConditionsCompete() async throws {
        var input = Self.checkInInput()
        input.visits[Self.parkID] = .init(exposure: .outdoor, exposureSource: .traveller, outdoorWeather: [
            .init(kind: .apparentTemperature, source: "Synthetic forecast", samples: [
                .init(interval: .init(start: Self.at(9, 0), end: Self.at(9, 30)), value: 26),
                .init(interval: .init(start: Self.at(9, 30), end: Self.at(10, 0)), value: 34)
            ])
        ])
        let result = try await PlannerV51(route: Self.checkInRoutes).plan(input)
        #expect(result.schedule?.visits.first?.placeID == Self.tourID)
        #expect(result.schedule?.checkIns.first?.shortfallMinutes == 0)
        #expect(result.alternative?.checkIns.first?.shortfallMinutes == 12)
        #expect(result.alternativeComparison?.weather.first?.scoreDelta == -8)
    }

    @Test func coolerNoonWinsAndShelterStillReportsUV() async throws {
        var input = Self.weatherInput(laterUV: 6)
        input.visits[Self.parkID]?.sunExposure = .sheltered
        let result = try await PlannerV51(route: Self.equalRoutes).plan(input)
        #expect(result.schedule?.visits.first?.placeID == Self.parkID)
        let visit = try #require(result.schedule?.outdoorVisits.first)
        #expect(result.schedule?.outdoorVisits.count == 1)
        #expect(visit.sunExposure == .sheltered)
        #expect(visit.readings.first { $0.kind == .uvIndex }?.average == 3)
        #expect(visit.readings.first { $0.kind == .directIrradiance } == nil)

        input.visits[Self.parkID]?.exposure = .indoor
        let indoor = try await PlannerV51(route: Self.equalRoutes).plan(input)
        #expect(indoor.schedule?.outdoorVisits.isEmpty == true)
        #expect(indoor.schedule?.visits.first?.placeID == Self.tourID)
    }

    @Test func coolerButHigherUVProducesOneTradeoff() async throws {
        let result = try await PlannerV51(route: Self.equalRoutes).plan(Self.weatherInput(laterUV: 1))
        #expect(result.schedule?.visits.first?.placeID == Self.tourID)
        #expect(result.alternative?.visits.first?.placeID == Self.parkID)
        let changes = try #require(result.alternativeComparison?.weather)
        #expect(changes.first { $0.kind == .apparentTemperature }?.scoreDelta == -80)
        #expect(changes.first { $0.kind == .directIrradiance }?.scoreDelta == -400)
        #expect(changes.first { $0.kind == .uvIndex }?.scoreDelta == 2)
    }

    @Test func missingUVStillAllowsComparableTemperature() async throws {
        var input = Self.weatherInput(laterUV: 6)
        input.visits[Self.parkID]?.outdoorWeather = [
            Self.series(.apparentTemperature, early: 29, late: 34),
            .init(kind: .uvIndex, source: "Synthetic forecast",
                  samples: [.init(interval: .init(start: Self.at(12, 0), end: Self.at(12, 7)), value: 3)])
        ]
        let result = try await PlannerV51(route: Self.equalRoutes).plan(input)
        #expect(result.schedule?.visits.first?.placeID == Self.parkID)
        let changes = try #require(result.comparisonWithFastest?.weather)
        #expect(changes.first { $0.kind == .apparentTemperature }?.scoreDelta == -5)
        #expect(changes.contains { $0.kind == .uvIndex && $0.scoreDelta == nil })
    }

    @Test func comparesCheckInAndOutdoorChoicesWithV42AndV5() async throws {
        for (name, source, route) in [
            ("check-in", Self.checkInInput(), Self.checkInRoutes),
            ("outdoor", Self.weatherInput(laterUV: 6), Self.equalRoutes)
        ] {
            var input = source
            for index in input.trip.places.indices {
                input.trip.places[index].visitConfirmation = .init(
                    opensAt: input.trip.startsAt, closesAt: input.trip.finishBy, publicAccessConfirmed: true
                )
            }
            input.trip.enginePreferences?.orderingMethod = .hybridV42
            input.trip.enginePreferences?.semanticAssistance = .disabled
            let services = PocketPlanningServices(
                travel: { from, to, date, mode in
                    guard let quote = try await route(.init(latitude: from.latitude, longitude: from.longitude),
                                                      .init(latitude: to.latitude, longitude: to.longitude), date, mode) else {
                        throw PlanningError.unavailable
                    }
                    return .init(seconds: Double(quote.seconds), meters: 1000)
                },
                weather: { _, _, _ in .init(maxRainChance: nil, summary: "Synthetic fixture") },
                advise: { _ in throw PlanningError.unavailable }
            )
            let job = PlanningJob(id: UUID(), status: .running, purpose: .firstItinerary, input: input.trip,
                                  createdAt: input.trip.startsAt)
            let legacy = try await V41ItineraryPlanner(
                services: services, hours: { _ in .init(status: "unavailable") }, synthetic: true
            ).plan(job)
            let v42 = try #require(legacy.proposal)
            let v5Result = try await PlannerV5(route: route).plan(input)
            let v51Result = try await PlannerV51(route: route).plan(input)
            let v5 = try #require(v5Result.schedule)
            let v51 = try #require(v51Result.schedule)
            let v42Drive = (v42.stops.map(\.travelSeconds).reduce(0, +) + (v42.returnTravelSeconds ?? 0)) / 60
            #expect(Set(v42.stops.map(\.id)) == Set(input.trip.places.map(\.id)))
            #expect(v42.stops.count == input.trip.places.count)

            if name == "check-in" {
                let deadline = Self.at(9, 20)
                let old = try #require(v42.stops.first { $0.id == Self.tourID }?.arrivalAt)
                let middle = try #require(v5.visits.first { $0.placeID == Self.tourID }?.arrivesAt)
                let new = try #require(v51.checkIns.first?.bufferMinutes)
                let buffers = [deadline.timeIntervalSince(old) / 60, deadline.timeIntervalSince(middle) / 60, new]
                #expect(buffers[1] == 3)
                #expect(buffers[2] == 15)
                print("CONTEXT check-in buffer=\(buffers) drive=\([v42Drive, v5.drivingMinutes, v51.drivingMinutes]) quotes=\([v42.scheduleAssessment?.routeCalls ?? 0, v5Result.routeQuotes, v51Result.routeQuotes])")
            } else {
                let oldPark = try #require(v42.stops.first { $0.id == Self.parkID }?.visitStartsAt)
                let middlePark = try #require(v5.visits.first { $0.placeID == Self.parkID }?.startsAt)
                let newPark = try #require(v51.visits.first { $0.placeID == Self.parkID }?.startsAt)
                let dates = [oldPark, middlePark, newPark].map { Int($0.timeIntervalSince1970 / 60) }
                #expect(dates[1] == 15 * 60 + 10)
                #expect(dates[2] == 12 * 60 + 5)
                print("CONTEXT outdoor start_minute=\(dates) drive=\([v42Drive, v5.drivingMinutes, v51.drivingMinutes]) quotes=\([v42.scheduleAssessment?.routeCalls ?? 0, v5Result.routeQuotes, v51Result.routeQuotes])")
            }
        }
    }

    private static let checkInRoutes: PlannerV5.RouteProvider = { from, to, _, _ in
        switch (Int(from.longitude), Int(to.longitude)) {
        case (0, 1), (2, 1): .init(seconds: 5 * 60)
        case (0, 2): .init(seconds: 2 * 60)
        default: .init(seconds: 4 * 60)
        }
    }

    private static let equalRoutes: PlannerV5.RouteProvider = { _, _, _, _ in .init(seconds: 5 * 60) }

    private static func checkInInput() -> PlannerV5Input {
        var tour = place(tourID, longitude: 1, minutes: 10)
        tour.activitySession = .init(startsAt: at(9, 25), endsAt: at(9, 35), arriveBy: at(9, 20))
        return .init(trip: trip([tour, place(parkID, longitude: 2, minutes: 10)], start: at(9, 0)),
                     extraTravelMinutes: 2)
    }

    private static func weatherInput(laterUV: Double) -> PlannerV5Input {
        let indoor = place(tourID, longitude: 1, minutes: 180)
        let park = place(parkID, longitude: 2, minutes: 20)
        let weather = [series(.apparentTemperature, early: 29, late: 34, threshold: 30),
                       series(.directIrradiance, early: 200, late: 600),
                       series(.uvIndex, early: 3, late: laterUV)]
        return .init(trip: trip([indoor, park], start: at(12, 0)),
                     visits: [tourID: .init(exposure: .indoor, exposureSource: .traveller, outdoorWeather: weather),
                              parkID: .init(exposure: .outdoor, exposureSource: .traveller, sunExposure: .direct,
                                            sunExposureSource: .traveller, outdoorWeather: weather)])
    }

    private static func series(_ kind: PlannerV51WeatherKind, early: Double, late: Double,
                               threshold: Double? = nil) -> PlannerV51WeatherSeries {
        .init(kind: kind, source: "Synthetic forecast", samples: [
            .init(interval: .init(start: at(12, 0), end: at(13, 0)), value: early),
            .init(interval: .init(start: at(15, 0), end: at(16, 0)), value: late)
        ], threshold: threshold)
    }

    private static func place(_ id: UUID, longitude: Double, minutes: Int) -> PlanningPlace {
        var place = PlanningPlace(id: id, name: "Synthetic stop \(longitude)", location: .init(latitude: 0, longitude: longitude),
                                  visitSeconds: minutes * 60)
        place.durationOverridden = true
        return place
    }

    private static func trip(_ places: [PlanningPlace], start: Date) -> PlanningInput {
        var input = PlanningInput(title: "Planner v5.1 fixture", origin: .init(latitude: 0, longitude: 0), places: places,
                                  preferences: "", startsAt: start, finishBy: at(18, 0), timeZone: "UTC",
                                  mode: .automobile)
        var preferences = PlanningPreferences()
        preferences.maximumWaitMinutes = 30
        input.enginePreferences = preferences
        return input
    }

    private static func at(_ hour: Int, _ minute: Int) -> Date {
        Date(timeIntervalSince1970: Double(hour * 60 + minute) * 60)
    }
}
