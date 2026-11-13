#if DEBUG
    import Foundation
    import C67Domain
    import PocketEngine

    /// Explicit synthetic transport around the real recommender and solver, only for local integration tests.
    public enum PocketIntegrationFixture {
        private actor Connection: PocketConnectionProviding {
            func credentials() -> PocketCredentials { .init(serverURL: "https://fixture.invalid", token: "synthetic-fixture-token") }
            func update(serverURL: String, token: String) {}
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
        public static func repository(storageURL: URL? = nil) throws -> PocketPlanningRepository {
            let services = PocketPlanningServices(catalog: { try catalog() }, discover: { _, _ in [] },
                                                  travel: { _, _, _, _ in .init(seconds: 120, meters: 500) },
                                                  weather: { _, _, _ in .init(maxRainChance: nil, summary: "Synthetic test; no live weather") },
                                                  advise: { _ in .init(slotID: "S1", requestedModel: "cx/gpt-6-luna(max)", reportedModel: "gpt-6-luna(max)") })
            return try PocketPlanningRepository(services: services, connection: Connection(), storageURL: storageURL, synthetic: true)
        }
    }
#endif
