import Foundation
import C67Domain

/// Explicit synthetic, in-memory demonstration. No AI, Apple provider requests or persistence.
public actor MockPlanningRepository: PlanningRepository {
    private var jobs: [UUID: PlanningJob] = [:]
    private var trips: [UUID: PersonalPlanningTrip] = [:]
    private var receipts: [UUID: (Data, Receipt)] = [:]
    private var applied: [UUID: PersonalPlanningTrip] = [:]
    private var pending: UUID?

    private enum Receipt { case job(PlanningJob), trip(PersonalPlanningTrip) }
    public init() {}

    public static func sampleInput() throws -> PlanningInput {
        guard let path = Bundle.module.url(forResource: "planning-input", withExtension: "json") else { throw PlanningError.notFound }
        var value = try SupabaseConnection.decoder().decode(PlanningInputDTO.self, from: Data(contentsOf: path)).domain
        let start = Date().addingTimeInterval(600)
        value.startsAt = start; value.finishBy = start.addingTimeInterval(4 * 3600)
        return value
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = SupabaseConnection.encoder(); encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }
    public func requestPlan(_ request: PlanningRequest) throws -> PlanningJob {
        try request.input.validate()
        let fingerprint = try encoded(PlanningRequestDTO(request))
        if let previous = receipts[request.requestID] {
            guard previous.0 == fingerprint, case .job(let job) = previous.1 else { throw PlanningError.requestConflict }
            return job
        }
        var input = request.input
        if request.purpose == .replan {
            guard let id = request.tripID, let trip = trips[id], trip.revision == request.baseRevision,
                  trip.input == request.input, trip.status != .completed else { throw PlanningError.revisionConflict }
            if trip.status == .active {
                let remaining = trip.plan.stops.filter { !trip.completedStopIDs.contains($0.id) }
                guard let first = remaining.first, Date() < input.finishBy else { throw PlanningError.invalidInput }
                let atCurrent = trip.currentStopID == first.id
                input.startsAt = Date()
                input.origin = atCurrent ? first.location : request.currentOrigin ?? trip.plan.stops.last(where: { trip.completedStopIDs.contains($0.id) })?.location ?? input.origin
                input.firstPlaceID = atCurrent ? first.id : nil
                input.places = remaining.compactMap { stop in
                    guard var place = trip.input.places.first(where: { $0.id == stop.id }) else { return nil }
                    place.visitSeconds = atCurrent && stop.id == first.id ? max(0, Int(ceil(first.departureAt.timeIntervalSinceNow))) : stop.visitSeconds
                    return place
                }
            }
        }
        let result: PlanningResult
        if request.purpose == .suggest {
            let place = PlanningPlace(id: UUID(), name: "Synthetic reading stop", location: .init(latitude: min(90, input.origin.latitude + 0.002), longitude: min(180, input.origin.longitude + 0.002)), visitSeconds: 1800)
            result = .init(proposal: nil, candidates: [place], warnings: ["Synthetic suggestion; review and select it before adding."], synthetic: true)
        } else {
            result = .init(proposal: try makeProposal(input), candidates: [], warnings: [], synthetic: true)
        }
        let job = PlanningJob(id: UUID(), status: .succeeded, purpose: request.purpose, input: input,
                              tripID: request.tripID, baseRevision: request.baseRevision, result: result,
                              errorCode: nil, createdAt: Date())
        jobs[job.id] = job; receipts[request.requestID] = (fingerprint, .job(job)); pending = job.id
        return job
    }
    public func planningJob(id: UUID) throws -> PlanningJob {
        guard let job = jobs[id] else { throw PlanningError.notFound }; return job
    }
    public func resumePlanning() -> PlanningJob? { pending.flatMap { jobs[$0] } }
    public func personalTrips() -> [PersonalPlanningTrip] { trips.values.sorted { $0.createdAt > $1.createdAt } }

    public func applyProposal(jobID: UUID, expectedRevision: Int?, requestID: UUID) throws -> PersonalPlanningTrip {
        let fingerprint = Data("apply:\(jobID):\(expectedRevision.map(String.init) ?? "new")".utf8)
        if let previous = receipts[requestID] {
            guard previous.0 == fingerprint, case .trip(let trip) = previous.1 else { throw PlanningError.requestConflict }; return trip
        }
        guard let job = jobs[jobID], job.baseRevision == expectedRevision else { throw PlanningError.revisionConflict }
        if let previous = applied[jobID] { receipts[requestID] = (fingerprint, .trip(previous)); return previous }
        guard let proposal = job.result?.proposal, proposal.feasible else { throw PlanningError.invalidInput }
        guard Date().timeIntervalSince(job.createdAt) <= 900 else { throw PlanningError.expired }
        var trip: PersonalPlanningTrip
        if let id = job.tripID {
            guard var previous = trips[id], previous.revision == expectedRevision, previous.status != .completed else { throw PlanningError.revisionConflict }
            let visited = previous.plan.stops.filter { previous.completedStopIDs.contains($0.id) }
            previous.plan = proposal; previous.plan.stops = visited + proposal.stops; previous.revision += 1
            trip = previous
        } else {
            trip = .init(id: UUID(), title: job.input.title, revision: 1, status: .planned,
                         input: job.input, plan: proposal, completedStopIDs: [], synthetic: true, createdAt: Date())
        }
        trips[trip.id] = trip; applied[jobID] = trip; receipts[requestID] = (fingerprint, .trip(trip)); pending = nil
        return trip
    }

    public func recordEvent(tripID: UUID, event: PlanningEvent) throws -> PersonalPlanningTrip {
        let fingerprint = try encoded(PlanningEventDTO(event)) + Data(tripID.uuidString.utf8)
        if let previous = receipts[event.requestID] {
            guard previous.0 == fingerprint, case .trip(let trip) = previous.1 else { throw PlanningError.requestConflict }; return trip
        }
        guard var trip = trips[tripID], trip.revision == event.expectedRevision, trip.status != .completed else { throw PlanningError.revisionConflict }
        let next = trip.nextStop
        switch event.kind {
        case .start:
            guard trip.status == .planned else { throw PlanningError.invalidInput }; trip.status = .active
        case .arrive:
            guard trip.status == .active, trip.currentStopID == nil, next?.id == event.stopID,
                  let index = trip.plan.stops.firstIndex(where: { $0.id == event.stopID }) else { throw PlanningError.invalidInput }
            trip.currentStopID = event.stopID; trip.currentArrivedAt = Date()
            trip.plan.stops[index].departureAt = Date().addingTimeInterval(Double(trip.plan.stops[index].visitSeconds))
        case .completeStop:
            guard trip.status == .active, let next, next.id == event.stopID, trip.currentStopID == next.id else { throw PlanningError.invalidInput }
            trip.completedStopIDs.append(next.id); trip.currentStopID = nil; trip.currentArrivedAt = nil
            if trip.completedStopIDs.count == trip.plan.stops.count { trip.status = .completed }
        case .extendStay:
            guard trip.status == .active, next?.id == event.stopID, trip.currentStopID == event.stopID,
                  let extra = event.extraSeconds, (1 ... 7200).contains(extra),
                  let index = trip.plan.stops.firstIndex(where: { $0.id == event.stopID }) else { throw PlanningError.invalidInput }
            trip.plan.stops[index].departureAt = max(Date(), trip.plan.stops[index].departureAt).addingTimeInterval(Double(extra))
        }
        trip.revision += 1; trips[trip.id] = trip; receipts[event.requestID] = (fingerprint, .trip(trip)); return trip
    }

    private func makeProposal(_ input: PlanningInput) throws -> PlanProposal {
        try input.validate()
        var pending = input.places; var from = input.origin; var at = input.startsAt; var stops: [ScheduledPlanningStop] = []
        while !pending.isEmpty {
            let chosen: PlanningPlace
            if input.preservesPlaceOrder { chosen = pending[0] }
            else if stops.isEmpty, let first = input.firstPlaceID, let match = pending.first(where: { $0.id == first }) { chosen = match }
            else { chosen = pending.min { distance(from, $0.location) < distance(from, $1.location) }! }
            let meters = distance(from, chosen.location)
            let travel = meters < 1 ? 0 : max(60, Int(ceil(meters / (input.mode == .walking ? 1.2 : 5))))
            let arrival = at.addingTimeInterval(Double(travel)); let departure = arrival.addingTimeInterval(Double(chosen.visitSeconds))
            var warnings: [String] = []
            if let before = chosen.preferredBefore, arrival > before { warnings.append("Your preferred experience window may be missed. This destination is retained.") }
            if let after = chosen.preferredAfter, arrival < after { warnings.append("Arrival precedes your preferred experience window.") }
            stops.append(.init(id: chosen.id, name: chosen.name, location: chosen.location, arrivalAt: arrival,
                               departureAt: departure, visitSeconds: chosen.visitSeconds, travelSeconds: travel, warnings: warnings))
            at = departure; from = chosen.location; pending.removeAll { $0.id == chosen.id }
        }
        let feasible = at <= input.finishBy
        return .init(id: UUID(), input: input, stops: stops, finishesAt: at, feasible: feasible,
                     explanation: "Synthetic demonstration of trip planning and changes. No hosted AI, real route, traffic, venue research or weather was used.",
                     warnings: feasible ? ["Synthetic estimates; not a real travel plan."] : ["The selected visits do not fit. No destinations were removed or finish time extended."],
                     evidence: [], synthetic: true)
    }
    private func distance(_ a: PlanningPoint, _ b: PlanningPoint) -> Double {
        hypot((a.latitude - b.latitude) * 111000, (a.longitude - b.longitude) * 110000)
    }
}
