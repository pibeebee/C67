import Foundation
import FoundationModels

// The evaluator oracle is deliberately not read by this executable.
@Generable(representNilExplicitlyInGeneratedContent: true)
struct Action: Codable {
    @Guide(.anyOf(["extend_current_visit", "set_leave_time", "skip_stop", "set_deadline", "mark_arrived", "begin_visit", "depart_visit", "request_replan", "apply_proposal", "reject_proposal"]))
    var type: String
    @Guide(description: "Existing explicitly requested target ID; null when not applicable.") var targetID: String?
    @Guide(description: "Explicit requested duration in minutes; null when not applicable.") var minutes: Int?
    @Guide(description: "Explicitly requested absolute local time; otherwise null. Do not calculate new times.") var localTime: String?
    @Guide(description: "An existing valid proposal ID for proposal actions only; otherwise null. Never invent an ID.") var proposalID: String?
    @Guide(description: "Explicit search query for a supported action when relevant; otherwise null.") var query: String?
}

@Generable
struct Preference: Codable {
    @Guide(.anyOf(["coffee", "reading_friendly", "quiet", "indoor", "outdoor", "golden_hour", "popular", "walking_effort"]))
    var key: String
    @Guide(.anyOf(["prefer", "avoid", "not_important"]))
    var value: String
    @Guide(.anyOf(["soft", "hard"]))
    var strength: String
}

@Generable(representNilExplicitlyInGeneratedContent: true)
struct Suggestion: Codable {
    @Guide(.anyOf(["propose", "clarify", "explain", "recommend", "cannot_complete"]))
    var status: String
    var basedOnRevision: Int
    @Guide(description: "Exactly the explicitly requested supported changes, no inferred changes; empty for explanations and recommendations.", .maximumCount(3)) var actions: [Action]
    @Guide(description: "Explicit preference changes only; otherwise empty.") var preferences: [Preference]
    @Guide(description: "Only recommended candidate IDs from supplied candidate data; otherwise empty.") var candidateIDs: [String]
    @Guide(description: "Only actual supporting evidence IDs from context or tool results; otherwise empty.") var evidenceIDs: [String]
    var message: String
    @Guide(description: "One question only for an unresolved ambiguity; otherwise null.") var question: String?
    var requiresConfirmation: Bool
}

enum HarnessError: Error { case invalidRequest, fixtureMissing, invalidArguments, toolBudget, toolStopped }

// The SDK's default @Generable Optional schema allows omission rather than
// required JSON nulls. Use explicit required nullable unions for the package contract.
func experimentSchema() throws -> GenerationSchema {
    let nullableString = DynamicGenerationSchema(name: "NullableString", anyOf: [.init(type: String.self), .null])
    let nullableInt = DynamicGenerationSchema(name: "NullableInteger", anyOf: [.init(type: Int.self), .null])
    let actionType = DynamicGenerationSchema(name: "ActionType", anyOf: ["extend_current_visit", "set_leave_time", "skip_stop", "set_deadline", "mark_arrived", "begin_visit", "depart_visit", "request_replan", "apply_proposal", "reject_proposal"])
    let action = DynamicGenerationSchema(name: "Action", properties: [
        .init(name: "type", schema: actionType),
        .init(name: "targetID", description: "Existing target ID, or null when not applicable.", schema: nullableString),
        .init(name: "minutes", description: "Explicit requested minutes, or null when not applicable.", schema: nullableInt),
        .init(name: "localTime", description: "Explicitly requested absolute time, otherwise null; never calculate a time.", schema: nullableString),
        .init(name: "proposalID", description: "Existing valid proposal ID for a proposal action only; otherwise null.", schema: nullableString),
        .init(name: "query", description: "Explicit search query if applicable, otherwise null.", schema: nullableString),
    ])
    let preference = DynamicGenerationSchema(name: "Preference", properties: [
        .init(name: "key", schema: .init(name: "PreferenceKey", anyOf: ["coffee", "reading_friendly", "quiet", "indoor", "outdoor", "golden_hour", "popular", "walking_effort"])),
        .init(name: "value", schema: .init(name: "PreferenceValue", anyOf: ["prefer", "avoid", "not_important"])),
        .init(name: "strength", schema: .init(name: "PreferenceStrength", anyOf: ["soft", "hard"])),
    ])
    let root = DynamicGenerationSchema(name: "C67ModelSuggestion", properties: [
        .init(name: "status", schema: .init(name: "Status", anyOf: ["propose", "clarify", "explain", "recommend", "cannot_complete"])),
        .init(name: "basedOnRevision", schema: .init(type: Int.self)),
        .init(name: "actions", description: "Exactly the explicitly requested supported changes; otherwise empty.", schema: .init(arrayOf: action, maximumElements: 3)),
        .init(name: "preferences", description: "Explicit preference changes only; otherwise empty.", schema: .init(arrayOf: preference)),
        .init(name: "candidateIDs", description: "Only recommended candidate IDs from the supplied data; otherwise empty.", schema: .init(arrayOf: .init(type: String.self))),
        .init(name: "evidenceIDs", description: "Only supplied supporting evidence IDs; otherwise empty.", schema: .init(arrayOf: .init(type: String.self))),
        .init(name: "message", schema: .init(type: String.self)),
        .init(name: "question", description: "One question for an unresolved ambiguity, otherwise null.", schema: nullableString),
        .init(name: "requiresConfirmation", schema: .init(type: Bool.self)),
    ])
    return try GenerationSchema(root: root, dependencies: [])
}

