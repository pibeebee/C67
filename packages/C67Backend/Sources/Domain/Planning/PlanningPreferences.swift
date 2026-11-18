import Foundation

public enum PlanningOrderingMethod: String, Codable, CaseIterable, Sendable {
    case luna
    case hybridLegacy = "hybrid_legacy"
    case hybridWeather = "hybrid_weather"
    case hybridV4 = "hybrid_v4"
    case hybridV41 = "hybrid_v4_1"
    case hybridV42 = "hybrid_v4_2"

    public var usesFlexibleSchedule: Bool { self == .hybridV41 || self == .hybridV42 }
    public var isSchedule: Bool { self == .hybridV4 || usesFlexibleSchedule }
}

public enum PlanningVisitTiming: String, Codable, Sendable, CaseIterable {
    case preferred, required, notBefore
}

public enum PlanningCondition: String, Codable, CaseIterable, Sendable {
    case neutral, liked, required, avoided
}

/// Structured on-device preferences. The prose field remains a user wish, not a source of facts.
public struct PlanningPreferences: Equatable, Codable, Sendable {
    public var themes: Set<String> = []
    public var labels: Set<String> = []
    public var conditions: [String: PlanningCondition] = [:]
    public var area = "jakarta-selatan"
    public var flexibleDeparture = false
    public var returnToOrigin = false
    public var maximumWaitMinutes = 0
    public var avoidRain = false
    public var usesLuna = true
    public var allowsAIProcessing = false
    public var lastPlaceID: UUID?
    public var automaticFirstPlan: Bool?
    public var reasonableOrdering: Bool?
    public var orderingMethod: PlanningOrderingMethod?
    public var usesAutomaticTripDate: Bool?
    public var mainSpotID: UUID?
    public var endPoint: PlanningPoint?
    public var endPointName: String?
    public var tripTiming: PlanningTripTiming?
    public var preferredDayPart: PlanningDayPart?
    public var scheduleSource: PlanningScheduleSource?
    public var timingAnchor: Date?
    public var semanticAssistance: PlanningSemanticAssistance?
    public init() {}
}

public struct PlanningPreferenceLabel: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let group: String
    public let allowsCondition: Bool
    public init(id: String, title: String, group: String, allowsCondition: Bool = false) {
        self.id = id; self.title = title; self.group = group; self.allowsCondition = allowsCondition
    }
}

/// A traveller's confirmation for one trip date; never promoted to public venue evidence.
public struct PlanningVisitConfirmation: Equatable, Codable, Sendable {
    public var opensAt: Date
    public var closesAt: Date
    public var publicAccessConfirmed: Bool
    public var lastEntryAt: Date?
    public init(opensAt: Date, closesAt: Date, publicAccessConfirmed: Bool) {
        self.opensAt = opensAt; self.closesAt = closesAt; self.publicAccessConfirmed = publicAccessConfirmed
    }
}

public struct PlanningConnection: Equatable, Sendable {
    public var serverURL: String
    public var hasToken: Bool
    public init(serverURL: String, hasToken: Bool) { self.serverURL = serverURL; self.hasToken = hasToken }
}
