import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Testing
import C67Domain
import C67Data

@Test func queryAdaptersPreserveCursorAndUseTravellerJWTOnlyForPrivateRPCs() async throws {
    let graph = try contractFixture("trip-graph"), page = try contractFixture("trip-page")
    let http = HTTPHarness { request in
        let body = try requestBody(request)
        #expect(request.value(forHTTPHeaderField: "apikey") == "opaque-client")
        switch request.url!.lastPathComponent {
        case "search_rundowns":
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(body["p_query"] as? String == "photo walk")
            #expect(body["p_area"] as? String == "Jakarta")
            #expect(body["p_cursor"] as? String == "opaque+/cursor==")
            #expect(body["p_limit"] as? Int == 7)
            return .init(#"{"items":[],"next_cursor":"unchanged+/=="}"#)
        case "list_my_trips":
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-traveller")
            #expect(body["p_cursor"] as? String == "account-bound-cursor")
            return .init(data: page)
        case "get_trip_graph":
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-traveller")
            #expect((body["p_trip_id"] as? String)?.lowercased() == "51111111-1111-4111-8111-111111111111")
            return .init(data: graph)
        default: Issue.record("Unexpected RPC"); return .init(500, "{}")
        }
    }
    let repository = try SupabaseRundownRepository(baseURL: http.baseURL, clientKey: "opaque-client",
                                                   session: http.session, accessToken: { "synthetic-traveller" })
    let discovery = try await repository.searchRundowns(query: "photo walk", area: "Jakarta", limit: 7, cursor: "opaque+/cursor==")
    #expect(discovery.items.isEmpty && discovery.nextCursor == "unchanged+/==")
    let trips = try await repository.listMyTrips(limit: 1, cursor: "account-bound-cursor")
    #expect(trips.items.count == 1 && trips.nextCursor == nil)
    let value = try await repository.tripGraph(id: UUID(uuidString: "51111111-1111-4111-8111-111111111111")!)
    #expect(value.schemaVersion == 3 && value.revision == 1)
    #expect(value.days[0].origin?.latitude == 0)
    #expect(value.days[0].landing.location?.longitude == 1)
    #expect(value.stops[0].location?.longitude == 2)
    #expect(value.legs[0].durationSeconds == nil)
    #expect(value.legs[1].toTripStopID == value.stops[0].id)
}

@Test func legacyGraphKeepsUnknownTimesAndLocations() async throws {
    let graph = try contractFixture("trip-graph-legacy")
    let http = HTTPHarness { _ in .init(data: graph) }
    let repository = try SupabaseRundownRepository(baseURL: http.baseURL, clientKey: "client",
                                                   session: http.session, accessToken: { "synthetic" })
    let value = try await repository.tripGraph(id: UUID())
    #expect(value.days[0].timeZone == nil && value.days[0].localDate == nil)
    #expect(value.days[0].origin == nil && value.days[0].landing.kind == "unknown")
    #expect(value.stops.allSatisfy { $0.location == nil && $0.visitDurationSeconds == nil })
    #expect(value.warnings.contains("landing_unknown"))
}

@Test func queryValidationAndMissingSessionDoNotSendRequests() async throws {
    let http = HTTPHarness { _ in Issue.record("Network must not be reached"); return .init(500, "{}") }
    let repository = try SupabaseRundownRepository(baseURL: http.baseURL, clientKey: "client", session: http.session)
    await #expect(throws: RepositoryError.authenticationRequired) { try await repository.listMyTrips() }
    await #expect(throws: RepositoryError.authenticationRequired) { try await repository.tripGraph(id: UUID()) }
    await #expect(throws: RepositoryError.invalidInput) {
        try await repository.searchRundowns(query: "", area: nil, limit: 51, cursor: nil)
    }
    #expect(await http.log.requests().isEmpty)
}

