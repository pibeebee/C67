import Foundation
import PlaceContextEngine

public struct RevisionPlace: Codable, Sendable {
    public var prepared: DynamicPreparedPlace
    public var apple: DynamicAppleCandidate
    public var endpoint: DynamicEndpoint { .init(preparedID: prepared.id, appleCandidateID: apple.id) }
    public init(prepared: DynamicPreparedPlace, apple: DynamicAppleCandidate) { self.prepared = prepared; self.apple = apple }
}
public struct RevisionStop: Codable, Sendable, Identifiable {
    public var id: UUID
    public var place: RevisionPlace
    public var required: Bool
    public var durationMinutes: Int
    public var exposure: ActivityExposure
    public var preferredTime: PreferredVisitTime?
    public var avoidRain: Bool
    public var source: RevisionPlaceSource
    public init(id: UUID = UUID(), place: RevisionPlace, required: Bool, durationMinutes: Int = 60, exposure: ActivityExposure = .unknown, preferredTime: PreferredVisitTime? = nil, avoidRain: Bool = false, source: RevisionPlaceSource) {
        self.id = id; self.place = place; self.required = required; self.durationMinutes = durationMinutes
        self.exposure = exposure; self.preferredTime = preferredTime; self.avoidRain = avoidRain; self.source = source
    }
    public var input: DynamicStopInput { .init(endpoint: place.endpoint, durationMinutes: durationMinutes, exposure: exposure, preferredTime: preferredTime, avoidRain: avoidRain) }
}
public struct ItineraryEditDraft: Codable, Sendable, Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        let encoder = ContextJSON.encoder(); encoder.outputFormatting.insert(.sortedKeys)
        guard let a = try? encoder.encode(lhs), let b = try? encoder.encode(rhs) else { return false }; return a == b
    }
    public var id: UUID
    public var parentRevisionID: UUID
    public var origin: RevisionPlace
    public var stops: [RevisionStop]
    public var omittedStops: [RevisionStop]
    public var departure: Date
    public var deadline: Date
    public var maximumWaitingMinutes: Int
    public var transport: ContextTransport
    public init(parentRevisionID: UUID, origin: RevisionPlace, stops: [RevisionStop], departure: Date, deadline: Date, maximumWaitingMinutes: Int, transport: ContextTransport = .automobile, omittedStops: [RevisionStop] = []) {
        id = UUID(); self.parentRevisionID = parentRevisionID; self.origin = origin; self.stops = stops; self.departure = departure; self.deadline = deadline
        self.maximumWaitingMinutes = maximumWaitingMinutes; self.transport = transport; self.omittedStops = omittedStops
    }
    public func request() throws -> ItineraryRevisionInput {
        let ids = stops.map { $0.place.prepared.googlePlaceID }
        guard (1 ... 6).contains(stops.count), Set(ids).count == stops.count, !ids.contains(origin.prepared.googlePlaceID),
              stops.allSatisfy({ $0.source.placeID == $0.place.prepared.googlePlaceID }) else { throw ContextError.invalid("Pilih 1–6 tujuan unik; lokasi awal bukan tujuan") }
        var plan = DynamicPlanInput(origin: origin.endpoint, stops: stops.map(\.input), departure: departure, deadline: deadline, maximumWaitingMinutes: maximumWaitingMinutes)
        plan.transport = transport; plan.order = .fixed
        return .init(draftID: id, parentRevisionID: parentRevisionID, plan: plan, requiredPlaceIDs: stops.filter(\.required).map { $0.place.prepared.googlePlaceID }, sources: stops.map(\.source))
    }
}
public struct LocalItineraryRevision: Codable, Sendable, Identifiable {
    public var id: UUID
    public var parentRevisionID: UUID?
    public var draft: ItineraryEditDraft
    public var result: PersonalPlanResult
    public var savedAt: Date
    public init(id: UUID = UUID(), parentRevisionID: UUID? = nil, draft: ItineraryEditDraft, result: PersonalPlanResult, savedAt: Date = .now) {
        self.id = id; self.parentRevisionID = parentRevisionID; self.draft = draft; self.result = result; self.savedAt = savedAt
    }
}
public struct ItineraryRevisionState: Codable, Sendable {
    public var schemaVersion = 1
    public private(set) var revisions: [LocalItineraryRevision] = []
    public private(set) var draft: ItineraryEditDraft?
    public private(set) var preview: ItineraryRevisionPreview?
    public var current: LocalItineraryRevision? { revisions.last }
    public init() {}
    @discardableResult public mutating func capture(_ revision: LocalItineraryRevision) -> Bool {
        guard draft == nil else { return false }
        revisions.append(revision); preview = nil; return true
    }
    public mutating func begin() throws {
        guard draft == nil else { throw ContextError.invalid("Selesaikan atau batalkan draft yang masih tersimpan") }
        guard let current else { throw ContextError.invalid("Belum ada itinerary tersimpan") }
        var next = current.draft; next.parentRevisionID = current.id; next.id = UUID()
        let ordered = current.result.result.itinerary.visits.map(\.placeID)
        next.stops = ordered.compactMap { id in current.draft.stops.first { $0.place.prepared.googlePlaceID == id } }
        var seen = Set<String>()
        next.omittedStops = (current.draft.stops + current.draft.omittedStops).filter {
            let id = $0.place.prepared.googlePlaceID
            return !ordered.contains(id) && seen.insert(id).inserted
        }
        for i in next.stops.indices { next.stops[i].source = .init(placeID: next.stops[i].place.prepared.googlePlaceID, origin: .previousPlan) }
        for i in next.omittedStops.indices { next.omittedStops[i].source = .init(placeID: next.omittedStops[i].place.prepared.googlePlaceID, origin: .previousPlan) }
        draft = next; preview = nil
    }
    public mutating func change(_ edit: (inout ItineraryEditDraft) throws -> Void) rethrows {
        guard var next = draft else { return }
        try edit(&next); guard next != draft else { return }; next.id = UUID(); draft = next; preview = nil
    }
    public mutating func move(from: Int, to: Int) {
        change { draft in
            guard draft.stops.indices.contains(from), draft.stops.indices.contains(to) else { return }
            let value = draft.stops.remove(at: from); draft.stops.insert(value, at: to)
        }
    }
    public mutating func put(_ stop: RevisionStop, replacing id: UUID? = nil) throws {
        try change { draft in
            guard stop.place.prepared.googlePlaceID != draft.origin.prepared.googlePlaceID,
                  !draft.stops.contains(where: { $0.id != id && $0.place.prepared.googlePlaceID == stop.place.prepared.googlePlaceID }) else { throw ContextError.invalid("Tempat sudah dipilih atau sama dengan lokasi awal") }
            if let id {
                guard let index = draft.stops.firstIndex(where: { $0.id == id }) else { throw ContextError.invalid("Tujuan yang diganti sudah berubah") }
                var value = stop; value.id = id; value.required = draft.stops[index].required
                draft.stops[index] = value
            } else {
                guard draft.stops.count < 6 else { throw ContextError.invalid("Maksimal enam tujuan") }
                draft.stops.append(stop)
            }
            draft.omittedStops.removeAll { $0.place.prepared.googlePlaceID == stop.place.prepared.googlePlaceID }
        }
    }
    public mutating func receive(_ value: ItineraryRevisionPreview) -> Bool {
        guard let draft, value.draftID == draft.id, value.parentRevisionID == draft.parentRevisionID, current?.id == draft.parentRevisionID else { return false }
        preview = value; return true
    }
    public func canApply(now: Date = .now) -> Bool {
        guard let draft, let preview, preview.canApply, preview.draftID == draft.id, preview.parentRevisionID == current?.id,
              preview.generatedAt <= now, now.timeIntervalSince(preview.generatedAt) < 900, draft.departure > now,
              draft.origin.prepared.expiresAt > now, draft.stops.allSatisfy({ $0.place.prepared.expiresAt > now }) else { return false }
        return true
    }
    public mutating func apply(now: Date = .now) throws {
        guard canApply(now: now), let draft, let preview else { throw ContextError.invalid("Preview tidak berlaku; segarkan tempat dan hitung ulang") }
        revisions.append(.init(parentRevisionID: draft.parentRevisionID, draft: draft, result: preview.result, savedAt: now))
        self.draft = nil; self.preview = nil
    }
    public mutating func cancel() { draft = nil; preview = nil }
    public mutating func discardPreview() { preview = nil }
}

public struct ItineraryRevisionStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> ItineraryRevisionState {
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        var state = try ContextJSON.decoder().decode(ItineraryRevisionState.self, from: Data(contentsOf: url))
        guard state.schemaVersion == 1 else { throw ContextError.invalid("Versi penyimpanan tidak didukung") }
        // A restored preview is historical; obtain a fresh calculation before applying it.
        state.discardPreview(); return state
    }
    public func save(_ state: ItineraryRevisionState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ContextJSON.encoder().encode(state).write(to: url, options: .atomic)
    }
}
