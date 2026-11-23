import C67Domain
import Foundation

public enum PlannerV5Source: Equatable, Sendable {
    case traveller, reservation, localEstimate
    case venue(String), observed(String), suggestion(String)
}

public struct PlannerV5Duration: Equatable, Sendable {
    public var minutes: ClosedRange<Int>
    public var target: Int
    public var source: PlannerV5Source

    public init(minutes: ClosedRange<Int>, target: Int, source: PlannerV5Source) {
        self.minutes = minutes
        self.target = target
        self.source = source
    }
}

public enum PlannerV5Exposure: Sendable, Equatable {
    case indoor, outdoor
}

public enum PlannerV5Goal: Sendable, Hashable {
    case avoidRain, sunrise, sunset, goldenHour
}

public struct PlannerV5Access: Sendable {
    public struct Window: Sendable {
        public var interval: DateInterval
        public var lastEntry: Date?

        public init(_ interval: DateInterval, lastEntry: Date? = nil) {
            self.interval = interval
            self.lastEntry = lastEntry
        }
    }

    /// An empty confirmed or regular set means closed for the supplied date.
    public var windows: [Window]
    public var source: PlannerV5Source

    public init(windows: [Window], source: PlannerV5Source) {
        self.windows = windows
        self.source = source
    }
}

public struct PlannerV5RainSample: Sendable {
    public var interval: DateInterval
    public var probability: Double
    public var source: String

    public init(interval: DateInterval, probability: Double, source: String) {
        self.interval = interval
        self.probability = probability
        self.source = source
    }
}

public enum PlannerV5Light: Sendable {
    case sunrise(Date), sunset(Date), goldenHour(DateInterval)
}

public struct PlannerV5VisitContext: Sendable {
    public var activity: String?
    public var activitySource: PlannerV5Source?
    public var duration: PlannerV5Duration?
    public var exposure: PlannerV5Exposure?
    public var exposureSource: PlannerV5Source?
    public var access: PlannerV5Access?
    public var goals: Set<PlannerV5Goal>
    public var rain: [PlannerV5RainSample]
    public var light: [PlannerV5Light]
    public var lightSource: String?
    public var sunExposure: PlannerV51SunExposure?
    public var sunExposureSource: PlannerV5Source?
    public var outdoorWeather: [PlannerV51WeatherSeries]

    public init(activity: String? = nil, activitySource: PlannerV5Source? = nil,
                duration: PlannerV5Duration? = nil, exposure: PlannerV5Exposure? = nil,
                exposureSource: PlannerV5Source? = nil, access: PlannerV5Access? = nil,
                goals: Set<PlannerV5Goal> = [], rain: [PlannerV5RainSample] = [],
                light: [PlannerV5Light] = [], lightSource: String? = nil,
                sunExposure: PlannerV51SunExposure? = nil, sunExposureSource: PlannerV5Source? = nil,
                outdoorWeather: [PlannerV51WeatherSeries] = []) {
        self.activity = activity
        self.activitySource = activitySource
        self.duration = duration
        self.exposure = exposure
        self.exposureSource = exposureSource
        self.access = access
        self.goals = goals
        self.rain = rain
        self.light = light
        self.lightSource = lightSource
        self.sunExposure = sunExposure
        self.sunExposureSource = sunExposureSource
        self.outdoorWeather = outdoorWeather
    }
}

public struct PlannerV5Input: Sendable {
    /// A resolved single-day planning window. Use PlanningDayWindow to resolve date intent upstream.
    public var trip: PlanningInput
    public var visits: [UUID: PlannerV5VisitContext]
    public var extraTravelMinutes: Int
    /// Overrides the v5.1 target for this trip.
    public var checkInBufferMinutes: Int?

    public init(trip: PlanningInput, visits: [UUID: PlannerV5VisitContext] = [:], extraTravelMinutes: Int = 0,
                checkInBufferMinutes: Int? = nil) {
        self.trip = trip
        self.visits = visits
        self.extraTravelMinutes = extraTravelMinutes
        self.checkInBufferMinutes = checkInBufferMinutes
    }
}

