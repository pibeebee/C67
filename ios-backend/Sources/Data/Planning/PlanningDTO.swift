import Foundation
import C67Domain

struct PlanningPointDTO: Codable {
    let latitude: Double
    let longitude: Double
    init(_ value: PlanningPoint) {
        latitude = value.latitude
        longitude = value.longitude
    }
    var domain: PlanningPoint {
        .init(latitude: latitude, longitude: longitude)
    }
}

struct PlanningPlaceDTO: Codable {
    let id: UUID
    let name: String
    let location: PlanningPointDTO
    let visit_seconds: Int
    let website: URL?
    let preferred_after: Date?
    let preferred_before: Date?
    init(_ value: PlanningPlace) {
        id = value.id
        name = value.name
        location = .init(value.location)
        visit_seconds = value.visitSeconds
        website = value.website
        preferred_after = value.preferredAfter
        preferred_before = value.preferredBefore
    }
    var domain: PlanningPlace {
        .init(id: id, name: name, location: location.domain, visitSeconds: visit_seconds, website: website, preferredAfter: preferred_after, preferredBefore: preferred_before)
    }
}

struct PlanningInputDTO: Codable {
    let title: String
    let origin: PlanningPointDTO
    let places: [PlanningPlaceDTO]
    let preferences: String
    let starts_at: Date
    let finish_by: Date
    let time_zone: String
    let mode: String
    let first_place_id: UUID?
    let preserve_place_order: Bool?
    init(_ value: PlanningInput) {
        title = value.title
        origin = .init(value.origin)
        places = value.places.map(PlanningPlaceDTO.init)
        preferences = value.preferences
        starts_at = value.startsAt
        finish_by = value.finishBy
        time_zone = value.timeZone
        mode = value.mode.rawValue
        first_place_id = value.firstPlaceID
        preserve_place_order = value.preservesPlaceOrder ? true : nil
    }
    var domain: PlanningInput {
        .init(title: title, origin: origin.domain, places: places.map(\.domain), preferences: preferences, startsAt: starts_at, finishBy: finish_by, timeZone: time_zone, mode: PlanningMode(rawValue: mode) ?? .unknown, firstPlaceID: first_place_id, preservesPlaceOrder: preserve_place_order ?? false)
    }
}

struct PlanningEvidenceDTO: Codable {
    let id: String
    let label: String
    let url: URL?
    let attribution_logo_url: URL?
    let checked_at: Date
    let kind: String
    let summary: String
    let synthetic: Bool
    init(_ value: PlanningEvidence) {
        id = value.id
        label = value.label
        url = value.url
        attribution_logo_url = value.attributionLogoURL
        checked_at = value.checkedAt
        kind = value.kind
        summary = value.summary
        synthetic = value.synthetic
    }
    var domain: PlanningEvidence {
        .init(id: id, label: label, url: url, checkedAt: checked_at, kind: kind, summary: summary, synthetic: synthetic, attributionLogoURL: attribution_logo_url)
    }
}

struct ScheduledPlanningStopDTO: Codable {
    let id: UUID
    let name: String
    let location: PlanningPointDTO
    let arrival_at: Date
    let departure_at: Date
    let visit_seconds: Int
    let travel_seconds: Int
    let warnings: [String]
    init(_ value: ScheduledPlanningStop) {
        id = value.id
        name = value.name
        location = .init(value.location)
        arrival_at = value.arrivalAt
        departure_at = value.departureAt
        visit_seconds = value.visitSeconds
        travel_seconds = value.travelSeconds
        warnings = value.warnings
    }
    var domain: ScheduledPlanningStop {
        .init(id: id, name: name, location: location.domain, arrivalAt: arrival_at, departureAt: departure_at, visitSeconds: visit_seconds, travelSeconds: travel_seconds, warnings: warnings)
    }
}

struct PlanProposalDTO: Codable {
    let id: UUID
    let input: PlanningInputDTO
    let stops: [ScheduledPlanningStopDTO]
    let finishes_at: Date
    let feasible: Bool
    let explanation: String
    let warnings: [String]
    let evidence: [PlanningEvidenceDTO]
    let synthetic: Bool
    init(_ value: PlanProposal) {
        id = value.id
        input = .init(value.input)
        stops = value.stops.map(ScheduledPlanningStopDTO.init)
        finishes_at = value.finishesAt
        feasible = value.feasible
        explanation = value.explanation
        warnings = value.warnings
        evidence = value.evidence.map(PlanningEvidenceDTO.init)
        synthetic = value.synthetic
    }
    var domain: PlanProposal {
        .init(id: id, input: input.domain, stops: stops.map(\.domain), finishesAt: finishes_at, feasible: feasible, explanation: explanation, warnings: warnings, evidence: evidence.map(\.domain), synthetic: synthetic)
    }
}

