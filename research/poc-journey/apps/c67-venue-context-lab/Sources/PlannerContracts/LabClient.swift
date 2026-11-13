import Foundation

public struct LabClient: Sendable {
    public let baseURL: URL
    private let token: String
    private let session: URLSession
    public init(baseURL: URL, token: String) throws {
        guard ["http", "https"].contains(baseURL.scheme ?? ""), baseURL.host != nil,
              baseURL.user == nil, baseURL.password == nil, baseURL.query == nil, token.utf8.count >= 32 else {
            throw LabFailure.invalid("Invalid lab URL/token")
        }
        self.baseURL = baseURL; self.token = token
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 30
        config.urlCache = nil; session = URLSession(configuration: config)
    }
    public func call<T: Decodable>(_ path: String, method: String = "GET", data: Data? = nil,
                                   as: T.Type) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method; req.httpBody = data; req.timeoutInterval = 30
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if data != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let bytes: Data; let response: URLResponse
        do { (bytes, response) = try await session.data(for: req) }
        catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            let details = (error as NSError).userInfo["_NSURLErrorNWPathKey"].map { String(describing: $0) } ?? "unavailable"
            throw LabFailure.unavailable("LAN: \(error.localizedDescription); path=\(details)")
        }
        guard let http = response as? HTTPURLResponse else { throw LabFailure.unavailable("Invalid HTTP response") }
        guard (200 ..< 300).contains(http.statusCode) else { throw LabFailure.unavailable("Lab HTTP \(http.statusCode)") }
        guard bytes.count <= 5 * 1024 * 1024 else { throw LabFailure.invalid("Oversized lab response") }
        return try LabJSON.decoder().decode(T.self, from: bytes)
    }
    public func capabilities() async throws -> [String: String] { try await call("v1/lab/capabilities", as: [String: String].self) }
    public func submit(_ input: JobInput) async throws -> LabJob {
        try await call("v1/lab/jobs", method: "POST", data: LabJSON.encoder().encode(input), as: LabJob.self)
    }
    public func wait(_ job: LabJob, timeout: Double = 240,
                     progress: @escaping @Sendable (String) async -> Void = { _ in }) async throws -> LabOutcome {
        let start = ContinuousClock.now
        do {
            var current = job
            while !current.state.terminal {
                try Task.checkCancellation()
                if start.duration(to: .now) > .seconds(timeout) { throw LabFailure.unavailable("client_observation_limit_censored") }
                await progress(current.progress)
                try await Task.sleep(for: .milliseconds(100))
                current = try await call("v1/lab/jobs/\(job.id)", as: LabJob.self)
            }
            guard current.state == .completed else { throw LabFailure.unavailable("Job \(current.state.rawValue): \(current.error ?? "")") }
            return try await call("v1/lab/jobs/\(job.id)/result", as: LabOutcome.self)
        } catch {
            await Task.detached { [self] in
                _ = try? await call("v1/lab/jobs/\(job.id)/cancel", method: "POST", as: LabJob.self)
            }.value
            throw error
        }
    }
    public func apply(_ plan: IntegratedPlan, clientID: String, baseRevision: Int) async throws -> AcceptedState {
        let input = ApplyInput(clientID: clientID, baseRevision: baseRevision, requestHash: try LabJSON.hash(plan.request))
        return try await call("v1/lab/proposals/\(plan.id)/apply", method: "POST",
                              data: LabJSON.encoder().encode(input), as: AcceptedState.self)
    }
}
public struct LabObservation: Codable, Sendable {
    public var caseID: String; public var family: String; public var variant: String
    public var condition: String; public var clientSeconds: Double; public var outcome: LabOutcome?
    public var error: String?; public var thermal: String; public var baselineID: UUID?
    public init(caseID: String, family: String, variant: String, condition: String = "fresh",
                clientSeconds: Double, outcome: LabOutcome? = nil, error: String? = nil,
                thermal: String = "unmeasured", baselineID: UUID? = nil) {
        self.caseID = caseID; self.family = family; self.variant = variant; self.condition = condition
        self.clientSeconds = clientSeconds; self.outcome = outcome; self.error = error
        self.thermal = thermal; self.baselineID = baselineID
    }
}
