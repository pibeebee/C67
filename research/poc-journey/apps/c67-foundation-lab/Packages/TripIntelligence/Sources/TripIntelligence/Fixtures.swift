import Foundation

public enum LabFixtures {
    public static func jakarta() throws -> TripContextV1 {
        let url = Bundle.module.url(forResource: "jakarta-report", withExtension: "json")!
        return try TripImporter.load(
            Data(contentsOf: url),
            source:
            "Public MapKit/Open-Meteo production-source probe, 4 November 2026; service date 5 November 2026; scripted visits"
        )
    }
    public static func synthetic() throws -> TripContextV1 {
        var c = try jakarta()
        c.id = "synthetic-jakarta-v1"
        c.revision = 1
        c.synthetic = true
        c.source =
            "Synthetic experiment fixture; all venue names, hours, travel and experience windows are illustrative"
        c.generatedAt = "2026-11-04T08:00:00+07:00"
        c.departure = "2026-11-05T08:00:00+07:00"
        c.deadline = "2026-11-05T18:00:00+07:00"
        c.origin = PlaceV1(id: "O", name: "Example start", latitude: -6.2, longitude: 106.82)
        c.endpoint = c.origin
        c.stops = [
            VisitV1(
                place: .init(
                    id: "A", name: "Example Museum (fictional)", latitude: -6.1754, longitude: 106.8272,
                    category: "museum"), dwellMinutes: 60, exposure: "indoor"),
            VisitV1(
                place: .init(
                    id: "B", name: "Example Reading Cafe (fictional)", latitude: -6.25, longitude: 106.81,
                    category: "cafe"), dwellMinutes: 45, exposure: "indoor"),
            VisitV1(
                place: .init(
                    id: "C", name: "Example Garden (fictional)", latitude: -6.22, longitude: 106.84,
                    category: "park"), dwellMinutes: 30, exposure: "outdoor"),
        ]
        c.legs = [
            .init(
                id: "OA", fromID: "O", toID: "A", departure: c.departure,
                arrival: "2026-11-05T08:20:00+07:00", visit: "2026-11-05T09:00:00+07:00",
                leave: "2026-11-05T10:00:00+07:00", travelMinutes: 20),
            .init(
                id: "AB", fromID: "A", toID: "B", departure: "2026-11-05T10:00:00+07:00",
                arrival: "2026-11-05T10:20:00+07:00", visit: "2026-11-05T10:20:00+07:00",
                leave: "2026-11-05T11:05:00+07:00", travelMinutes: 20),
            .init(
                id: "BC", fromID: "B", toID: "C", departure: "2026-11-05T11:05:00+07:00",
                arrival: "2026-11-05T11:25:00+07:00", visit: "2026-11-05T11:25:00+07:00",
                leave: "2026-11-05T11:55:00+07:00", travelMinutes: 20),
            .init(
                id: "CO", fromID: "C", toID: "O", departure: "2026-11-05T11:55:00+07:00",
                arrival: "2026-11-05T12:15:00+07:00", travelMinutes: 20, isReturn: true),
        ]
        c.finish = "2026-11-05T12:15:00+07:00"
        c.elapsedMinutes = 255
        c.complete = true
        c.conflicts = []
        c.uncertainties = [
            "Prices and crowd levels unknown",
            "Garden afternoon preference has not been inserted into a new timetable",
        ]
        c.evidence = c.stops.map {
            .init(
                id: "place-\($0.id)", subjectID: $0.id, key: "identity", value: $0.place.name,
                source: c.source, observedAt: c.generatedAt, synthetic: true)
        }
        c.evidence += [
            .init(
                id: "hours-A-open", subjectID: "A", key: "opensMinute", value: "09:00", source: c.source,
                observedAt: c.generatedAt, synthetic: true),
            .init(
                id: "hours-A-close", subjectID: "A", key: "closesMinute", value: "16:00", source: c.source,
                observedAt: c.generatedAt, synthetic: true),
            .init(
                id: "experience-C", subjectID: "C", key: "experienceWindow",
                value: "afternoon is a soft photography preference; no measured golden hour or weather",
                source: c.source, observedAt: c.generatedAt, synthetic: true),
            .init(
                id: "reading-B", subjectID: "B", key: "reading",
                value: "Reading seating is provided in this synthetic fixture; noise and price unknown",
                source: c.source, observedAt: c.generatedAt, synthetic: true),
            .init(
                id: "baseline", subjectID: "trip", key: "schedule",
                value:
                "O → A → B → C → O; museum waits 40 minutes to open at 09:00; imported finish 12:15, deadline 18:00; feasible against supplied bounds; garden afternoon preference is not fulfilled",
                source: c.source, observedAt: c.generatedAt, synthetic: true),
        ]
        try c.validate()
        return c
    }
    public static func candidates() -> [CandidateV1] {
        let source = "Synthetic candidate fixture, not MapKit results"
        return [
            CandidateV1(
                place: .init(
                    id: "P1", name: "Example Book Cafe (fictional)", latitude: -6.24, longitude: 106.81,
                    category: "cafe"),
                evidence: [
                    .init(
                        id: "P1-info", subjectID: "P1", key: "attributes",
                        value: "Cafe with reading seating; price, quietness, accessibility and hours unknown",
                        source: source, observedAt: "2026-11-04T08:00:00+07:00", synthetic: true)
                ]),
            CandidateV1(
                place: .init(
                    id: "P2", name: "Example Gallery (fictional)", latitude: -6.19, longitude: 106.83,
                    category: "museum"),
                evidence: [
                    .init(
                        id: "P2-info", subjectID: "P2", key: "attributes",
                        value: "Indoor art gallery; price, accessibility and hours unknown", source: source,
                        observedAt: "2026-11-04T08:00:00+07:00", synthetic: true)
                ]),
        ]
    }
}
public struct FixturePlaceSearch: PlaceSearching {
    public var values: [CandidateV1]
    public init(values: [CandidateV1] = LabFixtures.candidates()) { self.values = values }
    public func search(profile: PreferenceExtraction, context: TripContextV1) async throws
        -> SearchBatch
    {
        try Task.checkCancellation()
        return .init(
            candidates: CandidateFilter.queries(profile).isEmpty ? [] : values,
            queries: CandidateFilter.queries(profile), source: "Synthetic search fixture; not live MapKit"
        )
    }
}
public struct FixtureModelEngine: ModelGenerating {
    public init() {}
    public func runtime() async -> ModelRuntime {
        ModelRuntime(
            available: false, englishSupported: true, indonesianSupported: false,
            availability: "Fixture mode; live model disabled", contextSize: 0,
            model: "Deterministic fixture mode (no inference)")
    }
    public func generate(_ request: GenerationRequest) async throws -> RawGeneration {
        throw LabError.unavailable("Fixture mode")
    }
}
