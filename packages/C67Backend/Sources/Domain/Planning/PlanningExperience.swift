import Foundation

/// An untimed experience recommendation. Provider context is distinct from suggested activities.
public struct PlanningExperiencePlan: Equatable, Codable, Sendable {
    public struct Activity: Equatable, Codable, Sendable {
        public var suggestion: String
        public var basis: String
    }
    public struct Duration: Equatable, Codable, Sendable {
        public var minMinutes: Int
        public var maxMinutes: Int
        public var rationale: String
        public var basis: String
        public var suggestedSeconds: Int { (minMinutes + (maxMinutes - minMinutes) / 2) * 60 }
    }
    public struct WeatherAdvice: Equatable, Codable, Sendable {
        public var sourceRefs: [String]
        public var advice: String
        public var status: String
    }
    public struct LightAdvice: Equatable, Codable, Sendable {
        public var windowRef: String?
        public var priority: String
        public var advice: String
    }
    public struct Stop: Equatable, Codable, Sendable {
        public var placeID: UUID
        public var activity: Activity
        public var role: String
        public var duration: Duration?
        public var durationUnknownReason: String?
        public var preferredDayPart: String
        public var reason: String
        public var weather: WeatherAdvice
        public var light: LightAdvice
        public var uncertainties: [String]
        public var dayPartLabel: String {
            switch preferredDayPart {
            case "morning": "Morning"
            case "afternoon": "Midday"
            case "evening": "Late afternoon"
            case "night": "Night"
            case "flexible": "Flexible"
            default: "Not suggested"
            }
        }
    }
    public struct WeatherSource: Equatable, Codable, Sendable, Identifiable {
        public struct Hour: Equatable, Codable, Sendable {
            public var start: Date
            public var end: Date
            public var period: String
            public var precipitationChance: Double
            public var precipitationAmountMM: Double
            public var precipitationType: String
            public var cloudCover: Double
            public var cloudCoverValidAt: Date
        }
        public var id: String
        public var placeID: UUID
        public var source: String
        public var url: URL
        public var checkedAt: Date
        public var date: String
        public var timeZone: String
        public var coordinates: PlanningPoint
        public var hourlySamples: [Hour]
        public var coverage: String
        public var fallbackReason: String?
        public var attributionLogoURL: URL? = nil
    }
    public struct LightWindow: Equatable, Codable, Sendable, Identifiable {
        public var id: String
        public var placeID: UUID
        public var date: String
        public var timeZone: String
        public var start: Date
        public var end: Date
        public var period: String
        public var method: String
    }
    public var status: String
    public var orderedIDs: [UUID]
    public var tripRationale: String
    public var stops: [Stop]
    public var alternativeOrder: [UUID]?
    public var tradeoffs: [String]
    public var uncertainties: [String]
    public var generatedAt: Date
    public var candidateDate: String
    public var timeZone: String
    public var requestedModel: String
    public var reportedModel: String
    public var reportedReasoningEffort: String?
    public var providerProtocol: String?
    public var weatherSources: [WeatherSource]
    public var solarWindows: [LightWindow]
    public var contextWarnings: [String]
    public var orderingMethod: PlanningOrderingMethod? = nil

    public func stop(_ id: UUID) -> Stop? { stops.first { $0.placeID == id } }
}

public extension PlanProposal {
    static let defaultExperienceTravelSeconds = 6 * 60
    static let defaultExperienceVisitSeconds = 30 * 60

    /// A device estimate. The candidate day comes from the request; the clock time is a default or user choice.
    var estimatedExperienceDeparture: Date? {
        guard experiencePlan != nil else { return nil }
        if let departureAt { return departureAt }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: input.timeZone) ?? .current
        return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: input.startsAt)
    }

    var hasExperienceTravelFallback: Bool {
        experiencePlan != nil && stops.contains { $0.roadDistanceMeters == nil }
    }

    /// Presentation estimates are derived without changing the provider proposal or claiming route feasibility.
    var stopsWithExperienceEstimates: [ScheduledPlanningStop] {
        if input.enginePreferences?.orderingMethod == .hybridV4 { return stops }
        guard var clock = estimatedExperienceDeparture else { return stops }
        return stops.map { stop in
            var estimate = stop
            estimate.travelSeconds = stop.experienceTravelSeconds
            estimate.visitSeconds = stop.experienceVisitSeconds
            estimate.arrivalAt = clock.addingTimeInterval(Double(estimate.travelSeconds))
            clock = clock.addingTimeInterval(Double(estimate.travelSeconds + estimate.visitSeconds))
            estimate.departureAt = clock
            return estimate
        }
    }
}

public extension ScheduledPlanningStop {
    var experienceTravelSeconds: Int {
        roadDistanceMeters == nil ? PlanProposal.defaultExperienceTravelSeconds : travelSeconds
    }

    var experienceVisitSeconds: Int {
        visitSeconds > 0 ? min(visitSeconds, 86_400) : PlanProposal.defaultExperienceVisitSeconds
    }
}
