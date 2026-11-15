import Foundation

@main struct LiveJakartaProbe {
    @MainActor static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func write<T: Encodable>(_ value: T, _ name: String) throws {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
        }
        func facts<T: Encodable>(_ value: T) throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(value)
        }
        let logs = NativeTripLogStore(directory: directory.appendingPathComponent("logs"))
        let draft = NativeTripDraft.jakartaFivePlaces()
        try draft.validate()
        try write(draft, "input.json")
        let provider = NativeTripAppleServices(
            logs: logs, operationID: "jakarta-live-initial", requestLimit: 512)
        let initialStart = Date()
        let report = try await NativeTripTimeAwarePlanner.plan(draft, services: provider) { print($0) }
        try write(report, "initial-report.json")
        try NativeTripLocalSession.validateAccepted(report)
        guard let initial = report.fastest, initial.complete, initial.feasible,
              initial.legs.count == 6, initial.legs.last?.to.id == draft.origin.id,
              initial.legs.allSatisfy({ $0.chosen?.mode == .automobile })
        else {
            fatalError("Live initial itinerary is not complete/feasible automobile")
        }
        let initialSeconds = Date().timeIntervalSince(initialStart)
        print("PASS initial five-stop live automobile itinerary")
        let store = NativeTripLocalStore(directory: directory.appendingPathComponent("storage"))
        var session = try store.commit(.init(draft: draft, acceptedReport: report), expected: nil)
        var active = try NativeTripActiveTrip.start(report: report, at: draft.departure)
        let runtime = UUID()
        func perform(_ command: NativeTripActiveCommand, at: Date) throws {
            try active.perform(
                command, actionID: UUID().uuidString, at: at,
                original: report, runtimeSessionID: runtime)
            var next = session
            next.activeTrip = active
            session = try store.commit(next, expected: session)
        }
        // These are scripted reported facts for a future test day, not real attendance.
        let first = initial.legs[0]
        let second = initial.legs[1]
        try perform(.arrive(first.to.id), at: first.arrival!)
        try perform(.beginVisit(first.to.id), at: first.visit!)
        try perform(.depart(first.to.id), at: first.leave!)
        try perform(.arrive(second.to.id), at: second.arrival!)
        try perform(.beginVisit(second.to.id), at: second.visit!)
        let asOf = second.visit!.addingTimeInterval(600)
        try perform(.extend(30), at: asOf)
        let before = active
        let projection = try active.projection(original: report, at: asOf, anchorConfirmed: true)
        let replanProvider = NativeTripAppleServices(
            logs: logs, operationID: "jakarta-live-replan", requestLimit: 512)
        let replanStart = Date()
        let replan = try await NativeTripActivePlanner.plan(projection, services: replanProvider) {
            print($0)
        }
        try write(replan, "replan-report.json")
        let proposal = NativeTripReplanProposal(
            producerSessionID: runtime, projection: projection,
            report: replan, baseline: replan.candidates.first)
        guard proposal.canApply else { fatalError("Live replan is not applicable") }
        active.proposal = proposal
        try perform(.apply(proposal.id), at: asOf)
        guard try facts(active.visits) == facts(before.visits),
              try facts(active.actualLegs) == facts(before.actualLegs),
              active.acceptedRemaining?.draft.endPoint == draft.origin
        else {
            fatalError("Actual history or endpoint changed")
        }
        let loaded = try store.load().session!
        guard try facts(loaded.activeTrip!.visits) == facts(active.visits),
              loaded.activeTrip?.acceptedRemaining?.fastest?.order
              == active.acceptedRemaining?.fastest?.order
        else {
            fatalError("Active restore mismatch")
        }
        try write(loaded, "restored-session.json")
        let replanSeconds = Date().timeIntervalSince(replanStart)
        // Explicitly skip all pending visits, then only route to the original endpoint.
        for id in active.pendingIDs { try perform(.skip(id), at: asOf) }
        let departureFromSecond = active.current!.plannedLeaveAt!
        try perform(.depart(second.to.id), at: departureFromSecond)
        let endProjection = try active.projection(
            original: report, at: departureFromSecond, anchorConfirmed: true)
        let endProvider = NativeTripAppleServices(
            logs: logs, operationID: "jakarta-live-end-only", requestLimit: 16)
        let endReport = try await NativeTripActivePlanner.plan(endProjection, services: endProvider) {
            print($0)
        }
        try write(endReport, "end-only-report.json")
        guard let endCandidate = endReport.fastest, endCandidate.feasible,
              endCandidate.order.isEmpty, endCandidate.legs.count == 1,
              endCandidate.legs[0].to.id == draft.origin.id
        else { fatalError("End-only failed") }
        let endProposal = NativeTripReplanProposal(
            producerSessionID: runtime, projection: endProjection,
            report: endReport, baseline: endCandidate)
        active.proposal = endProposal
        try perform(.apply(endProposal.id), at: departureFromSecond)
        try perform(.finish, at: endCandidate.finish!)
        let completed = try store.load().session!
        guard completed.activeTrip?.isActive == false else { fatalError("Completed restore failed") }
        try write(completed, "completed-session.json")
        let queries = ["Monas", "Kota Tua", "Kota Tua Padang"]
        var searches: [[String: Any]] = []
        for query in queries {
            do {
                let matches = try await provider.searchPlaces(
                    NativeTripListInput.searchQuery(name: query, context: NativeTripJakarta.context),
                    region: NativeTripJakarta.region)
                let eligible = matches.filter {
                    NativeTripJakarta.contains(latitude: $0.latitude, longitude: $0.longitude)
                }
                let requested = NativeTripPoint(
                    id: "search", title: query, query: query,
                    searchRegion: NativeTripJakarta.region)
                let automatic = NativeTripLocationSelection.automaticMatch(
                    eligible, point: requested,
                    context: NativeTripJakarta.context, requireExactName: true)
                searches.append([
                    "automaticSelection": automatic?.name as Any? ?? NSNull(),
                    "query": query, "rawCount": matches.count, "eligibleCount": eligible.count,
                    "eligible": eligible.map {
                        [
                            "name": $0.name, "address": $0.address, "latitude": $0.latitude,
                            "longitude": $0.longitude,
                        ] as [String: Any]
                    },
                ])
            } catch {
                searches.append(["query": query, "error": error.localizedDescription])
            }
        }
        try JSONSerialization.data(withJSONObject: searches, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("search-results.json"))
        let summary: [String: Any] = [
            "initialComplete": true, "initialFeasible": true,
            "initialRequests": report.requests, "initialWallSeconds": initialSeconds,
            "initialTravelMinutes": initial.travelMinutes,
            "initialElapsedMinutes": initial.elapsedMinutes,
            "initialOrder": initial.order, "initialFinish": initial.finish!.ISO8601Format(),
            "replanComplete": replan.fastest!.complete, "replanFeasible": replan.fastest!.feasible,
            "replanRequests": replan.requests, "replanWallSeconds": replanSeconds,
            "replanOrder": replan.fastest!.order, "replanFinish": replan.fastest!.finish!.ISO8601Format(),
            "actualHistoryPreserved": true, "restorePassed": true,
            "endOnlyComplete": true, "endOnlyRequests": endReport.requests, "finishRestorePassed": true,
            "weatherProviders": Array(Set(report.forecasts.compactMap { $0.provider?.rawValue })),
            "reportedFacts": "Scripted test facts, not actual attendance",
            "environment":
                "macOS executable; same production MapKit/weather/planner/domain/storage source; no iPhone claim",
        ]
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("summary.json"))
        await logs.flush()
        print("PASS live remaining-trip replan, apply and restore; scripted facts preserved")
    }
}