@Test func rpcPreservesSessionFailureAndMapsAccessErrors() async throws {
    let http = HTTPHarness { _ in .init(403, #"{"message":"not exposed"}"#) }
    let repository = try SupabaseRundownRepository(baseURL: http.baseURL, clientKey: "client", session: http.session,
                                                   accessToken: { throw AuthenticationError.sessionExpired })
    await #expect(throws: AuthenticationError.sessionExpired) { try await repository.listMyTrips() }
    #expect(await http.log.requests().isEmpty)
    let signedIn = try SupabaseRundownRepository(baseURL: http.baseURL, clientKey: "client", session: http.session,
                                                 accessToken: { "synthetic" })
    await #expect(throws: RepositoryError.accessDenied) { try await signedIn.tripGraph(id: UUID()) }
}

@Test func authenticatedRPCObtainsRefreshedTokenFromSessionProvider() async throws {
    let page = try contractFixture("trip-page")
    let http = HTTPHarness { request in
        if request.url!.path.contains("auth/v1/token") {
            let refreshed = request.url!.query == "grant_type=refresh_token"
            let access = refreshed ? "rotated-traveller" : "first-traveller"
            return .init("""
            {"access_token":"\(access)","refresh_token":"synthetic-refresh","token_type":"bearer","expires_in":3600,
             "user":{"id":"91111111-1111-4111-8111-111111111111","email":"a@example.test"}}
            """)
        }
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer rotated-traveller")
        return .init(data: page)
    }
    let clock = TestClock()
    let authentication = try SupabaseAuthentication(baseURL: http.baseURL, clientKey: "client", store: MemorySessionStore(),
                                                    session: http.session, now: { clock.now() })
    _ = try await authentication.signIn(email: "a@example.test", password: "synthetic")
    clock.advance(3590)
    let repository = try SupabaseRundownRepository(baseURL: http.baseURL, clientKey: "client", session: http.session,
                                                   accessToken: { try await authentication.accessToken() })
    #expect(try await repository.listMyTrips().items.count == 1)
}

@Test func mockSearchPaginationAndStableGraphAreExplicitlySynthetic() async throws {
    let repository: any RundownRepository = try MockRundownRepository()
    let found = try await repository.searchRundowns(query: "PHOTO walk", area: "jakarta")
    let source = try #require(found.items.first)
    #expect(try await repository.searchRundowns(query: "missing-word").items.isEmpty)
    let first = try await repository.createTrip(from: source.id, startsAt: Date(timeIntervalSince1970: 100), requestID: UUID())
    _ = try await repository.createTrip(from: source.id, startsAt: Date(timeIntervalSince1970: 200), requestID: UUID())
    let page = try await repository.listMyTrips(limit: 1, cursor: nil)
    let cursor = try #require(page.nextCursor)
    let second = try await repository.listMyTrips(limit: 1, cursor: cursor)
    #expect(second.items == [first] && second.nextCursor == nil)
    await #expect(throws: RepositoryError.invalidInput) { try await repository.listMyTrips(limit: 20, cursor: "invalid") }
    let graph = try await repository.tripGraph(id: first.id)
    #expect(try await repository.tripGraph(id: first.id) == graph)
    #expect(graph.stops.map(\.sourceStopID) == source.stops.map(\.id))
    #expect(graph.stops.allSatisfy { $0.location == nil })
}

@Test func serverRejectionInvalidatesOnlyTheRejectedTravellerSession() async throws {
    let http = HTTPHarness { request in
        if request.url!.path.contains("auth/v1/token") {
            return .init("""
            {"access_token":"rejected-access","refresh_token":"synthetic-refresh","token_type":"bearer","expires_in":3600,
             "user":{"id":"91111111-1111-4111-8111-111111111111","email":"a@example.test"}}
            """)
        }
        return .init(401, "{}")
    }
    let service = try SupabaseAuthentication(baseURL: http.baseURL, clientKey: "client", store: MemorySessionStore(), session: http.session)
    _ = try await service.signIn(email: "a@example.test", password: "synthetic")
    let repository = try SupabaseRundownRepository(baseURL: http.baseURL, clientKey: "client", session: http.session,
                                                   accessToken: { try await service.accessToken() },
                                                   onUnauthorized: { try await service.invalidateSession(rejectedToken: $0) })
    await #expect(throws: RepositoryError.authenticationRequired) { try await repository.listMyTrips() }
    #expect(try await service.currentAccount() == nil)
    #expect(await http.log.requests().count == 2)
}
