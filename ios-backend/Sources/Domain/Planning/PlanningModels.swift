import Foundation

public enum PlanningMode: String, Equatable, Sendable, CaseIterable {
    case walking
    case automobile
    case unknown
}

public enum PlanningPurpose: String, Equatable, Sendable, CaseIterable {
    case plan
    case suggest
    case replan
    case unknown
}

public enum PlanningJobStatus: String, Equatable, Sendable, CaseIterable {
    case queued
    case running
    case succeeded
    case failed
    case unknown
}

public enum PersonalTripStatus: String, Equatable, Sendable, CaseIterable {
    case planned
    case active
    case completed
    case unknown
}

public enum PlanningEventKind: String, Equatable, Sendable, CaseIterable {
    case start
    case arrive
    case completeStop = "complete_stop"
    case extendStay = "extend_stay"
}

public struct PlanningPoint: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct PlanningPlace: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var location: PlanningPoint
    public var visitSeconds: Int
    public var website: URL?
    public var preferredAfter: Date?
    public var preferredBefore: Date?
    public init(id: UUID, name: String, location: PlanningPoint, visitSeconds: Int, website: URL? = nil, preferredAfter: Date? = nil, preferredBefore: Date? = nil) {
        self.id = id
        self.name = name
        self.location = location
        self.visitSeconds = visitSeconds
        self.website = website
        self.preferredAfter = preferredAfter
        self.preferredBefore = preferredBefore
    }
}

public struct PlanningInput: Equatable, Sendable {
    public var title: String
    public var origin: PlanningPoint
    public var places: [PlanningPlace]
    public var preferences: String
    public var startsAt: Date
    public var finishBy: Date
    public var timeZone: String
    public var mode: PlanningMode
    public var firstPlaceID: UUID?
    public init(title: String, origin: PlanningPoint, places: [PlanningPlace], preferences: String, startsAt: Date, finishBy: Date, timeZone: String, mode: PlanningMode, firstPlaceID: UUID? = nil) {
        self.title = title
        self.origin = origin
        self.places = places
        self.preferences = preferences
        self.startsAt = startsAt
        self.finishBy = finishBy
        self.timeZone = timeZone
        self.mode = mode
        self.firstPlaceID = firstPlaceID
    }
}

public struct PlanningEvidence: Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var url: URL?
    public var attributionLogoURL: URL?
    public var checkedAt: Date
    public var kind: String
    public var summary: String
    public var synthetic: Bool
    public init(id: String, label: String, url: URL? = nil, checkedAt: Date, kind: String, summary: String, synthetic: Bool, attributionLogoURL: URL? = nil) {
        self.id = id
        self.label = label
        self.url = url
        self.attributionLogoURL = attributionLogoURL
        self.checkedAt = checkedAt
        self.kind = kind
        self.summary = summary
        self.synthetic = synthetic
    }
}

public struct ScheduledPlanningStop: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var location: PlanningPoint
    public var arrivalAt: Date
    public var departureAt: Date
    public var visitSeconds: Int
    public var travelSeconds: Int
    public var warnings: [String]
    public init(id: UUID, name: String, location: PlanningPoint, arrivalAt: Date, departureAt: Date, visitSeconds: Int, travelSeconds: Int, warnings: [String]) {
        self.id = id
        self.name = name
        self.location = location
        self.arrivalAt = arrivalAt
        self.departureAt = departureAt
        self.visitSeconds = visitSeconds
        self.travelSeconds = travelSeconds
        self.warnings = warnings
    }
}

public struct PlanProposal: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var input: PlanningInput
    public var stops: [ScheduledPlanningStop]
    public var finishesAt: Date
    public var feasible: Bool
    public var explanation: String
    public var warnings: [String]
    public var evidence: [PlanningEvidence]
    public var synthetic: Bool
    public init(id: UUID, input: PlanningInput, stops: [ScheduledPlanningStop], finishesAt: Date, feasible: Bool, explanation: String, warnings: [String], evidence: [PlanningEvidence], synthetic: Bool) {
        self.id = id
        self.input = input
        self.stops = stops
        self.finishesAt = finishesAt
        self.feasible = feasible
        self.explanation = explanation
        self.warnings = warnings
        self.evidence = evidence
        self.synthetic = synthetic
    }
}

public struct PlanningResult: Equatable, Sendable {
    public var proposal: PlanProposal?
    public var candidates: [PlanningPlace]
    public var warnings: [String]
    public var synthetic: Bool
    public init(proposal: PlanProposal? = nil, candidates: [PlanningPlace], warnings: [String], synthetic: Bool) {
        self.proposal = proposal
        self.candidates = candidates
        self.warnings = warnings
        self.synthetic = synthetic
    }
}

public struct PlanningRequest: Equatable, Sendable {
    public var requestID: UUID
    public var purpose: PlanningPurpose
    public var input: PlanningInput
    public var tripID: UUID?
    public var baseRevision: Int?
    public var currentOrigin: PlanningPoint?
    public init(requestID: UUID, purpose: PlanningPurpose, input: PlanningInput, tripID: UUID? = nil, baseRevision: Int? = nil, currentOrigin: PlanningPoint? = nil) {
        self.requestID = requestID
        self.purpose = purpose
        self.input = input
        self.tripID = tripID
        self.baseRevision = baseRevision
        self.currentOrigin = currentOrigin
    }
}

