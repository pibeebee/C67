import Foundation
import SwiftUI
@preconcurrency import MapKit
import C67Domain

@MainActor final class MapKitTripPlaceSearch: TripPlaceSearching {
    private var identities: [String: UUID] = [:]

    static func isEmptyResult(_ error: any Error) -> Bool {
        let value = error as NSError
        return value.domain == MKErrorDomain && value.code == MKError.Code.placemarkNotFound.rawValue
    }

    func search(_ query: String, near origin: PlanningPoint?) async throws -> [RecommendedPlace] {
        let matches = try await find(query, near: origin, pointsOfInterestOnly: false, spanMeters: 40000)
        var combined = matches
        do {
            let points = try await find(query, near: origin, pointsOfInterestOnly: true, spanMeters: 40000)
            var seen = Set(combined.map(\.id))
            for point in points where seen.insert(point.id).inserted { combined.append(point) }
        } catch is CancellationError { throw CancellationError() }
        catch { /* Preserve usable results from the first search. */ }
        guard let origin else { return combined }
        return combined.enumerated().sorted { first, second in
            let firstNearby = (first.element.straightLineDistance(from: origin) ?? .infinity) <= 40000
            let secondNearby = (second.element.straightLineDistance(from: origin) ?? .infinity) <= 40000
            return firstNearby == secondNearby ? first.offset < second.offset : firstNearby
        }.map(\.element)
    }

    func recommendations(_ query: String, near origin: PlanningPoint?) async throws -> [RecommendedPlace] {
        try await find(query, near: origin, pointsOfInterestOnly: true, spanMeters: 40000)
    }

    func recommendations(_ query: String, near origin: PlanningPoint, radiusMeters: Double) async throws -> [RecommendedPlace] {
        try await find(query, near: origin, pointsOfInterestOnly: true, spanMeters: radiusMeters * 2)
    }

    private func find(_ query: String, near origin: PlanningPoint?, pointsOfInterestOnly: Bool, spanMeters: Double) async throws -> [RecommendedPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = pointsOfInterestOnly ? [.pointOfInterest] : [.pointOfInterest, .address]
        if let origin {
            request.region = .init(center: .init(latitude: origin.latitude, longitude: origin.longitude),
                                   latitudinalMeters: spanMeters, longitudinalMeters: spanMeters)
        }
        let search = MKLocalSearch(request: request)
        let response: MKLocalSearch.Response
        do {
            response = try await withTaskCancellationHandler {
                try await search.start()
            } onCancel: {
                Task { @MainActor in search.cancel() }
            }
        } catch {
            try Task.checkCancellation()
            if Self.isEmptyResult(error) { return [] }
            throw error
        }
        try Task.checkCancellation()
        var seen: Set<String> = []
        let places = response.mapItems.compactMap { item -> RecommendedPlace? in
            let point = item.placemark.coordinate
            let location = PlanningPoint(latitude: point.latitude, longitude: point.longitude)
            guard TripDiscoveryArea.contains(location, countryCode: item.placemark.isoCountryCode) else { return nil }
            let name = item.name ?? "Selected place"
            let key = item.identifier?.rawValue ?? "\(name.lowercased())|\(point.latitude)|\(point.longitude)"
            guard seen.insert(key).inserted else { return nil }
            let id = identities[key] ?? UUID()
            identities[key] = id
            var place = PlanningPlace(id: id, name: name,
                                      location: location, visitSeconds: 2700, website: item.url)
            place.sourceID = item.identifier.map { "apple:" + $0.rawValue }
            place.address = item.placemark.title
            place.phoneNumber = item.phoneNumber
            place.categories = item.pointOfInterestCategory.map { [$0.rawValue] } ?? []
            let street = [item.placemark.thoroughfare, item.placemark.subThoroughfare]
                .compactMap { $0 }.joined(separator: " ")
            let branchAddress = street.isEmpty ? (item.placemark.subLocality ?? item.placemark.locality) : street
            return RecommendedPlace(place: place, address: place.address, branchAddress: branchAddress)
        }
        return places
    }
}

/// Apple search results remain in the current UI session and can also be viewed on Apple's map.
struct TripRecommendationsMap: View {
    let places: [RecommendedPlace]

    var body: some View {
        Map {
            ForEach(places) { item in
                Marker(item.place.name, coordinate: .init(latitude: item.place.location.latitude,
                                                          longitude: item.place.location.longitude))
            }
        }
        .accessibilityLabel("Recommended places on the map")
    }
}
