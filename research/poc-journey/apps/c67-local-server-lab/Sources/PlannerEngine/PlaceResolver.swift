import Foundation
import MapKit

@MainActor public protocol TripPlaceSearching {
    func search(query: String) async throws -> [PlacePin]
    func cancel()
}

@MainActor public final class MapKitTripSearch: TripPlaceSearching {
    private var operation: MKLocalSearch?
    private var operationID: UUID?
    public init() {}
    public func cancel() { operation?.cancel() }
    public func search(query: String) async throws -> [PlacePin] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = .init(center: .init(latitude: -6.2, longitude: 106.83),
                               latitudinalMeters: 45000, longitudinalMeters: 45000)
        request.resultTypes = .pointOfInterest
        let operation = MKLocalSearch(request: request)
        let operationID = UUID()
        self.operation = operation
        self.operationID = operationID
        let deadline = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(35)) } catch { return }
            operation.cancel()
        }
        defer {
            deadline.cancel()
            if self.operationID == operationID { self.operation = nil; self.operationID = nil }
        }
        return try await withTaskCancellationHandler {
            let result = try await operation.start()
            try Task.checkCancellation()
            return result.mapItems.prefix(10).map { item in
                let coordinate = item.location.coordinate
                return PlacePin(id: "\(item.name ?? query):\(coordinate.latitude):\(coordinate.longitude)",
                                name: item.name ?? query, address: item.address?.fullAddress ?? "Alamat tidak tersedia",
                                latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                if self?.operationID == operationID { self?.cancel() }
            }
        }
    }
}

public enum PlaceIdentityPolicy {
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    }
    public static func review(id: String, query: String, words: [String], branch: String?,
                              results: [PlacePin]) -> LocationReview {
        var unique: [PlacePin] = []
        for pin in results where IntegrationCatalog.contains(pin) {
            if !unique.contains(where: {
                normalize($0.name) == normalize(pin.name)
                    && abs($0.latitude - pin.latitude) < 0.0003 && abs($0.longitude - pin.longitude) < 0.0003
            }) { unique.append(pin) }
        }
        let matches = unique.filter { pin in
            let name = normalize(pin.name)
            let combined = name + " " + normalize(pin.address)
            // Observed in the 2026-11-05 live Mac/iPhone run. This alias is scoped
            // to the Cikini identity and still requires the Cikini branch address.
            let localizedCikini = id == "cikini" && branch == "cikini"
                && ["jakarta", "provincial", "library"].allSatisfy { name.contains($0) }
            return (words.allSatisfy { name.contains(normalize($0)) } || localizedCikini)
                && (branch.map { combined.contains(normalize($0)) } ?? true)
        }
        let selected = matches.count == 1 ? matches[0] : nil
        return LocationReview(id: id, query: query, candidates: matches, selected: selected,
                              issue: selected == nil ? (unique.isEmpty ? "Tidak ada hasil MapKit di Jakarta." : matches.isEmpty
                                  ? "Hasil MapKit tidak cocok dengan nama/cabang bersumber. Tidak menerapkan fakta ke cabang lain."
                                  : "Ada beberapa kecocokan nama/cabang. Pilih hasil MapKit yang benar secara eksplisit.") : nil)
    }
}
