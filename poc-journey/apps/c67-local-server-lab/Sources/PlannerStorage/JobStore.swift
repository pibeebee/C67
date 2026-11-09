import Foundation
import PlannerContracts
import CSQLite

/// One main-actor connection, short atomic transactions, parameterized SQL, bounded payloads.
@MainActor public final class JobStore {
    private let db: OpaquePointer
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public init(path: String) throws {
        var connection: OpaquePointer?
        guard sqlite3_open(path, &connection) == SQLITE_OK, let connection else {
            if let connection { sqlite3_close(connection) }; throw LabFailure.unavailable("SQLite open failed")
        }
        db = connection
        try execute("PRAGMA journal_mode=WAL")
        try execute("CREATE TABLE IF NOT EXISTS jobs(id TEXT PRIMARY KEY, client TEXT NOT NULL, operation TEXT NOT NULL, payload TEXT NOT NULL, UNIQUE(client,operation))")
        try execute("CREATE TABLE IF NOT EXISTS accepted(client TEXT PRIMARY KEY, payload TEXT NOT NULL)")
        for var job in try all() where !job.state.terminal {
            job.state = .failed; job.error = "interrupted_by_restart"; job.completedAt = .now; try save(job)
        }
    }
    // The connection has process lifetime. Close explicitly after the worker has stopped.
    public func close() { sqlite3_close(db) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw LabFailure.unavailable("SQLite statement failed") }
    }
    private func statement(_ sql: String, _ values: [String]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw LabFailure.unavailable("SQLite prepare failed") }
        for (i, value) in values.enumerated() { sqlite3_bind_text(stmt, Int32(i + 1), value, -1, transient) }
        return stmt
    }
    private func rows<T: Decodable>(_ sql: String, _ values: [String] = [], as: T.Type) throws -> [T] {
        let stmt = try statement(sql, values); defer { sqlite3_finalize(stmt) }
        var result: [T] = []; var code = sqlite3_step(stmt)
        while code == SQLITE_ROW {
            guard let text = sqlite3_column_text(stmt, 0) else { throw LabFailure.unavailable("SQLite corrupt row") }
            result.append(try LabJSON.decoder().decode(T.self, from: Data(String(cString: text).utf8)))
            code = sqlite3_step(stmt)
        }
        guard code == SQLITE_DONE else { throw LabFailure.unavailable("SQLite read failed") }
        return result
    }
    public func all() throws -> [LabJob] { try rows("SELECT payload FROM jobs ORDER BY rowid", as: LabJob.self) }
    public func get(_ id: UUID) throws -> LabJob? { try rows("SELECT payload FROM jobs WHERE id=?", [id.uuidString], as: LabJob.self).first }
    public func save(_ job: LabJob) throws {
        let data = try LabJSON.encoder().encode(job)
        guard data.count <= 5 * 1024 * 1024 else { throw LabFailure.invalid("Result exceeds 5 MiB") }
        let stmt = try statement("INSERT INTO jobs(id,client,operation,payload) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload",
                                 [job.id.uuidString, job.input.clientID, job.input.operationID, String(decoding: data, as: UTF8.self)])
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw LabFailure.unavailable("SQLite write failed") }
    }
    public func submit(_ input: JobInput, snapshot: String, capacity: Int = 3) throws -> LabJob {
        try input.validate(snapshot: snapshot)
        let previous = try rows("SELECT payload FROM jobs WHERE client=? AND operation=?", [input.clientID, input.operationID], as: LabJob.self).first
        if let previous {
            guard previous.inputHash == (try LabJSON.hash(input)) else { throw LabFailure.conflict("Idempotency key reused for different input") }
            return previous
        }
        guard try all().filter({ !$0.state.terminal }).count < capacity else { throw LabFailure.capacity }
        let current = try accepted(input.clientID)
        guard input.baseRevision == (current?.revision ?? 0), input.baseAcceptedID == current?.plan.id else {
            throw LabFailure.conflict("Accepted baseline revision changed")
        }
        let job = try LabJob(input: input); try save(job); return job
    }
    public func accepted(_ client: String) throws -> AcceptedState? {
        try rows("SELECT payload FROM accepted WHERE client=?", [client], as: AcceptedState.self).first
    }
    public func apply(_ jobID: UUID, input: ApplyInput, now: Date) throws -> AcceptedState {
        try execute("BEGIN IMMEDIATE")
        do {
            guard let job = try get(jobID), job.state == .completed, job.result?.outcome == "ready",
                  let plan = job.result?.plan, input.clientID == job.input.clientID,
                  input.requestHash == (try LabJSON.hash(plan.request)), input.baseRevision == job.input.baseRevision else {
                throw LabFailure.conflict("Proposal/request/client mismatch")
            }
            let previous = try accepted(input.clientID)
            if let previous, previous.plan.id == plan.id {
                try execute("COMMIT"); return previous
            }
            guard (previous?.revision ?? 0) == input.baseRevision,
                  previous?.plan.id == plan.baseAcceptedID else { throw LabFailure.conflict("Stale baseline") }
            var session = IntegrationSession(); session.accepted = previous?.plan; session.proposal = plan
            try session.apply(now: now)
            let accepted = AcceptedState(revision: input.baseRevision + 1, plan: session.accepted!)
            let data = try LabJSON.encoder().encode(accepted)
            let stmt = try statement("INSERT INTO accepted(client,payload) VALUES(?,?) ON CONFLICT(client) DO UPDATE SET payload=excluded.payload",
                                     [input.clientID, String(decoding: data, as: UTF8.self)])
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw LabFailure.unavailable("SQLite apply failed") }
            try execute("COMMIT"); return accepted
        } catch { try? execute("ROLLBACK"); throw error }
    }
}