struct PlanningResultDTO: Codable {
    let proposal: PlanProposalDTO?
    let candidates: [PlanningPlaceDTO]
    let warnings: [String]
    let synthetic: Bool
    init(_ value: PlanningResult) {
        proposal = value.proposal.map { .init($0) }
        candidates = value.candidates.map(PlanningPlaceDTO.init)
        warnings = value.warnings
        synthetic = value.synthetic
    }
    var domain: PlanningResult {
        .init(proposal: proposal?.domain, candidates: candidates.map(\.domain), warnings: warnings, synthetic: synthetic)
    }
}

struct PlanningRequestDTO: Codable {
    let request_id: UUID
    let purpose: String
    let input: PlanningInputDTO
    let trip_id: UUID?
    let base_revision: Int?
    let current_origin: PlanningPointDTO?
    init(_ value: PlanningRequest) {
        request_id = value.requestID
        purpose = value.purpose.rawValue
        input = .init(value.input)
        trip_id = value.tripID
        base_revision = value.baseRevision
        current_origin = value.currentOrigin.map { .init($0) }
    }
    var domain: PlanningRequest {
        .init(requestID: request_id, purpose: PlanningPurpose(rawValue: purpose) ?? .unknown, input: input.domain, tripID: trip_id, baseRevision: base_revision, currentOrigin: current_origin?.domain)
    }
}

struct PlanningJobDTO: Codable {
    let id: UUID
    let status: String
    let purpose: String
    let input: PlanningInputDTO
    let trip_id: UUID?
    let base_revision: Int?
    let result: PlanningResultDTO?
    let error_code: String?
    let created_at: Date
    init(_ value: PlanningJob) {
        id = value.id
        status = value.status.rawValue
        purpose = value.purpose.rawValue
        input = .init(value.input)
        trip_id = value.tripID
        base_revision = value.baseRevision
        result = value.result.map { .init($0) }
        error_code = value.errorCode
        created_at = value.createdAt
    }
    var domain: PlanningJob {
        .init(id: id, status: PlanningJobStatus(rawValue: status) ?? .unknown, purpose: PlanningPurpose(rawValue: purpose) ?? .unknown, input: input.domain, tripID: trip_id, baseRevision: base_revision, result: result?.domain, errorCode: error_code, createdAt: created_at)
    }
}

struct PersonalPlanningTripDTO: Codable {
    let id: UUID
    let title: String
    let revision: Int
    let status: String
    let input: PlanningInputDTO
    let plan: PlanProposalDTO
    let completed_stop_ids: [UUID]
    let current_stop_id: UUID?
    let current_arrived_at: Date?
    let synthetic: Bool
    let created_at: Date
    init(_ value: PersonalPlanningTrip) {
        id = value.id
        title = value.title
        revision = value.revision
        status = value.status.rawValue
        input = .init(value.input)
        plan = .init(value.plan)
        completed_stop_ids = value.completedStopIDs
        current_stop_id = value.currentStopID
        current_arrived_at = value.currentArrivedAt
        synthetic = value.synthetic
        created_at = value.createdAt
    }
    var domain: PersonalPlanningTrip {
        .init(id: id, title: title, revision: revision, status: PersonalTripStatus(rawValue: status) ?? .unknown, input: input.domain, plan: plan.domain, completedStopIDs: completed_stop_ids, currentStopID: current_stop_id, currentArrivedAt: current_arrived_at, synthetic: synthetic, createdAt: created_at)
    }
}

struct PlanningEventDTO: Codable {
    let request_id: UUID
    let expected_revision: Int
    let kind: String
    let stop_id: UUID?
    let extra_seconds: Int?
    init(_ value: PlanningEvent) {
        request_id = value.requestID
        expected_revision = value.expectedRevision
        kind = value.kind.rawValue
        stop_id = value.stopID
        extra_seconds = value.extraSeconds
    }
    var domain: PlanningEvent {
        .init(requestID: request_id, expectedRevision: expected_revision, kind: PlanningEventKind(rawValue: kind) ?? .start, stopID: stop_id, extraSeconds: extra_seconds)
    }
}
