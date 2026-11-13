import Foundation
import Vapor
import PlannerStorage
import PlannerContracts
import PlaceContextEngine
import DynamicTripContracts
import DynamicTripEngine
import RecommendationEngine
import RecommendationContracts
import PlannerEngine

@main struct ServerMain {
    static func main() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let token = env["LAB_ACCESS_TOKEN"], token.utf8.count >= 32 else {
            throw LabFailure.invalid("Set LAB_ACCESS_TOKEN (at least 32 bytes); never embed Apple credentials in client")
        }
        let mode = LabProviderMode(rawValue: env["LAB_PROVIDER_MODE"] ?? "replay")
        guard let mode else { throw LabFailure.invalid("LAB_PROVIDER_MODE must be replay or rest") }
        let dir = URL(fileURLWithPath: env["LAB_DATA_DIR"] ?? ".local", isDirectory: true).standardizedFileURL
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let app = try await Application.make(.development)
        app.http.server.configuration.hostname = env["LAB_HOST"] ?? "127.0.0.1"
        app.http.server.configuration.port = Int(env["LAB_PORT"] ?? "8767") ?? 8767
        app.routes.defaultMaxBodySize = "64kb"
        let worker = try await makeWorker(dir: dir, mode: mode)
        let precomputeSeconds = try await worker.runtime.precompute()
        let google = await MainActor.run { (try? PlacesConfiguration()).map { GooglePlacesClient(configuration: $0) } }
        let dynamic: DynamicTripService? = try await MainActor.run {
            guard mode == .rest, let google else { return nil }
            let contextBudget = LabProviderBudget(callLimit: Int(env["LAB_CONTEXT_HTTP_CAP"] ?? "900") ?? 900,
                                                  cellLimit: Int(env["LAB_CONTEXT_ETA_CAP"] ?? "720") ?? 720)
            return try DynamicTripService(google: google, apple: LabAppleREST(config: .init(), budget: contextBudget))
        }
        let recommendations: RecommendationService? = try await MainActor.run {
            guard mode == .rest, let key = env["OPENROUTER_API_KEY"],!key.isEmpty,
                  let googleKey = env["GOOGLE_PLACES_API_KEY"] else { return nil }
            let client = GooglePlacesClient(configuration: try PlacesConfiguration(apiKey: googleKey, maxRequests: 100))
            let apple = LabAppleREST(config: try .init(), budget: .init(callLimit: 120, cellLimit: 0))
            let llm = try OpenRouterClient(key: key, model: env["OPENROUTER_MODEL"] ?? OpenRouterClient.defaultModel,
                                           fallbackModel: env["OPENROUTER_FALLBACK_MODEL"] ?? OpenRouterClient.defaultFallbackModel, maxCalls: 40)
            return RecommendationService(google: client, apple: apple, llm: llm)
        }
        print("LAB_PRECOMPUTE seconds=\(precomputeSeconds)")
        func authorize(_ req: Request) throws {
            guard let supplied = req.headers.bearerAuthorization?.token,
                  LabJSON.digest(Data(supplied.utf8)) == LabJSON.digest(Data(token.utf8)) else { throw Abort(.unauthorized) }
        }
        func body<T: Decodable>(_ req: Request, as: T.Type) throws -> T {
            guard let buffer = req.body.data, buffer.readableBytes <= 65536 else { throw Abort(.payloadTooLarge) }
            do { return try LabJSON.decoder().decode(T.self, from: Data(buffer.readableBytesView)) }
            catch { throw Abort(.badRequest, reason: "Invalid lab JSON") }
        }
        func response<T: Encodable>(_ value: T, status: HTTPResponseStatus = .ok) throws -> Response {
            let data = try LabJSON.encoder().encode(value)
            guard data.count <= 5 * 1024 * 1024 else { throw Abort(.payloadTooLarge) }
            return Response(status: status, headers: ["Content-Type": "application/json", "Cache-Control": "no-store"], body: .init(data: data))
        }
        func identifier(_ req: Request) throws -> UUID {
            guard let text = req.parameters.get("id"), let id = UUID(uuidString: text) else { throw Abort(.badRequest) }; return id
        }
        func translate(_ error: Error) -> Error {
            if let e = error as? LabFailure {
                switch e {
                case .conflict: return Abort(.conflict, reason: e.localizedDescription)
                case .capacity: return Abort(.tooManyRequests, reason: e.localizedDescription)
                case .invalid: return Abort(.badRequest, reason: e.localizedDescription)
                case .unavailable: return Abort(.serviceUnavailable, reason: e.localizedDescription)
                }
            }; return error
        }
        func contextFailure(_ error: Error) -> Error {
            if error is CancellationError || error is any AbortError { return error }
            guard let context = error as? ContextError else { return Abort(.badGateway, reason: "Context provider response could not be processed") }
            switch context {
            case .invalid(let reason): return Abort(.badRequest, reason: reason)
            case .missingKey: return Abort(.serviceUnavailable, reason: context.localizedDescription)
            case .budget: return Abort(.tooManyRequests, reason: context.localizedDescription)
            case .provider, .response: return Abort(.badGateway, reason: context.localizedDescription)
            }
        }
        app.get("health") { _ in ["status": "ok", "providerMode": mode.rawValue, "service": "c67-local-server-lab"] }
        app.get("v1", "lab", "place-context", "capabilities") { @MainActor req async throws -> Response in
            try authorize(req)
            return try response(["configured": String(google != nil), "keyVariable": "GOOGLE_PLACES_API_KEY",
                                 "provider": "Google Places API (New)", "requests": String(google?.requests ?? 0), "cache": "none; live content not persisted",
                                 "routingIntegration": "separate context API; original routing/catalogue unchanged", "reviews": "optional; at most five; no popular-times claim"])
        }
        struct SearchContextInput: Decodable { var query: String; var limit: Int? }
        app.post("v1", "lab", "place-context", "search") { @MainActor req async throws -> Response in
            try authorize(req); let input = try body(req, as: SearchContextInput.self)
            guard let google else { throw Abort(.serviceUnavailable, reason: "Configure GOOGLE_PLACES_API_KEY in private local environment") }
            guard mode == .rest else { throw Abort(.conflict, reason: "Live Google context calls require server REST mode") }
            do { return try response(try await google.search(input.query, limit: input.limit ?? 5)) }
            catch { throw contextFailure(error) }
        }
        app.post("v1", "lab", "place-context", "evaluate") { @MainActor req async throws -> Response in
            try authorize(req); let input = try body(req, as: GoogleContextEvaluationInput.self)
            guard let google else { throw Abort(.serviceUnavailable, reason: "Configure GOOGLE_PLACES_API_KEY in private local environment") }
            guard mode == .rest else { throw Abort(.conflict, reason: "Live Google context calls require server REST mode") }
            do { return try response(try await GoogleContextService.evaluate(input, client: google)) }
            catch { throw contextFailure(error) }
        }
        app.get("v1", "lab", "context", "capabilities") { @MainActor req async throws -> Response in
            try authorize(req)
            return try response(["configured": String(dynamic != nil), "experiments": String(env["LAB_CONTEXT_EXPERIMENTS"] == "1"),
                                 "catalogue": "dynamic Google place selection and explicit Apple candidate confirmation", "gridDefaultMinutes": "5", "transportTransjakarta": "1"])
        }
        app.get("v1", "lab", "recommendation", "capabilities") { @MainActor req async throws -> Response in
            try authorize(req)
            return try response(["configured": String(recommendations != nil), "llm": "mandatory, zero price ceiling, bounded fallback to the configured free model",
                                 "targetSeconds": "20 client end-to-end; 19 server session", "profile": "on-device, explicit interests and pace; learned affinity within interests only"])
        }
        app.get("v1", "lab", "recommendation", "counters") { @MainActor req async throws -> Response in
            try authorize(req); return try response(recommendations?.counters ?? [:])
        }
        app.post("v1", "lab", "recommendation", "start") { @MainActor req async throws -> Response in
            try authorize(req); guard let recommendations else { throw Abort(.serviceUnavailable, reason: "OpenRouter/local provider configuration missing") }
            do { return try response(try await recommendations.start(body(req, as: RecommendationStart.self))) }
            catch { throw contextFailure(error) }
        }
        struct FixtureInput: Decodable { var input: RecommendationStart; var scenario: String }
        app.post("v1", "lab", "recommendation", "fixture") { @MainActor req async throws -> Response in
            try authorize(req); guard env["LAB_CONTEXT_EXPERIMENTS"] == "1" else { throw Abort(.notFound) }
            guard let recommendations else { throw Abort(.serviceUnavailable, reason: "OpenRouter configuration missing") }
            do { let value = try body(req, as: FixtureInput.self); return try response(try recommendations.startFixture(value.input, scenario: value.scenario)) }
            catch { throw contextFailure(error) }
        }
        app.post("v1", "lab", "recommendation", "complete") { @MainActor req async throws -> Response in
            try authorize(req); guard let recommendations, let dynamic else { throw Abort(.serviceUnavailable) }
            do {
                let value = try await recommendations.complete(body(req, as: RecommendationComplete.self))
                dynamic.registerRecommendedIDs(value.places.map(\.id)); return try response(value)
            } catch { throw contextFailure(error) }
        }
        app.post("v1", "lab", "recommendation", "plan") { @MainActor req async throws -> Response in
            try authorize(req); guard let recommendations, let dynamic else { throw Abort(.serviceUnavailable) }
            do {
                let input = try body(req, as: PersonalPlanInput.self), ids = try dynamic.selectedPlaceIDs(input.plan)
                guard Set(input.requiredPlaceIDs).count == input.requiredPlaceIDs.count, Set(input.requiredPlaceIDs).isSubset(of: Set(ids)) else {
                    throw ContextError.invalid("ID wajib tidak sah")
                }
                let profile = try recommendations.authorizePlan(recommendationID: input.recommendationID, profileRevision: input.profileRevision,
                                                                placeIDs: ids, departure: input.plan.departure, deadline: input.plan.deadline)
                let required = Set(input.requiredPlaceIDs)
                let result: DynamicPlanResponse
                let momentReview: MomentPlanReview?
                if input.considerMoments == true {
                    let choices = try await dynamic.planWithMoments(input.plan, requiredIDs: required)
                    (result, momentReview) = try await recommendations.chooseItinerary(choices, profile: profile)
                } else {
                    result = try await dynamic.plan(input.plan, requiredIDs: required)
                    momentReview = nil
                }
                let visited = Set(result.itinerary.visits.map(\.placeID))
                let omitted = ids.filter{ !visited.contains($0)}.map { id in
                    let status = result.itinerary.contexts.first{$0.placeID == id}?.status ?? "not_selected_within_search"
                    return PersonalPlanOmission(id: id, required: input.requiredPlaceIDs.contains(id),
                                                reason: status.contains("hours") || status == "closed" || status == "needs_identity_confirmation" ? status :
                                                    "Belum dipilih dalam batas pencarian; bukan bukti global tidak memungkinkan")
                }
                return try response(PersonalPlanResult(result: result, requiredPlaceIDs: input.requiredPlaceIDs, omitted: omitted, momentReview: momentReview))
            } catch { throw contextFailure(error) }
        }
        app.post("v1", "lab", "itinerary", "revisions", "preview") { @MainActor req async throws -> Response in
            try authorize(req); guard let dynamic else { throw Abort(.serviceUnavailable) }
            do {
                let input = try body(req, as: ItineraryRevisionInput.self)
                let ids = try dynamic.selectedPlaceIDs(input.plan)
                try input.validate(placeIDs: ids)
                for source in input.sources where source.origin == .recommendation {
                    guard let recommendations, let recommendationID = source.recommendationID, let revision = source.profileRevision else { throw ContextError.invalid("Recommendation proof missing") }
                    _ = try recommendations.authorizePlan(recommendationID: recommendationID, profileRevision: revision, placeIDs: [source.placeID], departure: input.plan.departure, deadline: input.plan.deadline)
                }
                // Explicit user/history choices need fresh place/identity evidence, not a new LLM endorsement.
                let choices = try await dynamic.planWithMoments(input.plan, requiredIDs: Set(input.requiredPlaceIDs))
                let result = input.result(for: choices.baseline)
                return try response(ItineraryRevisionPreview(input: input, result: result))
            } catch { throw contextFailure(error) }
        }
        app.get("v1", "lab", "context", "counters") { @MainActor req async throws -> Response in
            try authorize(req); return try response(dynamic?.counters ?? [:])
        }
        app.post("v1", "lab", "context", "search") { @MainActor req async throws -> Response in
            try authorize(req)
            guard let dynamic else { throw Abort(.serviceUnavailable, reason: "Live context service is not configured") }
            do { let value = try await dynamic.search(body(req, as: DynamicSearchInput.self)); return try response(value) }
            catch { throw contextFailure(error) }
        }
        app.post("v1", "lab", "context", "prepare") { @MainActor req async throws -> Response in
            try authorize(req)
            guard let dynamic else { throw Abort(.serviceUnavailable, reason: "Live context service is not configured") }
            do { let value = try await dynamic.prepare(body(req, as: DynamicPrepareInput.self)); return try response(value) }
            catch { throw contextFailure(error) }
        }
        app.post("v1", "lab", "context", "plan") { @MainActor req async throws -> Response in
            try authorize(req)
            guard let dynamic else { throw Abort(.serviceUnavailable, reason: "Live context service is not configured") }
            do { let value = try await dynamic.plan(body(req, as: DynamicPlanInput.self)); return try response(value) }
            catch { throw contextFailure(error) }
        }
        app.get("v1", "lab", "context", "scenarios") { @MainActor req async throws -> Response in
            try authorize(req)
            guard env["LAB_CONTEXT_EXPERIMENTS"] == "1" else { throw Abort(.notFound) }
            return try response(ContextExperiments.scenarios)
        }
        app.post("v1", "lab", "context", "experiment") { @MainActor req async throws -> Response in
            try authorize(req)
            guard env["LAB_CONTEXT_EXPERIMENTS"] == "1" else { throw Abort(.notFound) }
            let input = try body(req, as: ContextExperimentInput.self)
            do { let value = try await ContextExperiments.run(input.scenario); return try response(value) }
            catch { throw contextFailure(error) }
        }
        app.get("v1", "lab", "capabilities") { @MainActor req async throws -> Response in
            try authorize(req)
            return try await response(["schemaVersion": "1", "snapshotHash": worker.snapshot,
                                       "providerMode": mode.rawValue, "engine": "hybrid-elapsed_v2", "workerConcurrency": "1",
                                       "providerConcurrency": "1", "pinSnapshotHash": worker.pinSnapshotHash, "providerCalls": String(worker.providerCalls), "providerCells": String(worker.providerCells), "responseCacheCrossJob": "off", "variants": "B,C,D,E",
                                       "dateEncoding": "unix-seconds-double", "replayClock": mode == .replay ? LabMatrix.now.ISO8601Format() : "disabled"])
        }
        app.post("v1", "lab", "jobs") { @MainActor req async throws -> Response in
            try authorize(req); let input = try body(req, as: JobInput.self)
            do { return try await response(worker.submit(input), status: .accepted) } catch { throw translate(error) }
        }
        app.get("v1", "lab", "jobs", ":id") { @MainActor req async throws -> Response in
            try authorize(req); let id = try identifier(req)
            guard var job = try await worker.store.get(id) else { throw Abort(.notFound) }
            job.result = nil; return try response(job)
        }
        app.post("v1", "lab", "jobs", ":id", "cancel") { @MainActor req async throws -> Response in
            try authorize(req); return try await response(worker.cancel(identifier(req)))
        }
        app.get("v1", "lab", "jobs", ":id", "result") { @MainActor req async throws -> Response in
            try authorize(req)
            guard let job = try await worker.store.get(identifier(req)) else { throw Abort(.notFound) }
            guard job.state == .completed, let result = job.result else { throw Abort(.conflict, reason: "Result not complete") }
            return try response(result)
        }
        app.post("v1", "lab", "proposals", ":id", "apply") { @MainActor req async throws -> Response in
            try authorize(req); let id = try identifier(req); let input = try body(req, as: ApplyInput.self)
            guard let job = try await worker.store.all().first(where: { $0.result?.plan?.id == id }) else { throw Abort(.notFound) }
            do { return try await response(worker.store.apply(job.id, input: input, now: mode == .replay ? LabMatrix.now : .now)) }
            catch { throw translate(error) }
        }
        do { try await app.execute(); await worker.shutdown(); try await app.asyncShutdown() }
        catch { await worker.shutdown(); try? await app.asyncShutdown(); throw error }
    }
    @MainActor static func makeWorker(dir: URL, mode: LabProviderMode) throws -> LabWorker {
        let env = ProcessInfo.processInfo.environment
        let budget = LabProviderBudget(callLimit: Int(env["LAB_PROVIDER_CALL_CAP"] ?? "3000") ?? 3000,
                                       cellLimit: Int(env["LAB_ETA_CELL_CAP"] ?? "6000") ?? 6000)
        let apple = mode == .rest ? LabAppleREST(config: try .init(), budget: budget) : nil
        let pinSnapshot: LabPinSnapshot?
        if let path = ProcessInfo.processInfo.environment["LAB_PIN_SNAPSHOT_PATH"] {
            pinSnapshot = try LabJSON.decoder().decode(LabPinSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        } else { pinSnapshot = nil }
        return try LabWorker(store: JobStore(path: dir.appendingPathComponent("jobs.sqlite").path),
                             directory: dir, mode: mode, apple: apple, pinSnapshot: pinSnapshot)
    }
}
