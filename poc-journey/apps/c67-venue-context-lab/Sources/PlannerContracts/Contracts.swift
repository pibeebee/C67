import CryptoKit
import Foundation
@_exported import PlannerEngine

public enum LabJSON {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return e
    }
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d
    }
    public static func hash<T: Encodable>(_ value: T) throws -> String {
        func normalized(_ value: Any, key: String = "") -> Any {
            if let dict = value as? [String: Any] { return dict.mapValues { $0 }.reduce(into: [String: Any]()) { $0[$1.key] = normalized($1.value, key: $1.key) } }
            if let strings = value as? [String], ["must", "prefer", "avoid", "excludedIDs"].contains(key) { return strings.sorted() }
            if let array = value as? [Any] { return array.map { normalized($0) } }
            return value
        }
        let object = try JSONSerialization.jsonObject(with: encoder().encode(value))
        return try digest(JSONSerialization.data(withJSONObject: normalized(object), options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]))
    }
    public static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
public struct JobInput: Codable, Sendable {
    public var schemaVersion = 1
    public var clientID: String
    public var operationID: String
    public var runID: String
    public var variant: LabVariant
    public var snapshotHash: String
    public var request: TripRequest
    public var baseRevision: Int
    public var baseAcceptedID: UUID?
    public init(clientID: String = "lab-client", operationID: String = UUID().uuidString,
                runID: String, variant: LabVariant, snapshotHash: String, request: TripRequest,
                baseRevision: Int = 0, baseAcceptedID: UUID? = nil) {
        self.clientID = clientID; self.operationID = operationID; self.runID = runID
        self.variant = variant; self.snapshotHash = snapshotHash; self.request = request
        self.baseRevision = baseRevision; self.baseAcceptedID = baseAcceptedID
    }
    public func validate(snapshot: String) throws {
        guard schemaVersion == 1, snapshotHash == snapshot, (0 ... Int.max).contains(baseRevision),
              [clientID, operationID, runID].allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 && !$0.contains("\0") })
        else { throw LabFailure.invalid("Unsupported schema/snapshot/identity") }
    }
}
public enum JobState: String, Codable, Sendable {
    case queued, running, completed, failed, cancelled, timedOut = "timed_out"
    public var terminal: Bool { self != .queued && self != .running }
}
public struct LabJob: Codable, Sendable {
    public var id: UUID
    public var inputHash: String
    public var input: JobInput
    public var state: JobState
    public var progress: String
    public var createdAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    public var result: LabOutcome?
    public var error: String?
    public init(input: JobInput) throws {
        id = UUID(); inputHash = try LabJSON.hash(input); self.input = input
        state = .queued; progress = "queued"; createdAt = .now
    }
}
public struct ApplyInput: Codable, Sendable {
    public var clientID: String; public var baseRevision: Int; public var requestHash: String
    public init(clientID: String, baseRevision: Int, requestHash: String) {
        self.clientID = clientID; self.baseRevision = baseRevision; self.requestHash = requestHash
    }
}
public struct AcceptedState: Codable, Sendable {
    public var revision: Int; public var plan: IntegratedPlan
    public init(revision: Int, plan: IntegratedPlan) { self.revision = revision; self.plan = plan }
}
public enum LabFailure: Error, LocalizedError, Sendable {
    case invalid(String), conflict(String), unavailable(String), capacity
    public var errorDescription: String? {
        switch self {
        case .invalid(let s), .conflict(let s), .unavailable(let s): s
        case .capacity: "Outstanding job capacity reached"
        }
    }
}
public enum LabSnapshot {
    public static func hash() throws -> String {
        // The same resource bytes are bundled with the adapted engine and included in its source manifest.
        let catalog = try IntegrationCatalog.load()
        return try LabJSON.hash(Snapshot(quality: try LabJSON.encoder().encode(catalog.quality),
                                         timing: try LabJSON.encoder().encode(catalog.timing)))
    }
    private struct Snapshot: Encodable { var quality: Data; var timing: Data }
}
public struct LabCase: Codable, Sendable {
    public var id: String; public var family: String; public var expected: String
    public var request: TripRequest; public var revision = false
}
public enum LabMatrix {
    public static let now = TripClock.date("2026-11-06T00:00:00Z")
    public static func cases(now: Date = now) -> [LabCase] {
        let cal = TripClock.calendar
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        func request(_ ids: [String], hour: Int = 7) -> TripRequest {
            var r = TripRequest(now: now)
            r.id = UUID(uuidString: "00000000-0000-0000-0000-000000000067")!
            r.departure = cal.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow)!
            r.deadline = cal.date(bySettingHour: 19, minute: 0, second: 0, of: tomorrow)!
            r.requiredCandidateIDs = ids; r.desiredCount = ids.count
            r.profile.prefer = [.reading, .culture]; r.useEmbedding = true; return r
        }
        let defs: [(String, [String], Int)] = [("N1", ["cikini"], 9),
                                               ("N3", ["cikini", "bdt-rbbj", "erasmus"], 9),
                                               ("N4", ["cikini", "bdt-rbbj", "erasmus", "ragunan"], 7),
                                               ("N5", ["cikini", "bdt-rbbj", "erasmus", "ragunan", "gbk"], 7)]
        var result: [LabCase] = []
        for (name, ids, hour) in defs {
            for n in 1 ... 3 { result.append(.init(id: "\(name)-R\(n)", family: name,
                                                   expected: "ready", request: request(ids, hour: hour))) }
        }
        let five = defs.last!.1
        result.append(.init(id: "REV5", family: "REV5", expected: "ready", request: request(five), revision: true))
        var mixed = request(five)
        mixed.durationByVenue = ["cikini": 45, "bdt": 90, "erasmus": 45, "ragunan": 60, "gbk": 30]
        result.append(.init(id: "MIX5", family: "MIX5", expected: "ready", request: mixed))
        var tight = request(five); tight.defaultDuration = 90
        tight.deadline = cal.date(bySettingHour: 13, minute: 0, second: 0, of: tomorrow)!
        result.append(.init(id: "TIGHT5", family: "TIGHT5", expected: "rejected", request: tight))
        var six = request([]); six.desiredCount = 6
        result.append(.init(id: "SIX", family: "SIX", expected: "needs_places", request: six))
        var unknown = request(["cikini"], hour: 9); unknown.profile.must = [.wifi]
        result.append(.init(id: "UNKNOWN", family: "UNKNOWN", expected: "needs_places", request: unknown))
        return result
    }
}
