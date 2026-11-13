import Foundation
import C67Domain

extension SupabaseRundownRepository {
    public func searchRundowns(query: String = "", area: String? = nil, limit: Int = 20,
                               cursor: String? = nil) async throws -> RepositoryPage<Rundown> {
        guard (1 ... 50).contains(limit), query.count <= 120, (area?.count ?? 0) <= 80,
              (cursor?.count ?? 0) <= 1024 else { throw RepositoryError.invalidInput }
        let page: PageDTO<Rundown> = try await rpc("search_rundowns", body: Search(
            p_query: query, p_area: area, p_limit: limit, p_cursor: cursor))
        return .init(items: page.items, nextCursor: page.next_cursor)
    }

    public func listMyTrips(limit: Int = 20, cursor: String? = nil) async throws -> RepositoryPage<Trip> {
        guard (1 ... 100).contains(limit), (cursor?.count ?? 0) <= 512 else { throw RepositoryError.invalidInput }
        let page: PageDTO<Trip> = try await privateRPC("list_my_trips", body: TripList(p_limit: limit, p_cursor: cursor))
        return .init(items: page.items, nextCursor: page.next_cursor)
    }

    public func tripGraph(id: UUID) async throws -> TripGraph {
        let dto: TripGraphDTO = try await privateRPC("get_trip_graph", body: TripID(p_trip_id: id))
        return dto.domain
    }

    private struct PageDTO<Item: Decodable>: Decodable { let items: [Item]; let next_cursor: String? }
    private struct Search: Encodable {
        let p_query: String
        let p_area: String?
        let p_limit: Int
        let p_cursor: String?
    }
    private struct TripList: Encodable { let p_limit: Int; let p_cursor: String? }
    private struct TripID: Encodable { let p_trip_id: UUID }
}
