import Foundation

public enum PlanningTripTiming: String, Codable, Sendable, CaseIterable {
    case now, tomorrow, inAFewDays, bestDay
}

public enum PlanningScheduleSource: String, Codable, Sendable {
    case automatic, timingAnswer, manual, resolved
}

public enum PlanningSemanticAssistance: String, Codable, Sendable, CaseIterable {
    case whenNeeded, disabled, requested
}

public enum PlanningDayPart: String, Codable, Sendable, CaseIterable {
    case morning, afternoon, evening, night

    public var minuteRange: Range<Int> {
        switch self {
        case .morning: 360 ..< 660
        case .afternoon: 660 ..< 900
        case .evening: 900 ..< 1080
        case .night: 1080 ..< 1320
        }
    }
}

public struct PlanningActivitySession: Equatable, Codable, Sendable {
    public var startsAt: Date
    public var endsAt: Date
    public var arriveBy: Date?

    public init(startsAt: Date, endsAt: Date, arriveBy: Date? = nil) {
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.arriveBy = arriveBy
    }
}

public struct PlanningScheduleIssue: Equatable, Codable, Sendable, Identifiable {
    public var code: String
    public var placeID: UUID?
    public var source: String?
    public var id: String { "\(code):\(placeID?.uuidString ?? "trip"):\(source ?? "")" }

    public init(code: String, placeID: UUID? = nil, source: String? = nil) {
        self.code = code
        self.placeID = placeID
        self.source = source
    }

    public func message(in input: PlanningInput) -> String {
        let name = input.places.first { $0.id == placeID }?.name ?? "Trip"
        let detail: String
        switch code {
        case "all_day_closed": detail = "closed for the available window"
        case "visit_outside_hours_or_entry": detail = "visit does not fit the available hours or entry cutoff"
        case "duration_exceeds_all_windows": detail = "visit duration exceeds the available opening windows"
        case "target_outside_availability", "hard_target_missed", "required_target_missed", "session_outside_date": detail = "required visit time conflicts with this schedule"
        case "return_deadline_exceeded", "duration_exceeds_day": detail = "visits and travel exceed the finish time under the selected duration policy"
        case "duration_unknown": detail = "visit duration is needed"
        case "date_access_unverified":
            detail = source == EstimatedVisitWindow.source ? "hours are estimated and need checking before the visit" : "access on this date has not been confirmed"
        case "semantic_unavailable":
            detail = input.enginePreferences?.orderingMethod == .hybridV42FoundationModels ?
                "Foundation Models suggestions are unavailable" : "Luna suggestions are unavailable"
        case "session_arrival_missed": detail = "arrival is later than the session check-in time"
        case "required_visits_overlap": detail = "required activity time overlaps another visit"
        case "waiting_permission_unknown": detail = "waiting needs your confirmation"
        default:
            detail = code.hasPrefix("eta:") ? "a travel estimate is unavailable" : code.replacingOccurrences(of: "_", with: " ")
        }
        return "\(name): \(detail)."
    }
}

public struct PlanningDurationAlternative: Equatable, Codable, Sendable, Identifiable {
    public var placeID: UUID
    public var originalSeconds: Int
    public var proposedSeconds: Int
    public var source: String
    public var startsAt: Date?
    public var finishBy: Date?
    public var id: UUID { placeID }

    public init(placeID: UUID, originalSeconds: Int, proposedSeconds: Int, source: String, startsAt: Date? = nil, finishBy: Date? = nil) {
        self.placeID = placeID
        self.originalSeconds = originalSeconds
        self.proposedSeconds = proposedSeconds
        self.source = source
        self.startsAt = startsAt
        self.finishBy = finishBy
    }
}

public struct PlanningDateAssessment: Equatable, Codable, Sendable {
    public var date: Date
    public var stopReason: String
    public var completeCandidates: Int
    public init(date: Date, stopReason: String, completeCandidates: Int) {
        self.date = date
        self.stopReason = stopReason
        self.completeCandidates = completeCandidates
    }
}

public struct PlanningScheduleAssessment: Equatable, Codable, Sendable {
    public var conflicts: [PlanningScheduleIssue] = []
    public var regularConflicts: [PlanningScheduleIssue] = []
    public var unresolved: [PlanningScheduleIssue] = []
    public var generatedCandidates = 0
    public var evaluatedCandidates = 0
    public var completeCandidates = 0
    public var routeCalls = 0
    public var modelCalls = 0
    public var stopReason = "not_started"
    public var durationPolicy = "target"
    public var dates: [PlanningDateAssessment] = []
    public var durationAlternatives: [PlanningDurationAlternative] = []
    public var preferredPeriodOutsideMinutes: Int?
    public var remainingMinutes: Int?
    public var allCandidatesMissedDeadline = false

    public init() {}

    public var needsAccessConfirmation: Bool {
        unresolved.contains { $0.code == "date_access_unverified" }
    }

    public func messages(in input: PlanningInput) -> [String] {
        var seen = Set<String>()
        return (conflicts + regularConflicts + unresolved).filter { seen.insert($0.id).inserted }.map { $0.message(in: input) }
    }
}

public struct PlanningScheduleFailure: Error, LocalizedError, Sendable {
    public let code: String
    public var assessment: PlanningScheduleAssessment
    public var errorDescription: String? { PlanningError.failed(code).errorDescription }

    public init(code: String, assessment: PlanningScheduleAssessment) {
        self.code = code
        self.assessment = assessment
    }
}

/// An original validated response and its applicability key, retained in the account's job store.
public struct PlanningSemanticSnapshot: Equatable, Codable, Sendable {
    public var contextKey: String
    public var plan: PlanningExperiencePlan

    public init(contextKey: String, plan: PlanningExperiencePlan) {
        self.contextKey = contextKey
        self.plan = plan
    }
}

public extension PlanProposal {
    var usesExperienceFlow: Bool {
        experiencePlan != nil || input.enginePreferences?.orderingMethod?.usesFlexibleSchedule == true
    }

    var effectiveOrderingMethod: PlanningOrderingMethod {
        input.enginePreferences?.orderingMethod ?? experiencePlan?.orderingMethod ?? .luna
    }
}
