import Foundation
import Observation
@preconcurrency import MapKit
import CoreLocation
import C67Domain

@MainActor @Observable
final class PlanningPlaceSearch {
    var query = ""
    private(set) var results: [PlanningPlace] = []
    private(set) var isBusy = false
    var error: String?
    private var generation = 0

    func search(near point: PlanningPoint?) async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { results = []; return }
        generation += 1; let ticket = generation; isBusy = true; error = nil
        defer { if ticket == generation { isBusy = false } }
        let request = MKLocalSearch.Request(); request.naturalLanguageQuery = text
        request.resultTypes = [.address, .pointOfInterest]
        if let point { request.region = MKCoordinateRegion(center: .init(latitude: point.latitude, longitude: point.longitude), latitudinalMeters: 20000, longitudinalMeters: 20000) }
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard ticket == generation, !Task.isCancelled else { return }
            results = response.mapItems.prefix(12).map { item in
                .init(id: UUID(), name: item.name ?? "Selected place",
                      location: .init(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude),
                      visitSeconds: 2700, website: item.url)
            }
        } catch is CancellationError { }
        catch { if ticket == generation { self.error = "Place search is unavailable. Try another query." } }
    }
}

@MainActor @Observable
final class PlanningLocation: NSObject, @preconcurrency CLLocationManagerDelegate {
    private(set) var point: PlanningPoint?
    private(set) var isRequesting = false
    var error: String?
    @ObservationIgnored private let manager = CLLocationManager()

    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyHundredMeters }
    func request() {
        point = nil; error = nil; isRequesting = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default: isRequesting = false; error = "Location is unavailable. Choose a starting point with place search."
        }
    }
    func cancel() { isRequesting = false; manager.stopUpdatingLocation() }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isRequesting else { return }
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
        else if manager.authorizationStatus != .notDetermined { isRequesting = false; error = "Location permission was not granted. Choose a starting point manually." }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRequesting else { return }; isRequesting = false
        guard let location = locations.last, location.horizontalAccuracy >= 0, abs(location.timestamp.timeIntervalSinceNow) <= 30 else { error = "A current position was not available. Try again or search manually."; return }
        point = .init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        guard isRequesting else { return }; isRequesting = false; self.error = "Your position could not be obtained. Choose a starting point manually."
    }
}

enum PlanningDirections {
    @MainActor static func open(_ stop: ScheduledPlanningStop, mode: PlanningMode) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: stop.location.latitude, longitude: stop.location.longitude)))
        item.name = stop.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mode == .walking ? MKLaunchOptionsDirectionsModeWalking : MKLaunchOptionsDirectionsModeDriving])
    }
}
