import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import C67Domain

private final class PlanningRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// The client sends traveller JWTs only. Model, Apple and worker credentials stay on the server.
public actor HTTPPlanningRepository: PlanningRepository {
    private let baseURL: URL
    private let authentication: SupabaseAuthentication
    private let session: URLSession
    private let onUnauthorized: @Sendable (String) async throws -> Void
    private let defaults: UserDefaults

    public init(baseURL: URL, authentication: SupabaseAuthentication,
                onUnauthorized: @escaping @Sendable (String) async throws -> Void = { _ in }) throws {
        guard let host = baseURL.host, baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil, baseURL.path.isEmpty || baseURL.path == "/",
              baseURL.scheme == "https" || (baseURL.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            throw PlanningError.configurationRequired
        }
        self.baseURL = baseURL; self.authentication = authentication; self.onUnauthorized = onUnauthorized
        session = URLSession(configuration: .ephemeral, delegate: PlanningRedirectPolicy(), delegateQueue: nil)
        defaults = .standard
    }

    private struct Authorization {
        let ticket: SupabaseAuthentication.Authorization
        let owner: UUID
    }
    private func authorize() async throws -> Authorization {
        guard let ticket = try await authentication.authorization(),
              let account = try await authentication.currentAccount() else { throw PlanningError.authenticationRequired }
        guard await authentication.isCurrent(ticket) else { throw CancellationError() }
        return .init(ticket: ticket, owner: account.id)
    }

    private func pendingKey(_ account: UUID) -> String { "C67.Planning.Pending.\(baseURL.absoluteString).\(account.uuidString)" }

    private func send<T: Decodable>(_ path: String, method: String, body: Data? = nil, authorization: Authorization) async throws -> T {
        guard await authentication.isCurrent(authorization.ticket) else { throw CancellationError() }
        let token = authorization.ticket.token
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 35
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, raw) = try await session.data(for: request)
        try Task.checkCancellation()
        guard await authentication.isCurrent(authorization.ticket) else { throw CancellationError() }
        guard let response = raw as? HTTPURLResponse, data.count <= 1024 * 1024,
              response.url?.scheme == baseURL.scheme, response.url?.host == baseURL.host,
              response.url?.port == baseURL.port else { throw PlanningError.invalidResponse }
        guard (200 ... 299).contains(response.statusCode) else {
            if response.statusCode == 401 { try await onUnauthorized(token); throw PlanningError.authenticationRequired }
            let error = try? JSONDecoder().decode(PlanningErrorEnvelope.self, from: data)
            switch response.statusCode {
            case 404: throw PlanningError.notFound
            case 409: throw PlanningError.revisionConflict
            case 429: throw PlanningError.rateLimited
            case 400: throw PlanningError.invalidInput
            default: throw error.map { PlanningError.failed($0.error.code) } ?? .unavailable
            }
        }
        do { return try SupabaseConnection.decoder().decode(T.self, from: data) }
        catch { throw PlanningError.invalidResponse }
    }

    public func requestPlan(_ request: PlanningRequest) async throws -> PlanningJob {
        try await submit(request, authorization: authorize())
    }
    private func submit(_ request: PlanningRequest, authorization: Authorization) async throws -> PlanningJob {
        try request.input.validate()
        let data = try SupabaseConnection.encoder().encode(PlanningRequestDTO(request))
        // Persist the exact command before sending. An uncertain HTTP response can be retried safely.
        defaults.set(data, forKey: pendingKey(authorization.owner))
        let value: PlanningJobDTO = try await send("v1/planning/jobs", method: "POST", body: data, authorization: authorization)
        return value.domain
    }
    public func planningJob(id: UUID) async throws -> PlanningJob {
        let value: PlanningJobDTO = try await send("v1/planning/jobs/\(id.uuidString)", method: "GET", authorization: authorize())
        return value.domain
    }
    public func resumePlanning() async throws -> PlanningJob? {
        let authorization = try await authorize(); let owner = authorization.owner
        guard let data = defaults.data(forKey: pendingKey(owner)) else { return nil }
        guard let command = try? SupabaseConnection.decoder().decode(PlanningRequestDTO.self, from: data) else {
            defaults.removeObject(forKey: pendingKey(owner)); return nil
        }
        let job = try await submit(command.domain, authorization: authorization)
        let value: PlanningJobDTO = try await send("v1/planning/jobs/\(job.id.uuidString)", method: "GET", authorization: authorization)
        return value.domain
    }
    public func applyProposal(jobID: UUID, expectedRevision: Int?, requestID: UUID) async throws -> PersonalPlanningTrip {
        let authorization = try await authorize(); let owner = authorization.owner
        let body = try SupabaseConnection.encoder().encode(ApplyPlanningBody(request_id: requestID, expected_revision: expectedRevision))
        let value: PersonalPlanningTripDTO = try await send("v1/planning/proposals/\(jobID.uuidString)/apply", method: "POST", body: body, authorization: authorization)
        defaults.removeObject(forKey: pendingKey(owner))
        return value.domain
    }
    public func personalTrips() async throws -> [PersonalPlanningTrip] {
        let values: [PersonalPlanningTripDTO] = try await send("v1/planning/trips", method: "GET", authorization: authorize())
        return values.map(\.domain)
    }
    public func recordEvent(tripID: UUID, event: PlanningEvent) async throws -> PersonalPlanningTrip {
        let body = try SupabaseConnection.encoder().encode(PlanningEventDTO(event))
        let value: PersonalPlanningTripDTO = try await send("v1/planning/trips/\(tripID.uuidString)/events", method: "POST", body: body, authorization: authorize())
        return value.domain
    }
}

private struct ApplyPlanningBody: Encodable {
    let request_id: UUID
    let expected_revision: Int?
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(request_id, forKey: .request_id)
        if let expected_revision { try values.encode(expected_revision, forKey: .expected_revision) }
        else { try values.encodeNil(forKey: .expected_revision) }
    }
    private enum CodingKeys: String, CodingKey { case request_id, expected_revision }
}
private struct PlanningErrorEnvelope: Decodable {
    struct Body: Decodable { let code: String }
    let error: Body
}

public actor UnconfiguredPlanningRepository: PlanningRepository {
    public init() {}
    public func requestPlan(_ request: PlanningRequest) throws -> PlanningJob { throw PlanningError.configurationRequired }
    public func planningJob(id: UUID) throws -> PlanningJob { throw PlanningError.configurationRequired }
    public func resumePlanning() throws -> PlanningJob? { throw PlanningError.configurationRequired }
    public func applyProposal(jobID: UUID, expectedRevision: Int?, requestID: UUID) throws -> PersonalPlanningTrip { throw PlanningError.configurationRequired }
    public func personalTrips() throws -> [PersonalPlanningTrip] { throw PlanningError.configurationRequired }
    public func recordEvent(tripID: UUID, event: PlanningEvent) throws -> PersonalPlanningTrip { throw PlanningError.configurationRequired }
}