actor FixtureLedger {
    private let fixtures: Data
    private let traceURL: URL
    private var calls = 0
    private var stopped = false

    init(fixtures: Data, traceURL: URL) {
        self.fixtures = fixtures
        self.traceURL = traceURL
    }

    private func log(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) + Data("\n".utf8)
        if !FileManager.default.fileExists(atPath: traceURL.path) {
            FileManager.default.createFile(atPath: traceURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: traceURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    func call(_ name: String, _ arguments: [String: String]) throws -> String {
        calls += 1
        var event: [String: Any] = ["tool": name, "arguments": arguments, "callNumber": calls]
        do {
            guard calls <= 2 else { throw HarnessError.toolBudget }
            guard !stopped else { throw HarnessError.toolStopped }
            guard let all = try JSONSerialization.jsonObject(with: fixtures) as? [String: Any],
                  let fixture = all[name] as? [String: Any], let result = fixture["result"] else {
                throw HarnessError.fixtureMissing
            }
            let valid: Bool
            switch name {
            case "readWeather":
                valid = arguments["stopID"] == "C" && arguments["at"] == "2026-11-05T09:30:00+07:00"
            case "readOpeningHours":
                valid = arguments["stopID"] == "C" && arguments["serviceDate"] == "2026-11-05"
            case "searchPlaces":
                let q = (arguments["query"] ?? "").lowercased()
                let coffee = ["kopi", "coffee", "cafe", "kafe"].contains { q.contains($0) }
                let reading = ["baca", "read", "buku", "book"].contains { q.contains($0) }
                valid = arguments["area"]?.lowercased() == "cipete" && coffee && reading
            default:
                valid = false
            }
            guard valid else { throw HarnessError.invalidArguments }
            let resultData = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            let resultString = String(decoding: resultData, as: UTF8.self)
            event["result"] = result
            if let object = result as? [String: Any], object["status"] as? String == "unavailable" { stopped = true }
            try log(event)
            return resultString
        } catch {
            stopped = true
            event["error"] = String(describing: error)
            try? log(event)
            throw error
        }
    }
}

struct WeatherTool: Tool {
    let name = "readWeather"
    let description = "Read the local frozen synthetic forecast for a stop and ISO-8601 timestamp; no network."
    let ledger: FixtureLedger
    @Generable struct Arguments { var stopID: String; var at: String }
    func call(arguments: Arguments) async throws -> String {
        try await ledger.call(name, ["stopID": arguments.stopID, "at": arguments.at])
    }
}

struct SearchTool: Tool {
    let name = "searchPlaces"
    let description = "Search the local synthetic catalogue by area and search keywords; no network."
    let ledger: FixtureLedger
    @Generable struct Arguments { var area: String; var query: String }
    func call(arguments: Arguments) async throws -> String {
        try await ledger.call(name, ["area": arguments.area, "query": arguments.query])
    }
}

struct HoursTool: Tool {
    let name = "readOpeningHours"
    let description = "Read local synthetic opening hours by stop ID and service date; may return unavailable."
    let ledger: FixtureLedger
    @Generable struct Arguments { var stopID: String; var serviceDate: String }
    func call(arguments: Arguments) async throws -> String {
        try await ledger.call(name, ["stopID": arguments.stopID, "serviceDate": arguments.serviceDate])
    }
}

func textSegment(_ s: String) -> Transcript.Segment { .text(.init(content: s)) }