public struct PlannerV5Route: Sendable, Equatable {
    public var seconds: Int
    public var meters: Int?

    public init(seconds: Int, meters: Int? = nil) {
        self.seconds = seconds
        self.meters = meters
    }
}

public struct PlannerV5Leg: Sendable, Equatable {
    public let from: UUID?
    public let to: UUID?
    public let departsAt: Date
    public let arrivesAt: Date
    public let route: PlannerV5Route
}

public struct PlannerV5Visit: Sendable {
    public let placeID: UUID
    public let arrivesAt: Date
    public let startsAt: Date
    public let endsAt: Date
    public let duration: PlannerV5Duration
    public let activity: String?
    public let activitySource: PlannerV5Source?
    public let exposure: PlannerV5Exposure?
    public let exposureSource: PlannerV5Source?
    public let accessSource: PlannerV5Source?
    public let unverifiedAccess: Bool
}

public struct PlannerV5Metric: Sendable {
    public let placeID: UUID
    public let goal: PlannerV5Goal
    /// Rain is probability-weighted minutes, golden hour is minutes, and solar events are 0 or 1.
    public let value: Double?
    public let sources: [String]
}

public struct PlannerV5Schedule: Sendable {
    public let departsAt: Date
    public let finishesAt: Date
    public let visits: [PlannerV5Visit]
    public let legs: [PlannerV5Leg]
    public let drivingMinutes: Int
    public let waitingMinutes: Int
    public let preferredTimeDeviation: Int
    public let metrics: [PlannerV5Metric]
    public internal(set) var checkIns: [PlannerV51CheckIn] = []
    public internal(set) var outdoorVisits: [PlannerV51OutdoorVisit] = []
}

public enum PlannerV5Issue: Hashable, Sendable {
    case access(UUID), visitTime(UUID), checkIn(UUID), waiting(UUID), deadline
    case etaUnavailable(from: UUID?, to: UUID?)
}

public enum PlannerV5Status: Equatable, Sendable {
    case scheduled, conflicts, incomplete
}

public enum PlannerV5Limit: Equatable, Sendable {
    case shortlist, routeQuotes, candidates, sensitivity, unavailableETA
}

public enum PlannerV5Information: Equatable, Sendable {
    case travellerIntent, venueAccess, activitySuggestion
}

public struct PlannerV5EnrichmentRequest: Sendable, Equatable {
    public let placeID: UUID
    public let information: PlannerV5Information
}

public enum PlannerV5EnrichmentAnswer: Sendable {
    case traveller(placeID: UUID, activity: String?, durationMinutes: Int?, exposure: PlannerV5Exposure?)
    case venue(placeID: UUID, access: PlannerV5Access)
    case suggestion(placeID: UUID, activity: String?, duration: PlannerV5Duration?, source: String)
}

public struct PlannerV5Sensitivity: Sendable {
    public let placeID: UUID
    public let minutes: Int
    public let recommendedOrder: [UUID]?
    public let metrics: [PlannerV5Metric]
    public let status: PlannerV5Status
    public let issues: [PlannerV5Issue]
}

public struct PlannerV5Result: Sendable {
    public let status: PlannerV5Status
    public let schedule: PlannerV5Schedule?
    public let fastestComparable: PlannerV5Schedule?
    public let alternative: PlannerV5Schedule?
    public let issues: [PlannerV5Issue]
    public let enrichment: [PlannerV5EnrichmentRequest]
    public let sensitivity: [PlannerV5Sensitivity]
    public let limit: PlannerV5Limit?
    public let routeQuotes: Int
    public let evaluatedCandidates: Int
    public let completeCandidates: Int
    public let reason: String

    public var comparisonWithFastest: PlannerV51Comparison? {
        guard let schedule, let fastestComparable else { return nil }
        return .init(candidate: schedule, reference: fastestComparable)
    }

    public var alternativeComparison: PlannerV51Comparison? {
        guard let schedule, let alternative else { return nil }
        return .init(candidate: alternative, reference: schedule)
    }
}

public enum PlannerV5Error: Error {
    case invalidInput, invalidEnrichment
}
