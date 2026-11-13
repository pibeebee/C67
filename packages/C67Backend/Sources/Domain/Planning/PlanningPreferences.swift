import Foundation

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
    public init(opensAt: Date, closesAt: Date, publicAccessConfirmed: Bool) {
        self.opensAt = opensAt; self.closesAt = closesAt; self.publicAccessConfirmed = publicAccessConfirmed
    }
}

public struct PlanningConnection: Equatable, Sendable {
    public var serverURL: String
    public var hasToken: Bool
    public init(serverURL: String, hasToken: Bool) { self.serverURL = serverURL; self.hasToken = hasToken }
}
