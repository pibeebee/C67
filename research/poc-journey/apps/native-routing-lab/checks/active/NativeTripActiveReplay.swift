import Foundation

@main struct ActiveReplay {
    @MainActor static func main() async throws {
        let input =
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var draft = try decoder.decode(
            NativeTripDraft.self, from: JSONSerialization.data(withJSONObject: input["draft"]!))
        draft.routingSeed = Int(CommandLine.arguments[3])!
        let originalStart = draft.departure
        func provider(_ draft: NativeTripDraft) -> NativeTripAppleServices {
            var shifted = input
            let delta = draft.departure.timeIntervalSince(originalStart)
            shifted["oracle"] = (input["oracle"] as! [[String: Any]]).map { arc in
                var value = arc
                value["start"] = (arc["start"] as? Double ?? 0) - delta
                value["end"] = (arc["end"] as? Double ?? 172800) - delta
                return value
            }
            return NativeTripAppleServices(shifted, draft: draft)
        }
        var original = try await NativeTripEngine.plan(
            draft, services: provider(draft), progress: { _ in })
        guard let first = original.fastest, first.feasible else {
            throw NativeTripError.message("Initial fixture is infeasible")
        }
        let variant = input["variant"] as? String ?? "extend"
        if variant == "tight" { original.draft.finishBy = first.finish!.addingTimeInterval(900) }
        let runtime = UUID()
        var active = try NativeTripActiveTrip.start(report: original, at: draft.departure)
        let firstLeg = first.legs[0]
        let currentLeg = first.legs[1]
        func perform(_ command: NativeTripActiveCommand, at: Date) throws {
            try active.perform(
                command, actionID: UUID().uuidString, at: at, original: original, runtimeSessionID: runtime)
        }
        try perform(.arrive(firstLeg.to.id), at: firstLeg.arrival!)
        try perform(.beginVisit(firstLeg.to.id), at: firstLeg.visit!)
        try perform(.depart(firstLeg.to.id), at: firstLeg.leave!)
        try perform(.arrive(currentLeg.to.id), at: currentLeg.arrival!)
        try perform(.beginVisit(currentLeg.to.id), at: currentLeg.visit!)
        let asOf = currentLeg.visit!.addingTimeInterval(600)
        try perform(.extend(30), at: asOf)
        if variant == "skip", let id = active.pendingIDs.last { try perform(.skip(id), at: asOf) }
        if variant == "end-only" { for id in active.pendingIDs { try perform(.skip(id), at: asOf) } }
        let before = active
        let projection = try active.projection(original: original, at: asOf, anchorConfirmed: true)
        let service = provider(projection.draft)
        let started = Date()
        let report: NativeTripReport
        if CommandLine.arguments[2] == "baseline" {
            service.resetRun()
            let byID = Dictionary(uniqueKeysWithValues: projection.draft.stops.map { ($0.id, $0) })
            let candidate = try await NativeTripEngine.evaluate(
                projection.retainedOrder.map { byID[$0]! }, draft: projection.draft, services: service,
                forecasts: [], progress: { _ in })
            report = .init(
                draft: projection.draft, candidates: [candidate],
                fastest: candidate.complete ? candidate : nil,
                forecasts: [], requests: service.directionRequests,
                weatherNote: "No weather in paired replay.")
        } else {
            report = try await NativeTripActivePlanner.plan(
                projection, services: service, progress: { _ in })
        }
        let proposal = NativeTripReplanProposal(
            producerSessionID: runtime, projection: projection, report: report,
            baseline: report.candidates.first)
        if proposal.canApply {
            active.proposal = proposal
            try perform(.apply(proposal.id), at: asOf)
        }
        func object<T: Encodable>(_ value: T) throws -> Any {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            return try JSONSerialization.jsonObject(with: encoder.encode(value))
        }
        let value: [String: Any] = [
            "id": input["id"]!, "arm": CommandLine.arguments[2], "seed": draft.routingSeed!,
            "original": try object(original), "activeBefore": try object(before),
            "activeAfter": try object(active),
            "projection": try object(projection), "report": try object(report),
            "requests": service.directionRequests,
            "requestTrace": service.requests, "solvers": service.logs.solvers,
            "wallSeconds": Date().timeIntervalSince(started),
        ]
        FileHandle.standardOutput.write(
            try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
        FileHandle.standardOutput.write(Data([10]))
    }
}
