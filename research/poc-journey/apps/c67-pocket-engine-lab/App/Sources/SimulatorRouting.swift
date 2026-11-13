#if DEBUG
    import Foundation
    import MapKit
    import PocketEngine
    import os

    @MainActor
    enum SimulatorRouting {
        struct Leg: Decodable {
            var id: String
            var origin: Coordinate
            var destination: Coordinate
            var departure: Date
        }
        private struct Input: Decodable {
            var legs: [Leg]
            var osrmBase: URL
            var valhallaBase: URL
            var publicDiagnostic: Bool
            var itinerary: PlanFixture?
        }
        private struct PlanFixture: Decodable, Sendable {
            var origin: Coordinate
            var departure: Date
            var deadline: Date
            var venues: [Venue]
            var choices: [StopChoice]
        }
        private struct PlannerTimings: Sendable {
            var first: Double?
            var finished: Double?
            var etaMs: [Double] = []
            var cacheHits = 0
            var retries = 0
        }
        private struct Routed: Sendable {
            var quote: LegQuote
            var geometryPoints: Int? = nil
            var geometryEncodedBytes: Int? = nil

            var fields: [String: Any] {
                var value: [String: Any] = ["seconds": quote.seconds, "meters": quote.meters]
                value["geometryPoints"] = geometryPoints
                value["geometryEncodedBytes"] = geometryEncodedBytes
                return value
            }
        }
        private struct OSRM: Decodable {
            struct Route: Decodable {
                var distance: Double
                var duration: Double
                var geometry: Shape
            }
            struct Shape: Decodable { var coordinates: [[Double]] }
            var code: String
            var routes: [Route]?
        }
        private struct Valhalla: Decodable {
            struct Trip: Decodable {
                struct Summary: Decodable {
                    var time: Double
                    var length: Double
                }
                struct Segment: Decodable { var shape: String }
                var summary: Summary
                var legs: [Segment]
            }
            var trip: Trip
        }

        static func runIfRequested(apple: AppleServices) async {
            guard ProcessInfo.processInfo.arguments.contains("--pocket-routing") else { return }
            let folder = URL.documentsDirectory
            let output = folder.appending(path: "routing-output.json")
            do {
                let input = try Codec.decoder().decode(Input.self, from: Data(contentsOf: folder.appending(path: "routing-input.json")))
                guard (1 ... (input.publicDiagnostic ? 3 : 100)).contains(input.legs.count),
                      input.legs.allSatisfy({ $0.origin.valid && $0.destination.valid && $0.origin != $0.destination }),
                      Set(input.legs.map(\.id)).count == input.legs.count else {
                    throw EngineError.invalid("Ruas pengujian routing tidak valid.")
                }
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForResource = 15
                configuration.httpAdditionalHeaders = ["User-Agent": "C67PocketEngineLab/0.1 (small simulator routing comparison)"]
                let session = URLSession(configuration: configuration)
                defer { session.finishTasksAndInvalidate() }
                var rows: [[String: Any]] = []
                for leg in input.legs {
                    rows.append(await measure("apple_eta", leg: leg) {
                        let value = try await apple.eta(from: leg.origin, to: leg.destination, at: leg.departure)
                        return ["seconds": value.seconds, "meters": value.meters]
                    })
                    rows.append(await measure("apple_route", leg: leg) {
                        let value = try await apple.route(from: leg.origin, to: leg.destination, at: leg.departure)
                        return ["seconds": value.expectedTravelTime, "meters": value.distance, "geometryPoints": value.polyline.pointCount]
                    })
                    rows.append(await measure("osrm", leg: leg) {
                        try await osrm(leg, base: input.osrmBase, session: session).fields
                    })
                    if input.publicDiagnostic { try await Task.sleep(for: .milliseconds(1100)) }
                    rows.append(await measure("valhalla", leg: leg) {
                        try await valhalla(leg, base: input.valhallaBase, session: session).fields
                    })
                    if input.publicDiagnostic { try await Task.sleep(for: .milliseconds(1100)) }
                    let result: [String: Any] = ["publicDiagnostic": input.publicDiagnostic, "rows": rows]
                    try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
                }
                if let plan = input.itinerary, !input.publicDiagnostic {
                    let results = await [
                        comparePlan("apple", fixture: plan) { from, to, time in
                            try await apple.eta(from: from, to: to, at: time)
                        },
                        comparePlan("osrm", fixture: plan) { from, to, time in
                            let leg = Leg(id: "solver", origin: from, destination: to, departure: time)
                            return try await osrm(leg, base: input.osrmBase, session: session).quote
                        },
                        comparePlan("valhalla", fixture: plan) { from, to, time in
                            let leg = Leg(id: "solver", origin: from, destination: to, departure: time)
                            return try await valhalla(leg, base: input.valhallaBase, session: session).quote
                        }
                    ]
                    let result: [String: Any] = ["publicDiagnostic": false, "rows": rows, "itineraries": results]
                    try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
                }
            } catch {
                try? Data(error.localizedDescription.utf8).write(to: folder.appending(path: "routing-error.txt"), options: .atomic)
            }
        }

        private static func comparePlan(_ engine: String, fixture: PlanFixture,
                                        travel: @escaping ItineraryPlanner.Travel) async -> [String: Any] {
            let timings = OSAllocatedUnfairLock(initialState: PlannerTimings())
            let input = TripInput(departure: fixture.departure, deadline: fixture.deadline, origin: fixture.origin,
                                  returnToOrigin: true, maxWaitMinutes: 0, avoidRain: false)
            var output: [String: Any] = ["engine": engine]
            do {
                let plan = try await ItineraryPlanner.make(input: input, choices: fixture.choices, venues: fixture.venues,
                                                           profile: Profile(), travel: travel, weather: { _, _, _ in .init(maxRainChance: nil, summary: "Cuaca dinonaktifkan pada fixture") },
                                                           report: { event in
                                                               timings.withLock { result in
                                                                   switch event {
                                                                   case .firstSchedule(let duration): result.first = milliseconds(duration)
                                                                   case .finished(let duration): result.finished = milliseconds(duration)
                                                                   case .etaAttempt(_, let elapsed, _): result.etaMs.append(milliseconds(elapsed))
                                                                   case .etaCacheHit: result.cacheHits += 1
                                                                   case .etaRetry: result.retries += 1
                                                                   }
                                                               }
                                                           })
                output["stopIDs"] = plan.stops.map(\.venueID)
                output["finish"] = ISO8601DateFormatter().string(from: plan.finish)
                output["travelSeconds"] = plan.stops.reduce(plan.returnSeconds) { $0 + $1.driveSeconds }
                output["searchTruncated"] = plan.searchTruncated
            } catch {
                output["error"] = error.localizedDescription
            }
            let values = timings.withLock { $0 }
            output["firstScheduleMs"] = values.first
            output["plannerMs"] = values.finished
            output["etaAttemptMs"] = values.etaMs
            output["cacheHits"] = values.cacheHits
            output["retries"] = values.retries
            return output
        }

        nonisolated private static func milliseconds(_ duration: Duration) -> Double {
            let parts = duration.components
            return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
        }

        private static func measure(_ engine: String, leg: Leg, operation: () async throws -> [String: Any]) async -> [String: Any] {
            let start = ContinuousClock.now
            var row: [String: Any]
            do { row = try await operation() }
            catch { row = ["error": error.localizedDescription] }
            row["elapsedMs"] = milliseconds(start.duration(to: .now))
            row["engine"] = engine
            row["leg"] = leg.id
            return row
        }

        private static func fetch<T: Decodable>(_ url: URL, session: URLSession) async throws -> T {
            let (data, response) = try await session.data(from: url)
            guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200 else {
                throw EngineError.invalid("Routing HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            return try JSONDecoder().decode(T.self, from: data)
        }

        private static func osrm(_ leg: Leg, base: URL, session: URLSession) async throws -> Routed {
            let coordinates = [leg.origin, leg.destination].map { "\($0.longitude),\($0.latitude)" }.joined(separator: ";")
            let endpoint = base.appending(path: "route/v1/driving/" + coordinates)
                .appending(queryItems: [.init(name: "overview", value: "full"), .init(name: "geometries", value: "geojson")])
            let response: OSRM = try await fetch(endpoint, session: session)
            guard response.code == "Ok", let route = response.routes?.first else { throw EngineError.invalid("OSRM " + response.code) }
            return Routed(quote: .init(seconds: route.duration, meters: route.distance), geometryPoints: route.geometry.coordinates.count)
        }

        private static func valhalla(_ leg: Leg, base: URL, session: URLSession) async throws -> Routed {
            let time = DateFormatter()
            time.locale = Locale(identifier: "en_US_POSIX")
            time.timeZone = TripClock.calendar.timeZone
            time.dateFormat = "yyyy-MM-dd'T'HH:mm"
            let request: [String: Any] = [
                "locations": [leg.origin, leg.destination].map { ["lat": $0.latitude, "lon": $0.longitude] },
                "costing": "auto", "units": "kilometers",
                "date_time": ["type": 1, "value": time.string(from: leg.departure)]
            ]
            let payload = try JSONSerialization.data(withJSONObject: request)
            let endpoint = base.appending(path: "route")
                .appending(queryItems: [.init(name: "json", value: String(decoding: payload, as: UTF8.self))])
            let response: Valhalla = try await fetch(endpoint, session: session)
            return Routed(quote: .init(seconds: response.trip.summary.time, meters: response.trip.summary.length * 1_000),
                          geometryEncodedBytes: response.trip.legs.reduce(0) { $0 + $1.shape.utf8.count })
        }
    }
#endif