public struct PlanningJob: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var status: PlanningJobStatus
    public var purpose: PlanningPurpose
    public var input: PlanningInput
    public var tripID: UUID?
    public var baseRevision: Int?
    public var result: PlanningResult?
    public var errorCode: String?
    public var createdAt: Date
    public init(id: UUID, status: PlanningJobStatus, purpose: PlanningPurpose, input: PlanningInput, tripID: UUID? = nil, baseRevision: Int? = nil, result: PlanningResult? = nil, errorCode: String? = nil, createdAt: Date) {
        self.id = id
        self.status = status
        self.purpose = purpose
        self.input = input
        self.tripID = tripID
        self.baseRevision = baseRevision
        self.result = result
        self.errorCode = errorCode
        self.createdAt = createdAt
    }
}

public struct PersonalPlanningTrip: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var revision: Int
    public var status: PersonalTripStatus
    public var input: PlanningInput
    public var plan: PlanProposal
    public var completedStopIDs: [UUID]
    public var currentStopID: UUID?
    public var currentArrivedAt: Date?
    public var synthetic: Bool
    public var createdAt: Date
    public init(id: UUID, title: String, revision: Int, status: PersonalTripStatus, input: PlanningInput, plan: PlanProposal, completedStopIDs: [UUID], currentStopID: UUID? = nil, currentArrivedAt: Date? = nil, synthetic: Bool, createdAt: Date) {
        self.id = id
        self.title = title
        self.revision = revision
        self.status = status
        self.input = input
        self.plan = plan
        self.completedStopIDs = completedStopIDs
        self.currentStopID = currentStopID
        self.currentArrivedAt = currentArrivedAt
        self.synthetic = synthetic
        self.createdAt = createdAt
    }
}

public struct PlanningEvent: Equatable, Sendable {
    public var requestID: UUID
    public var expectedRevision: Int
    public var kind: PlanningEventKind
    public var stopID: UUID?
    public var extraSeconds: Int?
    public init(requestID: UUID, expectedRevision: Int, kind: PlanningEventKind, stopID: UUID? = nil, extraSeconds: Int? = nil) {
        self.requestID = requestID
        self.expectedRevision = expectedRevision
        self.kind = kind
        self.stopID = stopID
        self.extraSeconds = extraSeconds
    }
}

public extension PlanningInput {
    func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 120,
              preferences.count <= 2000, (1 ... 6).contains(places.count), Set(places.map(\.id)).count == places.count,
              finishBy > startsAt, finishBy.timeIntervalSince(startsAt) <= 86400,
              TimeZone(identifier: timeZone) != nil, mode != .unknown,
              origin.latitude.isFinite, origin.longitude.isFinite,
              abs(origin.latitude) <= 90, abs(origin.longitude) <= 180 else { throw PlanningError.invalidInput }
        for place in places {
            guard !place.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, place.name.count <= 200, (0 ... 86400).contains(place.visitSeconds),
                  place.location.latitude.isFinite, place.location.longitude.isFinite,
                  abs(place.location.latitude) <= 90, abs(place.location.longitude) <= 180 else { throw PlanningError.invalidInput }
            if let website = place.website, website.absoluteString.count > 2048 { throw PlanningError.invalidInput }
            if let after = place.preferredAfter, let before = place.preferredBefore, after > before { throw PlanningError.invalidInput }
        }
        if let firstPlaceID, !places.contains(where: { $0.id == firstPlaceID }) { throw PlanningError.invalidInput }
    }
}

public extension PersonalPlanningTrip {
    var nextStop: ScheduledPlanningStop? { plan.stops.first { !completedStopIDs.contains($0.id) } }
}

public enum PlanningError: Error, Equatable, LocalizedError, Sendable {
    case invalidInput, configurationRequired, authenticationRequired, invalidResponse, notFound
    case revisionConflict, requestConflict, unavailable, rateLimited, expired, failed(String)
    public var errorDescription: String? {
        switch self {
        case .invalidInput: "Choose one to six places, valid visit durations, and a finish time within 24 hours of departure."
        case .configurationRequired: "Live planning is not configured. Set the planning API URL and configure the backend providers."
        case .authenticationRequired: "Sign in to plan and save a personal trip."
        case .invalidResponse: "The planner returned an unexpected result. Your current plan is unchanged."
        case .notFound: "This planning result is no longer available."
        case .revisionConflict: "Your trip changed. Refresh it and request a new proposal."
        case .requestConflict: "This request no longer matches its original input. Start a new request."
        case .unavailable: "Planning is unavailable. Your saved trip is unchanged. Try again."
        case .rateLimited: "The planning limit was reached. Wait before trying again."
        case .expired: "This proposal expired. Request a fresh plan."
        case .failed(let code):
            switch code {
            case "PROVIDER_CONFIGURATION_REQUIRED": "Live AI or Apple data is not configured on the planning server."
            case "ROUTE_UNAVAILABLE": "A route estimate is unavailable. No travel time was invented."
            case "MODEL_CONTEXT_LIMIT": "This request contains too much context. Try fewer places."
            case "PROVIDER_RATE_LIMITED": "A data provider is busy. Try again later."
            case "JOB_EXPIRED": "Planning took too long. Request a fresh proposal."
            default: "A planning provider could not complete this request. Your current plan is unchanged."
            }
        }
    }
}
