#if DEBUG
    import Foundation
    import C67Domain
    import PocketEngine

    /// Explicit synthetic transport around the real repository, only for local integration tests.
    public enum PocketIntegrationFixture {
        private actor Connection: PocketConnectionProviding {
            let hoursPort: Int?
            init(hoursPort: Int? = nil) { self.hoursPort = hoursPort }
            func credentials() -> PocketCredentials {
                if let hoursPort { return .init(serverURL: "http://127.0.0.1:\(hoursPort)", token: "0") }
                return .init(serverURL: "https://fixture.invalid", token: "synthetic-fixture-token")
            }
            func update(serverURL: String, token: String) {}
        }
        public static func lateDay(on date: Date = .now) -> Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
            return calendar.date(bySettingHour: 23, minute: 40, second: 0, of: date)!
        }

        public static func input() -> PlanningInput {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!
            let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
            var input = PlanningInput(title: "Pocket integration test", origin: .init(latitude: -6.25, longitude: 106.8), places: [], preferences: "",
                                      startsAt: start, finishBy: start.addingTimeInterval(10 * 3600), timeZone: "Asia/Jakarta", mode: .automobile)
            input.enginePreferences = PlanningPreferences()
            return input
        }
        public static func catalog() throws -> Catalog {
            let checked = Date(), expires = checked.addingTimeInterval(7 * 86400)
            let formatter = ISO8601DateFormatter()
            let venues: [[String: Any]] = (1 ... 6).map { index in
                ["id": "fixture-japanese-\(index)", "name": "Fixture \(index <= 3 ? "Japanese" : "Korean") \(index)", "branch": "Fixture \(index)", "address": "Synthetic test location",
                 "coordinate": ["latitude": -6.25 - Double(index) / 5000, "longitude": 106.8],
                 "categories": ["restaurant", index <= 3 ? "japanese_cuisine" : "korean_cuisine"], "aliases": [], "sourceURLs": ["https://fixture.invalid/\(index)"], "operatorURLs": [],
                 "license": "Synthetic integration fixture; not real venue evidence",
                 "facts": [["field": "publicAccess", "status": "supported", "value": "Synthetic fixture access", "sourceURL": "https://fixture.invalid/access",
                            "quote": "Synthetic fixture only", "checkedAt": formatter.string(from: checked), "expiresAt": formatter.string(from: expires)]],
                 "hours": ["intervals": (1 ... 7).map { ["weekday": $0, "startMinute": 0, "endMinute": 1440] },
                           "checkedAt": formatter.string(from: checked), "expiresAt": formatter.string(from: expires), "sourceURL": "https://fixture.invalid/hours", "quote": "Synthetic fixture hours"]]
            }
            let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "generatedAt": formatter.string(from: checked),
                                                                   "attribution": "Synthetic Pocket integration fixture", "venues": venues])
            return try Codec.decoder().decode(Catalog.self, from: data).validated()
        }
        public static func searchablePlaces() throws -> [PlanningPlace] {
            var places = try catalog().venues.map { venue in
                PlanningPlace(id: PocketPlanningRepository.identity(venue.id), name: venue.name,
                              location: .init(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude),
                              visitSeconds: 2700)
            }
            places.insert(.init(id: PocketPlanningRepository.identity("fixture-unknown"), name: "Fixture Unknown Hours",
                                location: .init(latitude: -6.2515, longitude: 106.8), visitSeconds: 2700), at: 2)
            return places
        }

        public static func resolution(_ input: PlanningInput, catalog: Catalog) -> PocketVisitResolution {
            let records = input.places.map { place -> PocketVisitResolution.Record in
                let venue = catalog.venues.first {
                    $0.id == place.sourceID || PocketPlanningRepository.identity($0.id) == place.id
                }
                return .init(placeID: place.id, status: venue == nil ? "unresolved" : "ready",
                             reason: venue == nil ? "Visit information is still unresolved after web research." : nil,
                             venue: venue, recommendedMinutes: place.id == input.enginePreferences?.mainSpotID ? 75 : 45,
                             preferredMinute: nil, recommendationReason: "Synthetic fixture", snapshotID: "synthetic-fixture")
            }
            return .init(resolvedAt: .now, records: records, requestedModel: "cx/gpt-6-luna(max)", reportedModel: "gpt-6-luna(max)")
        }

        private actor OrderInterruption {
            private var attempted = Set<UUID>()
            func check(_ id: UUID, failure: PlanningError?) throws {
                if let failure, attempted.insert(id).inserted { throw failure }
            }
        }

        public static func repository(storageURL: URL? = nil, jobClock: @escaping @Sendable () -> Date = { .now },
                                      firstOrderFailure: PlanningError? = nil, externalAIDisclosure: String? = nil,
                                      includesPinDetails: Bool = false,
                                      hoursPort: Int? = nil) throws -> PocketPlanningRepository {
            let interruption = OrderInterruption()
            let connection = Connection(hoursPort: hoursPort)
            var services = PocketPlanningServices(travel: { _, _, _, _ in .init(seconds: 120, meters: 500) },
                                                  weather: { _, _, _ in .init(maxRainChance: nil, summary: "Synthetic test; no live weather") },
                                                  advise: { _ in .init(slotID: "S1", requestedModel: "cx/gpt-6-luna(max)", reportedModel: "gpt-6-luna(max)") },
                                                  resolve: { input, _ in resolution(input, catalog: try catalog()) },
                                                  order: { input, id in
                                                      try await interruption.check(id, failure: firstOrderFailure)
                                                      return try experience(input)
                                                  },
                                                  experience: { inputs, _ in try inputs.map { try experience($0) } },
                                                  hours: includesPinDetails ? Self.pinHours : nil)
            if let hoursPort {
                let client = PocketResearchClient(connection: connection)
                if hoursPort >= 18792 { services.hours = { await client.openingHours(placeID: $0) } }
                if hoursPort == 18793 { services.batchHours = { try await client.openingHours(placeIDs: $0) } }
            }
            return try PocketPlanningRepository(services: services, connection: connection, storageURL: storageURL,
                                                synthetic: true, jobClock: jobClock,
                                                requiresExternalAIConsent: externalAIDisclosure != nil,
                                                externalAIDisclosure: externalAIDisclosure)
        }

        private static func pinHours(_ placeID: String) async -> PlanningHoursLookup {
            guard placeID == "I123A" else { return .init(status: "unavailable") }
            let weekly = (1 ... 7).map { ["weekday": $0, "intervals": [["startSeconds": 25200, "endSeconds": 64800]]] }
            let payload: [String: Any] = ["status": "available",
                                          "hours": ["placeId": placeID, "timezone": "Asia/Jakarta", "weekly": weekly],
                                          "entryRule": ["kind": "walk_in_with_onsite_registration",
                                                        "sourceURL": "https://fixture.invalid/access"]]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let details = try? JSONDecoder().decode(PlanningHoursLookup.self, from: data) else {
                return .init(status: "temporary_error")
            }
            return details
        }

        public static func experience(_ input: PlanningInput) throws -> PlanningExperiencePlan {
            let main = input.enginePreferences?.mainSpotID
            let stops: [[String: Any]] = input.places.map { place in
                let unknown = place.name.contains("Unknown")
                return ["placeID": place.id.uuidString,
                        "activity": ["suggestion": "Synthetic suggested activity", "basis": "unknown"],
                        "role": place.id == main ? "main" : "supporting",
                        "duration": unknown ? NSNull() : ["minMinutes": 30, "maxMinutes": 60, "rationale": "Synthetic experience estimate", "basis": "experience_estimate"] as Any,
                        "durationUnknownReason": unknown ? "Synthetic unknown activity" : NSNull(),
                        "preferredDayPart": "flexible", "reason": "Synthetic ordering explanation",
                        "weather": ["status": "unavailable", "sourceRefs": [], "advice": "Synthetic fixture has no forecast"],
                        "light": ["windowRef": NSNull(), "priority": "unknown", "advice": "Synthetic fixture has no light context"],
                        "uncertainties": ["Synthetic demonstration, not verified venue facts"]]
            }
            let object: [String: Any] = ["status": "proposed", "orderedIDs": input.places.map { $0.id.uuidString },
                                         "tripRationale": "Synthetic experience order; no arrival times or operational hours were invented.",
                                         "stops": stops, "alternativeOrder": NSNull(), "tradeoffs": [], "uncertainties": ["Synthetic fixture only"],
                                         "generatedAt": ISO8601DateFormatter().string(from: .now), "candidateDate": TripClock.day(input.startsAt), "timeZone": input.timeZone,
                                         "requestedModel": "cx/gpt-6-luna(max)", "reportedModel": "gpt-6-luna(max)",
                                         "orderingMethod": input.enginePreferences?.orderingMethod?.rawValue ?? "luna",
                                         "weatherSources": [], "solarWindows": [], "contextWarnings": []]
            return try PocketOrderCodec.decoder().decode(PlanningExperiencePlan.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }
#endif
