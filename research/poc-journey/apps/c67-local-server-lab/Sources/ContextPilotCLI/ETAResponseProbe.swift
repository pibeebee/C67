import Foundation
import PlaceContextEngine
import PlannerEngine

/// Reissues a small number of exact recorded ETA requests and stores HTTP and
/// schema diagnostics. Provider response bodies and headers stay in memory.
@MainActor enum ETAResponseProbe {
    struct Observation: Codable {
        let from: String
        let to: String
        let departure: Date
        let previouslyAvailable: Bool
        let httpStatus: Int?
        let networkErrorCode: Int?
        let responseKeys: [String]
        let firstETAKeys: [String]
        let unavailableReason: String?
        let seconds: Double?
    }

    private final class ProbeTransport: LabHTTPTransport {
        private let session = LabURLSession()
        var etaResponse: LabHTTPResponse?
        var networkErrorCode: Int?

        func send(_ request: URLRequest) async throws -> LabHTTPResponse {
            let isETA = request.url?.lastPathComponent == "etas"
            do {
                let response = try await session.send(request)
                if isETA { etaResponse = response }
                return response
            } catch {
                if isETA, let error = error as? URLError { networkErrorCode = error.code.rawValue }
                throw error
            }
        }
    }

    static func run(trace: URL, output: URL) async throws {
        let recorded = try ContextJSON.decoder().decode([LabETAValue].self, from: Data(contentsOf: trace))
        let failures = recorded.filter { $0.seconds == nil }.prefix(5)
        let control = recorded.first { $0.seconds != nil }
        let selected = Array(failures) + [control].compactMap { $0 }
        let transport = ProbeTransport()
        let budget = LabProviderBudget(callLimit: 8, cellLimit: 6)
        let apple = LabAppleREST(config: try .init(), transport: transport, budget: budget)
        let provider = LabRESTETA(apple: apple)
        var observations: [Observation] = []
        for prior in selected {
            transport.etaResponse = nil
            transport.networkErrorCode = nil
            let query = prior.query
            let value = try await provider.values([query]).first
            let response = transport.etaResponse
            let envelope = response.flatMap { try? JSONSerialization.jsonObject(with: $0.data) as? [String: Any] }
            let item = (envelope?["etas"] as? [[String: Any]])?.first
            var reason = value?.seconds == nil ? value?.note : nil
            if let response, response.status == 200, reason != nil {
                do { _ = try LabRESTETA.parse(response.data, queries: [query]) }
                catch DecodingError.keyNotFound(let key, let context) {
                    reason = "Missing field: " + (context.codingPath.map(\.stringValue) + [key.stringValue]).joined(separator: ".")
                }
                catch is DecodingError { reason = "ETA response failed schema decoding" }
            }
            observations.append(Observation(from: query.fromID, to: query.toID, departure: query.departure,
                                            previouslyAvailable: prior.seconds != nil, httpStatus: response?.status,
                                            networkErrorCode: transport.networkErrorCode, responseKeys: envelope?.keys.sorted() ?? [],
                                            firstETAKeys: item?.keys.sorted() ?? [], unavailableReason: reason, seconds: value?.seconds))
            try ContextJSON.encoder().encode(observations).write(to: output, options: .atomic)
        }
    }
}
