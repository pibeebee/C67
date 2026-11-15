import Foundation
import PlannerContracts
@testable import TripIntegration

@main struct BenchMain {
    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        let command = args.dropFirst().first ?? "preflight"
        let env = ProcessInfo.processInfo.environment
        if command == "decision-discovery", args.count >= 3 {
            try await LabDiscoveryProbe.run(directory: URL(fileURLWithPath: args[2], isDirectory: true)); return
        }
        if command == "preflight" {
            let names = ["APPLE_TEAM_ID", "MAPS_KEY_ID", "MAPS_KEY_PATH", "WEATHER_KEY_ID", "WEATHER_KEY_PATH", "WEATHER_SERVICE_ID"]
            let output = ["swiftPlatform": ProcessInfo.processInfo.operatingSystemVersionString,
                          "snapshotHash": try LabSnapshot.hash(), "restConfigured": String((try? LabAppleConfig()) != nil),
                          "missing": names.filter { (env[$0] ?? "").isEmpty }.joined(separator: ","),
                          "providerProbe": "not_attempted_without_credentials"]
            print(String(decoding: try LabJSON.encoder().encode(output), as: UTF8.self)); return
        }
        if command == "probe-native-locations" {
            let search = TripIntegration.MapKitTripSearch()
            let catalog = try PlannerEngine.IntegrationCatalog.load()
            struct Result: Encodable { var id: String; var query: String; var review: TripIntegration.LocationReview }
            var results: [Result] = []
            for id in ["origin", "cikini", "bdt-rbbj", "erasmus", "ragunan", "gbk"] {
                let candidate = catalog.candidate(id)
                let query = candidate?.mapQuery ?? "Bundaran HI Jakarta"
                let pins = try await search.search(query: query)
                let branch: String? = id == "cikini" ? "cikini" : id == "bdt-rbbj" ? "tebet" : nil
                let review = TripIntegration.PlaceIdentityPolicy.review(id: id, query: query,
                                                                        words: candidate?.matchWords ?? ["bundaran", "hi"], branch: branch, results: pins)
                results.append(.init(id: id, query: query, review: review))
            }
            print(String(decoding: try LabJSON.encoder().encode(results), as: UTF8.self)); return
        }
        if command == "probe-locations" {
            let apple = LabAppleREST(config: try .init(), budget: .init(callLimit: 8, cellLimit: 0))
            let search = LabRESTSearch(apple: apple)
            let catalog = try PlannerEngine.IntegrationCatalog.load()
            let ids = ["cikini", "bdt-rbbj", "erasmus", "ragunan", "gbk"]
            struct Result: Encodable { var id: String; var review: PlannerEngine.LocationReview; var parameters: [String: String] }
            var results: [Result] = []
            for id in ["origin"] + ids {
                let candidate = catalog.candidate(id)
                let query = candidate?.mapQuery ?? "Bundaran HI Jakarta"
                let pins = try await search.search(query: query)
                let branch: String? = id == "cikini" ? "cikini" : id == "bdt-rbbj" ? "tebet" : nil
                let review = PlannerEngine.PlaceIdentityPolicy.review(id: id, query: query,
                                                                      words: candidate?.matchWords ?? ["bundaran", "hi"], branch: branch, results: pins)
                results.append(.init(id: id, review: review,
                                     parameters: Dictionary(uniqueKeysWithValues: LabRESTSearch.parameters(query: query).map { ($0.name, $0.value!) })))
            }
            print(String(decoding: try LabJSON.encoder().encode(results), as: UTF8.self))
            return
        }
        if command == "probe" {
            let config = try LabAppleConfig()
            let budget = LabProviderBudget(callLimit: 8, cellLimit: 1)
            let apple = LabAppleREST(config: config, budget: budget)
            let search = try await LabRESTSearch(apple: apple).search(query: "Bundaran HI Jakarta")
            guard let origin = search.first else { throw LabFailure.unavailable("Probe: no search result") }
            let query = LabETAQuery(fromID: "origin", toID: "cikini", fromLatitude: origin.latitude,
                                    fromLongitude: origin.longitude, toLatitude: -6.190, toLongitude: 106.839, mode: "automobile", departure: .now)
            let eta = try await LabRESTETA(apple: apple).values([query])
            let start = PlannerEngine.TripClock.calendar.dateInterval(of: .hour, for: .now)!.start
            let weather = try await LabRESTWeather(apple: apple).fetch(pin: origin, memberIDs: ["origin"],
                                                                       start: start, end: start.addingTimeInterval(3600), allowFallback: false, now: .now)
            print(String(decoding: try LabJSON.encoder().encode([
                "searchResults": String(search.count), "etaStatus": eta[0].status,
                "weatherStatus": weather.status, "attributionPresent": String(weather.credit != nil),
                "calls": String(budget.calls), "cells": String(budget.cells), "evidence": "live_rest_probe"
            ]), as: UTF8.self)); return
        }
        guard ["replay", "fast-replay"].contains(command), args.count >= 3 else {
            print("Usage: planner-bench preflight | replay OUTPUT_DIR (LAB_URL, LAB_ACCESS_TOKEN required)"); return
        }
        let directory = URL(fileURLWithPath: args[2], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let client = try LabClient(baseURL: URL(string: env["LAB_URL"] ?? "http://127.0.0.1:8767")!, token: env["LAB_ACCESS_TOKEN"] ?? "")
        let caps = try await client.capabilities()
        guard caps["providerMode"] == "replay", caps["snapshotHash"] == (try LabSnapshot.hash()) else { throw LabFailure.conflict("Replay server/catal og mismatch") }
        let cases = LabMatrix.cases()
        try LabJSON.encoder().encode(cases).write(to: directory.appendingPathComponent("matrix.json"))
        try LabJSON.encoder().encode(caps).write(to: directory.appendingPathComponent("capabilities.json"))
        var results: [LabObservation] = []
        var accepted: [String: AcceptedState] = [:]
        let run = UUID().uuidString; let original = OriginalDriver()
        for (index, test) in cases.enumerated() {
            let order = command == "fast-replay" ? (index % 2 == 0 ? ["C", "D"] : ["D", "C"]) : [["A", "B", "C"], ["B", "C", "A"], ["C", "A", "B"]][index % 3]
            for variant in order {
                let start = ContinuousClock.now
                var result: LabOutcome?
                var failure: String?
                var baseID: UUID?
                do {
                    if variant == "A" {
                        result = try await original.run(test.request, now: LabMatrix.now,
                                                        directory: directory.appendingPathComponent("A/\(test.id)"), revision: test.revision)
                    } else {
                        var request = test.request
                        let baseline = accepted[variant]
                        if test.revision {
                            guard let baseline, let last = baseline.plan.stops.last else { throw LabFailure.conflict("Revision baseline missing") }
                            request = baseline.plan.request; request.revision += 1
                            request.durationByVenue[last.venueID] = last.duration + 30
                            baseID = baseline.plan.id
                        }
                        let input = JobInput(clientID: run + variant, runID: run, variant: LabVariant(rawValue: variant)!,
                                             snapshotHash: try LabSnapshot.hash(), request: request,
                                             baseRevision: baseline?.revision ?? 0, baseAcceptedID: baseline?.plan.id)
                        let job = try await client.submit(input)
                        result = try await client.wait(job)
                    }
                    // Stop timer only after complete result is persisted by this client.
                    let data = try LabJSON.encoder().encode(result)
                    try data.write(to: directory.appendingPathComponent("\(test.id)-\(variant)-result.json"), options: .atomic)
                } catch { failure = error.localizedDescription }
                let seconds = elapsed(start)
                let row = LabObservation(caseID: test.id, family: test.family, variant: variant,
                                         clientSeconds: seconds, outcome: result, error: failure,
                                         thermal: String(describing: ProcessInfo.processInfo.thermalState), baselineID: baseID)
                results.append(row)
                try LabJSON.encoder().encode(results).write(to: directory.appendingPathComponent("observations.json"), options: .atomic)
                print("LAB_REPLAY \(test.id) \(variant) \(result?.outcome ?? failure ?? "unknown") \(String(format: "%.3f", seconds))s calls=\(result?.providerMetrics.calls ?? 0) cells=\(result?.providerMetrics.cells ?? 0)")
                if variant == "A", test.family == "N5" { try await original.acceptBaseline() }
                if variant != "A", test.family == "N5", let plan = result?.plan, plan.feasible {
                    accepted[variant] = try await client.apply(plan, clientID: run + variant, baseRevision: accepted[variant]?.revision ?? 0)
                }
            }
        }
    }
}
