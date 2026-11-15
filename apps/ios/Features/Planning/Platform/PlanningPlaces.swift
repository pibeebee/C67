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

/// Foreground location and route state for the currently visible trip.
@MainActor @Observable
final class TripNavigation: NSObject, @preconcurrency CLLocationManagerDelegate {
    private(set) var location: CLLocation?
    private(set) var route: MKRoute?
    private(set) var error: String?
    private(set) var arrivalReady = false
    private var target: CLLocation?
    private var lastRouteLocation: CLLocation?
    private var routeTask: Task<Void, Never>?
    private var goodSamples = 0
    private var lastSampleDate: Date?
    private var generation = 0
    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .automotiveNavigation
    }

    func start(to point: PlanningPoint) {
        stop()
        target = CLLocation(latitude: point.latitude, longitude: point.longitude)
        location = nil; route = nil; error = nil; arrivalReady = false; goodSamples = 0; lastRouteLocation = nil; lastSampleDate = nil
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.startUpdatingLocation()
        default: error = "Allow location access in Settings to show directions and detect arrival."
        }
    }

    func stop() { generation += 1; manager.stopUpdatingLocation(); routeTask?.cancel(); routeTask = nil; target = nil }
    static func isArrivalSample(_ current: CLLocation, target: CLLocation, now: Date = .now) -> Bool {
        current.horizontalAccuracy >= 0 && current.horizontalAccuracy <= 50 &&
            abs(current.timestamp.timeIntervalSince(now)) < 20 &&
            current.distance(from: target) + current.horizontalAccuracy <= 100
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard target != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.startUpdatingLocation()
        case .denied, .restricted: error = "Allow location access in Settings to show directions and detect arrival."
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let target, let current = locations.last, current.horizontalAccuracy >= 0,
              abs(current.timestamp.timeIntervalSinceNow) < 20 else { return }
        location = current
        guard lastSampleDate.map({ current.timestamp > $0 }) ?? true else { return }
        lastSampleDate = current.timestamp
        if Self.isArrivalSample(current, target: target) {
            goodSamples += 1
            if goodSamples >= 2 { arrivalReady = true }
        } else { goodSamples = 0 }
        guard routeTask == nil, lastRouteLocation == nil || current.distance(from: lastRouteLocation!) >= 250 else { return }
        lastRouteLocation = current
        let ticket = generation
        routeTask = Task {
            defer { if ticket == generation { routeTask = nil } }
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: current.coordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: target.coordinate))
            request.transportType = .automobile
            let directions = MKDirections(request: request)
            do {
                let response = try await withTaskCancellationHandler { try await directions.calculate() } onCancel: { directions.cancel() }
                guard !Task.isCancelled, ticket == generation else { return }
                route = response.routes.first
                error = route == nil ? "Directions are unavailable. Try again." : nil
            } catch { if !Task.isCancelled, ticket == generation { self.error = "Directions are unavailable. Try again."; lastRouteLocation = nil } }
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        self.error = "Current location is unavailable. Check your location settings."
    }
}
