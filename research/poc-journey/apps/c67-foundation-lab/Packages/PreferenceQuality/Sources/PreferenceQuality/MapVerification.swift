import Foundation
import MapKit

public struct QualityMapCheck: Codable, Identifiable, Sendable {
    public var id: String { candidateID }
    public var candidateID: String
    public var checkedAt: Date
    public var status: String
    public var mapName: String?
    public var latitude: Double?
    public var longitude: Double?
    public var note: String
}
@MainActor public final class QualityMapVerifier {
    private var activeSearch: MKLocalSearch?
    public init() {}
    public func verify(_ candidates: [QualityCandidate]) async throws -> [QualityMapCheck] {
        var result: [QualityMapCheck] = []
        for candidate in candidates.prefix(3) {
            try Task.checkCancellation()
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = candidate.mapQuery
            request.region = .init(
                center: .init(latitude: -6.20, longitude: 106.82),
                span: .init(latitudeDelta: 0.4, longitudeDelta: 0.4))
            request.resultTypes = .pointOfInterest
            let search = MKLocalSearch(request: request)
            activeSearch = search
            let deadline = Task { @MainActor in
                try await Task.sleep(for: .seconds(20))
                self.activeSearch?.cancel()
            }
            do {
                let response = try await withTaskCancellationHandler {
                    try await search.start()
                } onCancel: {
                    Task { @MainActor in self.activeSearch?.cancel() }
                }
                deadline.cancel()
                try Task.checkCancellation()
                let values = response.mapItems.filter {
                    let name = ($0.name ?? "").lowercased()
                    let coord = $0.location.coordinate
                    return candidate.matchWords.allSatisfy(name.contains)
                        && (-6.45 ... -6.05).contains(coord.latitude)
                        && (106.65 ... 107.0).contains(coord.longitude)
                }
                let item = values.count == 1 ? values.first : nil
                result.append(
                    .init(
                        candidateID: candidate.id, checkedAt: .now,
                        status: item == nil ? "ambiguous_or_missing" : "identity_matched",
                        mapName: item?.name, latitude: item?.location.coordinate.latitude,
                        longitude: item?.location.coordinate.longitude,
                        note:
                        "MapKit identity only; \(values.count) matching rows. This does not verify room-level facilities, entry, or route."
                    ))
            } catch is CancellationError {
                deadline.cancel()
                throw CancellationError()
            } catch {
                deadline.cancel()
                try Task.checkCancellation()
                result.append(
                    .init(
                        candidateID: candidate.id, checkedAt: .now, status: "search_failed",
                        note: error.localizedDescription))
            }
        }
        activeSearch = nil
        return result
    }
}
