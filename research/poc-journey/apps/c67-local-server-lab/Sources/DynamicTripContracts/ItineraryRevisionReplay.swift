import Foundation
import PlaceContextEngine

/// Deterministic, explicitly synthetic editor acceptance data. Never a live fallback.
@MainActor public enum ItineraryRevisionReplay {
    public static let ids = ["revision-park", "revision-museum", "revision-cafe", "revision-library"]
    public static func prepared(_ id: String, now: Date = .now) throws -> DynamicPreparedPlace {
        let index = ids.firstIndex(of: id) ?? 0
        let names = ["Taman Sintetis", "Museum Sintetis", "Kafe Sintetis", "Perpustakaan Sintetis"]
        let bytes = try JSONSerialization.data(withJSONObject: ["id": id, "displayName": ["text": names[index]], "formattedAddress": "SYNTHETIC Jakarta", "location": ["latitude": -6.175 - Double(index) * 0.02, "longitude": 106.82], "businessStatus": "OPERATIONAL", "timeZone": ["id": "Asia/Jakarta"], "utcOffsetMinutes": 420, "regularOpeningHours": ["periods": [["open": ["day": 0, "hour": 0, "minute": 0]]]]])
        let snapshot = PlaceSnapshot(place: try JSONDecoder().decode(GooglePlace.self, from: bytes), fetchedAt: now, fieldMask: "SYNTHETIC", source: "SYNTHETIC")
        let tomorrow = ContextClock.calendar.startOfDay(for: now).addingTimeInterval(86400)
        return .init(id: UUID(), googlePlaceID: id, name: names[index], address: "SYNTHETIC Jakarta", googleMapsURL: nil, attribution: "SYNTHETIC acceptance fixture; no live providers", expiresAt: now.addingTimeInterval(900), hours: GoogleHoursResolver.resolve(snapshot, day: ContextClock.label(tomorrow), allowRegular: true, now: now), appleCandidates: [.init(id: id + "-apple", name: names[index], address: "SYNTHETIC Jakarta", latitude: -6.175 - Double(index) * 0.02, longitude: 106.82, distanceFromGoogleMeters: 0, nameSupported: true)])
    }
    public static func place(_ id: String, now: Date = .now) throws -> RevisionPlace {
        let value = try prepared(id, now: now); return .init(prepared: value, apple: value.appleCandidates[0])
    }
    public static func initial(now: Date = .now) async throws -> LocalItineraryRevision {
        let origin = try place("revision-origin", now: now)
        let rows = try ids.prefix(2).map { id in RevisionStop(place: try place(id, now: now), required: true, durationMinutes: 30, source: .init(placeID: id, origin: .userSelected)) }
        let day = ContextClock.calendar.startOfDay(for: now).addingTimeInterval(86400)
        let draft = ItineraryEditDraft(parentRevisionID: UUID(), origin: origin, stops: rows, departure: day.addingTimeInterval(9 * 3600), deadline: day.addingTimeInterval(18 * 3600), maximumWaitingMinutes: 120)
        let output = try await preview(draft.request(), now: now)
        guard output.canApply else { throw ContextError.invalid("Synthetic initial plan failed: " + output.result.result.itinerary.status) }
        return .init(draft: draft, result: output.result, savedAt: now)
    }
    public struct Travel: ContextTravelProvider {
        public var transport: ContextTransport
        public init(transport: ContextTransport) { self.transport = transport }
        public func travel(from: String, to: String, departure: Date) async throws -> ContextTravelTime? {
            try Task.checkCancellation()
            let points = [ContextRoutePoint(latitude: -6.175, longitude: 106.82), .init(latitude: -6.18, longitude: 106.821), .init(latitude: -6.195, longitude: 106.82)]
            let details = ContextTransportDetails(mode: transport.rawValue, walkingSeconds: transport == .transjakarta ? 120 : 0, transitWaitingSeconds: transport == .transjakarta ? 300 : 0, summary: transport == .transjakarta ? "SYNTHETIC TJ · Halte A → pindah → Halte B" : "SYNTHETIC Mobil", segments: [.init(id: "synthetic", kind: transport == .transjakarta ? "bus" : "automobile", label: "SYNTHETIC fixture geometry", from: points[0], to: points[2], points: points, geometryStatus: "synthetic_fixture")])
            return .init(seconds: transport == .transjakarta ? 900 : 300, departure: departure, source: "SYNTHETIC deterministic fixture", details: details)
        }
    }
    public static func preview(_ input: ItineraryRevisionInput, now: Date = .now) async throws -> ItineraryRevisionPreview {
        let ids = input.sources.map(\.placeID); try input.validate(placeIDs: ids)
        let day = ContextClock.label(input.plan.departure)
        let stops = try zip(input.plan.stops, ids).map { stop, id -> ContextPlanStop in
            let prepared = try prepared(id, now: now)
            let bytes = try JSONSerialization.data(withJSONObject: ["id": id, "displayName": ["text": prepared.name], "businessStatus": "OPERATIONAL", "timeZone": ["id": "Asia/Jakarta"], "utcOffsetMinutes": 420, "regularOpeningHours": ["periods": [["open": ["day": 0, "hour": 0, "minute": 0]]]]])
            let snapshot = PlaceSnapshot(place: try JSONDecoder().decode(GooglePlace.self, from: bytes), fetchedAt: now, fieldMask: "SYNTHETIC", source: "SYNTHETIC")
            var request = VisitContextRequest(placeID: id, day: day)
            request.identityConfirmed = true; request.durationMinutes = stop.durationMinutes; request.startStepMinutes = 5
            return .init(snapshot: snapshot, request: request)
        }
        var request = ContextPlanRequest(originID: "origin-" + input.plan.origin.preparedID.uuidString, returnID: "origin-" + input.plan.origin.preparedID.uuidString, departure: input.plan.departure, deadline: input.plan.deadline, stops: stops)
        request.order = .fixed; request.maximumTotalWaitingMinutes = input.plan.maximumWaitingMinutes; request.allVisitSlots = true
        let start = ContinuousClock.now
        let trip = try await OptionalItineraryPlanner.plan(request, requiredIDs: Set(input.requiredPlaceIDs), provider: Travel(transport: input.plan.transport ?? .automobile), now: now)
        let duration = start.duration(to: .now).components
        let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        let response = DynamicPlanResponse(itinerary: trip, metrics: .init(preparationSeconds: 0, routingSeconds: seconds, etaAdapterSeconds: 0, serverTotalSeconds: seconds, etaCalls: trip.travelCalls, unavailableETA: 0, weatherStatus: "SYNTHETIC_NOT_REQUESTED", evidenceMode: "SYNTHETIC"))
        return .init(input: input, result: input.result(for: response), generatedAt: now)
    }
}
