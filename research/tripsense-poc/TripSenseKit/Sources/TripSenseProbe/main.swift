import Foundation
import TripSenseCore

if CommandLine.arguments.contains("--osm-network-probe") {
    print(await OSMNetworkProbe.run())
} else if CommandLine.arguments.contains("--audit-hours") {
    await auditHours()
} else if let index = CommandLine.arguments.firstIndex(of: "--scenario"), CommandLine.arguments.count > index + 1 {
    await runScenario(CommandLine.arguments[index + 1])
} else {
    print(await FeasibilityExperiment.run())
}

@MainActor func runScenario(_ scenario: String) async {
    let diagnostics = Diagnostics()
    let maps = MapServices(diagnostics: diagnostics)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
    let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date().addingTimeInterval(86400))!
    let p = TripPreferences(start: start, duration: scenario == "D" ? 21600 : (scenario == "B" ? 28800 : 18000),
                            theme: scenario == "D" ? .mixed : .history, count: scenario == "A" ? 3 : 4)
    let request = scenario == "D" ? "Central Jakarta history, a museum and a coffee stop, six hours" : "Central Jakarta historical and cultural attractions, minimize unnecessary walking travel"
    print("Scenario \(scenario). Fixed public Jakarta scenario, live services; no fixture fallback. Start: \(start.ISO8601Format())")
    do {
        let choices = try await ModelPlanner.select(preferences: p, request: request, maps: maps, diagnostics: diagnostics)
        print("Model selected: \(choices.map(\.placeID))")
        for place in maps.places { print("Retrieved: \(place.id) | \(place.name) | \(place.category) | themes \(place.themes.map(\.rawValue).sorted())") }
        let eligible = maps.places.filter { p.theme == .mixed || $0.themes.contains(p.theme) }
        guard eligible.count >= p.count else { throw PlanningError.noPlaces }
        let poolChoices = try CandidateSelector.select(places: eligible,
                                                       proposed: choices.filter { choice in eligible.contains { $0.id == choice.placeID } },
                                                       theme: p.theme, count: min(6, eligible.count))
        let pool = poolChoices.compactMap { choice in eligible.first { $0.id == choice.placeID } }
        let poolIDs = Set(pool.map(\.id))
        let selected = choices.filter { poolIDs.contains($0.placeID) }
        maps.beginOptimization()
        let provider = OSMHoursProvider(diagnostics: diagnostics)
        let trip = try await RouteOptimizer(routes: maps, hours: provider, diagnostics: diagnostics).optimize(
            .init(preferences: p, places: pool, recommendations: selected))
        print("Native accepted: \(trip.stops.count) stops; route meters=\(Int(trip.distance)); travel seconds=\(Int(trip.travelTime)); visit seconds=\(Int(trip.visitTime)); waiting seconds=\(Int(trip.waitingTime))")
        for stop in trip.stops { print("Stop \(stop.place.name): \(stop.arrival.ISO8601Format()) – \(stop.departure.ISO8601Format()); \(stop.hours.label); reason: \(stop.reason)") }
        if let report = trip.report {
            print("Orders=\(report.evaluatedOrders); matrix ETA lookups=\(report.matrixRequests); detailed route lookups=\(report.detailRequests); validated alternatives=\(report.validatedAlternatives); matrix complete=\(report.matrixComplete); network requests=\(report.networkRequests.map(String.init) ?? "unknown"); cache hits=\(report.cacheHits.map(String.init) ?? "unknown")")
            print("Snapshot best seconds=\(report.snapshotTravelTime.map { String(Int($0)) } ?? "unknown"); revalidated baseline seconds=\(report.baselineTravelTime.map { String(Int($0)) } ?? "unavailable"); chosen seconds=\(Int(trip.travelTime))")
        }
    } catch { print("SCENARIO FAILED: \(error.localizedDescription)") }
    for event in diagnostics.events { print(event.message) }
}

@MainActor func auditHours() async {
    let diagnostics = Diagnostics()
    let maps = MapServices(diagnostics: diagnostics)
    let center = Coordinate(-6.1754, 106.8272)
    let wanted = ["National Museum", "Indonesia National Gallery", "Museum Taman Prasasti", "Kopi Nako Monas (Abdul Muis)", "D'Stupid Baker", "Loko Cafe"]
    do {
        _ = try await maps.search(query: "museums in Central Jakarta", center: center, radius: 8000, theme: .history, limit: 8)
        _ = try await maps.search(query: "cafes in Central Jakarta", center: center, radius: 8000, theme: .food, limit: 8)
        let found = wanted.compactMap { name in maps.places.first { $0.name == name } }
        let now = Date(); let zone = TimeZone(identifier: "Asia/Jakarta")!
        let results = await OSMHoursProvider(diagnostics: diagnostics).fetchHours(for: found, start: now, end: now.addingTimeInterval(86400), timeZone: zone)
        print("Public Jakarta hours audit; \(found.count)/\(wanted.count) found by MapKit. OSM data is not owner verification.")
        for name in wanted {
            guard let place = found.first(where: { $0.name == name }) else { print("\(name): no MapKit match"); continue }
            let value = results[place.id] ?? .unknown
            if case let .sourced(_, metadata) = value { print("\(name): OSM expression=\(metadata.expression), source=\(metadata.sourceURL), check_date=\(metadata.checkedDate ?? "unknown"), website=\(metadata.websiteURL?.absoluteString ?? "unknown")") }
            else { print("\(name): \(value.label)") }
        }
    } catch { print("Hours audit failed: \(error.localizedDescription)") }
    for event in diagnostics.events { print(event.message) }
}
