import Foundation

/// Only IDs leave/return to the planner. The provider cannot supply new times or destinations.
public struct VisitAdviceRequest: Codable, Sendable {
    public struct Option: Codable, Sendable {
        public var slotID: String
        public var departure: String
        public var finish: String
        public var visits: [Visit]
    }
    public struct Visit: Codable, Sendable {
        public var venueID: String
        public var name: String
        public var start: String
        public var end: String
        public var categories: [String]
        public var supportedAttributes: [String]
        public var weather: String
    }
    public var interests: [String]
    public var refinements: [String]
    public var preferences: [String: String]
    public var preferredVisitMinutes: [String: Int]
    public var day: String
    public var options: [Option]
    public init(plans: [Itinerary], venues: [Venue], profile: Profile, choices: [StopChoice] = []) {
        interests = profile.interests.sorted().map(Interests.title)
        day = plans.first.map { TripClock.day($0.departure) } ?? ""
        refinements = profile.categories.sorted().map(Interests.title)
        preferences = Dictionary(uniqueKeysWithValues: profile.preferences.map { ($0.key.rawValue, $0.value.rawValue) })
        preferredVisitMinutes = Dictionary(uniqueKeysWithValues: choices.compactMap { choice in
            guard case .preferred(let minute) = choice.timing else { return nil }
            return (choice.venueID, minute)
        })
        options = plans.enumerated().map { index, plan in
            Option(slotID: "S\(index + 1)", departure: TripClock.time(plan.departure), finish: TripClock.time(plan.finish), visits: plan.stops.map { stop in
                let venue = venues.first { $0.id == stop.venueID }
                return Visit(venueID: stop.venueID, name: stop.name, start: TripClock.time(stop.visitStart), end: TripClock.time(stop.visitEnd),
                             categories: venue?.effectiveCategories(at: stop.visitStart) ?? [],
                             supportedAttributes: Facet.activityOptions.filter { venue?.status($0, at: stop.visitStart) == .supported && venue?.status($0, at: stop.visitEnd) == .supported }.map(\.rawValue),
                             weather: stop.weather)
            })
        }
    }
    public func selected(_ slotID: String, from plans: [Itinerary]) throws -> Itinerary {
        guard options.count == plans.count, let index = options.firstIndex(where: { $0.slotID == slotID }) else {
            throw EngineError.invalid("Luna mengembalikan slot yang tidak tersedia. Ulangi penyusunan; hasil belum diterbitkan.")
        }
        return plans[index]
    }
}

extension ItineraryPlanner {
    /// Recheck the immutable chosen schedule after awaiting the model; never accept provider-authored times.
    public static func validateSelection(_ plan: Itinerary, input: TripInput, choices: [StopChoice], venues: [Venue], profile: Profile, now: Date = .now) throws {
        func reject() throws -> Never { throw EngineError.invalid("Jadwal pilihan AI tidak lagi memenuhi batas perjalanan atau masa berlaku bukti. Susun ulang.") }
        guard plan.departure >= input.departure, plan.departure >= now.addingTimeInterval(-60), plan.finish <= input.deadline,
              plan.departure <= (input.latestDeparture ?? input.departure),
              plan.stops.count >= input.minimumStops, plan.stops.count <= input.maximumStops,
              plan.returnToOrigin == input.returnToOrigin, plan.origin == input.origin,
              Set(plan.stops.map(\.venueID)).count == plan.stops.count,
              input.lastVenueID.map({ $0 == plan.stops.last?.venueID }) ?? true else { try reject() }
        let ids = Set(plan.stops.map(\.venueID))
        guard choices.filter({ choice in if choice.required { return true }; if case .required = choice.timing { return true }; return false }).allSatisfy({ ids.contains($0.venueID) }) else { try reject() }
        var time = plan.departure
        for stop in plan.stops {
            guard let choice = choices.first(where: { $0.venueID == stop.venueID }), let venue = venues.first(where: { $0.id == stop.venueID }),
                  stop.name == venue.name, stop.coordinate == venue.coordinate,
                  stop.departure == time, stop.driveSeconds.isFinite, stop.driveSeconds >= 0,
                  abs(stop.arrival.timeIntervalSince(stop.departure) - stop.driveSeconds) < 1,
                  stop.visitStart >= stop.arrival, stop.visitStart.timeIntervalSince(stop.arrival) <= Double(input.maxWaitMinutes * 60),
                  abs(stop.visitEnd.timeIntervalSince(stop.visitStart) - Double(choice.durationMinutes * 60)) < 1 else { try reject() }
            let manual = choice.override.flatMap { value -> TripOverride? in
                value.day == TripClock.day(stop.visitStart) && value.publicAccessConfirmed && value.opens >= 0 && value.closes <= 1440 && value.closes > value.opens ? value : nil
            }
            let day = TripClock.calendar.startOfDay(for: stop.visitStart)
            let intervals: [DateInterval]
            if let manual {
                intervals = [DateInterval(start: day.addingTimeInterval(Double(manual.opens * 60)), end: day.addingTimeInterval(Double(manual.closes * 60)))]
            } else { intervals = venue.hours?.windows(on: day) ?? [] }
            guard intervals.contains(where: { stop.visitStart >= $0.start && stop.visitEnd <= $0.end }) else { try reject() }
            var effective = profile
            if manual != nil && effective.preferences[.publicAccess] == .required { effective.preferences[.publicAccess] = .neutral }
            guard Recommender.assess(venue, profile: effective, now: stop.visitEnd).eligible,
                  Recommender.assess(venue, profile: effective, now: stop.visitStart).eligible,
                  manual != nil || venue.hours?.fresh(at: stop.visitEnd) == true,
                  manual == nil || profile.preferences[.publicAccess] != .avoided,
                  manual != nil || venue.status(.publicAccess, at: stop.visitEnd) == .supported else { try reject() }
            if let timing = choice.timing {
                let target = day.addingTimeInterval(Double(timing.minute * 60))
                if case .required = timing, abs(stop.visitStart.timeIntervalSince(target)) >= 1 { try reject() }
                if case .notBefore = timing, stop.visitStart < target { try reject() }
            }
            time = stop.visitEnd
        }
        guard plan.returnSeconds.isFinite, plan.returnSeconds >= 0,
              input.returnToOrigin || plan.returnSeconds == 0,
              abs(plan.finish.timeIntervalSince(time) - plan.returnSeconds) < 1 else { try reject() }
    }
}
