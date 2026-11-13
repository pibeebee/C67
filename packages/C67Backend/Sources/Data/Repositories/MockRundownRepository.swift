import Foundation
import C67Domain

/// Synthetic data and memory-only trips. No network, authentication or disk persistence.
public actor MockRundownRepository: RundownRepository {
    private let rundowns: [Rundown]
    private let syntheticRootIDs: [UUID: UUID]
    private var graphs: [UUID: TripGraph] = [:]
    private var trips: [UUID: Trip] = [:]

    public init() throws {
        guard let url = Bundle.module.url(forResource: "rundowns", withExtension: "json") else {
            throw RepositoryError.notFound
        }
        rundowns = try JSONDecoder().decode([Rundown].self, from: Data(contentsOf: url))
        syntheticRootIDs = Dictionary(uniqueKeysWithValues: rundowns.map { ($0.id, UUID()) })
    }

    public func listRundowns() async throws -> [Rundown] { rundowns }
    public func rundown(id: UUID) async throws -> Rundown {
        guard let value = rundowns.first(where: { $0.id == id }) else { throw RepositoryError.notFound }
        return value
    }
    public func createTrip(from versionID: UUID, startsAt: Date, requestID: UUID) async throws -> Trip {
        if let existing = trips[requestID] {
            guard existing.sourceVersionID == versionID, existing.startsAt == startsAt else {
                throw RepositoryError.idempotencyConflict
            }
            return existing
        }
        let source = try await rundown(id: versionID)
        let trip = Trip(id: UUID(), sourceVersionID: source.id, title: source.title,
                        startsAt: startsAt, stops: source.stops)
        graphs[trip.id] = makeGraph(trip)
        trips[requestID] = trip
        return trip
    }

    public func searchRundowns(query: String = "", area: String? = nil, limit: Int = 20,
                               cursor: String? = nil) async throws -> RepositoryPage<Rundown> {
        guard (1 ... 50).contains(limit), query.count <= 120, (area?.count ?? 0) <= 80,
              (cursor?.count ?? 0) <= 1024 else { throw RepositoryError.invalidInput }
        let normalized = query.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let area = area?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let binding = normalized + "\u{1f}" + (area ?? "")
        let after = try decodeCursor(cursor, kind: "discovery", binding: binding)
        let words = Set(normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let matches = rundowns.filter { item in
            let text = Set((item.title + " " + item.summary + " " + item.area).lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            return (area == nil || area == "" || item.area.lowercased() == area)
                && words.isSubset(of: text) && (after == nil || item.id.uuidString < after!.id.uuidString)
        }.sorted { $0.id.uuidString > $1.id.uuidString }
        let items = Array(matches.prefix(limit))
        let next = matches.count > limit ? try items.last.map { try encodeCursor(.init(
            kind: "discovery", binding: binding, id: $0.id, startsAt: nil)) } : nil
        return .init(items: items, nextCursor: next)
    }

    public func listMyTrips(limit: Int = 20, cursor: String? = nil) async throws -> RepositoryPage<Trip> {
        guard (1 ... 100).contains(limit), (cursor?.count ?? 0) <= 512 else { throw RepositoryError.invalidInput }
        let after = try decodeCursor(cursor, kind: "trips", binding: "synthetic")
        if let after, after.startsAt == nil { throw RepositoryError.invalidInput }
        let matches = trips.values.filter { item in
            guard let after, let date = after.startsAt else { return true }
            return item.startsAt < date || (item.startsAt == date && item.id.uuidString < after.id.uuidString)
        }.sorted { $0.startsAt == $1.startsAt ? $0.id.uuidString > $1.id.uuidString : $0.startsAt > $1.startsAt }
        let items = Array(matches.prefix(limit))
        let next = matches.count > limit ? try items.last.map { try encodeCursor(.init(
            kind: "trips", binding: "synthetic", id: $0.id, startsAt: $0.startsAt)) } : nil
        return .init(items: items, nextCursor: next)
    }

    public func tripGraph(id: UUID) async throws -> TripGraph {
        guard let graph = graphs[id] else { throw RepositoryError.notFound }
        return graph
    }

    private func makeGraph(_ trip: Trip) -> TripGraph {
        let dayID = UUID(), sourceID = UUID()
        let stops = trip.stops.sorted { $0.order < $1.order }.map {
            GraphStop(id: UUID(), dayID: dayID, sourceID: sourceID, sourceStopID: $0.id,
                      position: $0.order, title: $0.title, location: nil, timeZone: nil,
                      visitDurationSeconds: nil, progressStatus: "not_started")
        }
        let legs = zip(stops, stops.dropFirst()).enumerated().map { index, pair in
            GraphLeg(id: UUID(), dayID: dayID, position: index, kind: "between_stops",
                     fromTripStopID: pair.0.id, toTripStopID: pair.1.id, transportMode: "unknown",
                     durationSeconds: nil, sourceLegID: nil, estimateOrigin: "unknown")
        }
        return .init(schemaVersion: 3, id: trip.id, title: trip.title, startsAt: trip.startsAt, revision: 1,
                     status: "planned", sources: [.init(id: sourceID, rundownID: syntheticRootIDs[trip.sourceVersionID]!,
                                                        versionID: trip.sourceVersionID, versionNo: 1, title: trip.title)],
                     days: [.init(id: dayID, dayIndex: 0, startsAt: trip.startsAt, timeZone: nil, localDate: nil,
                                  startTimeBasis: "unspecified", origin: nil,
                                  landing: .init(kind: "unknown", tripStopID: nil, location: nil))], stops: stops, legs: legs,
                     warnings: ["landing_unknown", "start_basis_unspecified", "stop_location_unknown",
                                "visit_duration_unknown", "leg_duration_unknown"])
    }
    private struct Cursor: Codable {
        let kind: String
        let binding: String
        let id: UUID
        let startsAt: Date?
    }
    private func encodeCursor(_ cursor: Cursor) throws -> String { try JSONEncoder().encode(cursor).base64EncodedString() }
    private func decodeCursor(_ value: String?, kind: String, binding: String) throws -> Cursor? {
        guard let value else { return nil }
        guard let data = Data(base64Encoded: value), let cursor = try? JSONDecoder().decode(Cursor.self, from: data),
              cursor.kind == kind, cursor.binding == binding else { throw RepositoryError.invalidInput }
        return cursor
    }
}
