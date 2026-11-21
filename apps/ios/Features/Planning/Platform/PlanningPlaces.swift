import Foundation
import Observation
@preconcurrency import MapKit
import CoreLocation
import WeatherKit
import C67Domain

/// A departure forecast tied to the selected origin and departure instant.
@MainActor @Observable
final class DepartureWeatherLoader {
    struct Forecast {
        let temperature: Measurement<UnitTemperature>
        let condition: String
        let symbol: String
        let source: String
        let sourceURL: URL
        let markURL: URL?
    }

    enum ForecastFailure: Error {
        case noForecastForDeparture, temporarilyUnavailable
    }

    private(set) var forecast: Forecast?
    private(set) var failure: ForecastFailure?
    private(set) var isLoading = false
    private var generation = 0

    func clear() { generation += 1; forecast = nil; failure = nil; isLoading = false }

    func load(origin: PlanningPoint, departure: Date) async {
        generation += 1
        let ticket = generation
        forecast = nil; failure = nil; isLoading = true
        defer { if ticket == generation { isLoading = false } }
        guard departure >= Date().addingTimeInterval(-3600) else {
            failure = .noForecastForDeparture
            return
        }
        do {
            let start = Date(timeIntervalSince1970: floor(departure.timeIntervalSince1970 / 3600) * 3600)
            let location = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            let hours = try await WeatherService.shared.weather(for: location, including: .hourly(startDate: start, endDate: start.addingTimeInterval(3600)))
            let attribution = try await WeatherService.shared.attribution
            try Task.checkCancellation()
            guard ticket == generation else { return }
            guard let hour = hours.first(where: { $0.date <= departure && departure < $0.date.addingTimeInterval(3600) }) else { throw URLError(.resourceUnavailable) }
            forecast = Forecast(temperature: hour.temperature, condition: hour.condition.description, symbol: hour.symbolName,
                                source: "Apple Weather", sourceURL: attribution.legalPageURL, markURL: attribution.combinedMarkLightURL)
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled, ticket == generation else { return }
            do {
                let value = try await openMeteo(origin: origin, departure: departure)
                guard !Task.isCancelled, ticket == generation else { return }
                forecast = value
            } catch {
                guard !Task.isCancelled, ticket == generation else { return }
                failure = error as? ForecastFailure ?? .temporarilyUnavailable
            }
        }
    }

    private func openMeteo(origin: PlanningPoint, departure: Date) async throws -> Forecast {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [URLQueryItem(name: "latitude", value: String(origin.latitude)),
                                 URLQueryItem(name: "longitude", value: String(origin.longitude)),
                                 URLQueryItem(name: "hourly", value: "temperature_2m,weather_code"),
                                 URLQueryItem(name: "forecast_days", value: "16"),
                                 URLQueryItem(name: "temperature_unit", value: "celsius"),
                                 URLQueryItem(name: "timezone", value: "GMT"),
                                 URLQueryItem(name: "timeformat", value: "unixtime")]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try Self.decodeOpenMeteo(data, departure: departure)
    }

    static func decodeOpenMeteo(_ data: Data, departure: Date) throws -> Forecast {
        struct Response: Decodable {
            struct Units: Decodable {
                let time: String
                let temperature_2m: String
            }
            struct Hourly: Decodable {
                let time: [Double]
                let temperature_2m: [Double?]
                let weather_code: [Int?]
            }
            let hourly: Hourly
            let hourly_units: Units
        }
        let forecast = try JSONDecoder().decode(Response.self, from: data)
        guard forecast.hourly_units.time == "unixtime", forecast.hourly_units.temperature_2m == "°C" else { throw URLError(.cannotParseResponse) }
        let hourly = forecast.hourly
        guard let index = hourly.time.firstIndex(where: { $0 <= departure.timeIntervalSince1970 && departure.timeIntervalSince1970 < $0 + 3600 }) else {
            throw ForecastFailure.noForecastForDeparture
        }
        guard hourly.temperature_2m.indices.contains(index), hourly.weather_code.indices.contains(index),
              let temperature = hourly.temperature_2m[index], temperature.isFinite, let code = hourly.weather_code[index] else { throw URLError(.cannotParseResponse) }
        let (condition, symbol): (String, String) = switch code {
        case 0: ("Clear", "sun.max")
        case 1 ... 3: ("Cloudy", "cloud")
        case 45, 48: ("Fog", "cloud.fog")
        case 51 ... 67, 80 ... 82: ("Rain", "cloud.rain")
        case 71 ... 77, 85, 86: ("Snow", "cloud.snow")
        case 95 ... 99: ("Thunderstorms", "cloud.bolt.rain")
        default: ("Forecast", "cloud.sun")
        }
        return Forecast(temperature: .init(value: temperature, unit: .celsius), condition: condition, symbol: symbol,
                        source: "Open-Meteo", sourceURL: URL(string: "https://open-meteo.com/")!, markURL: nil)
    }
}

@MainActor @Observable
final class PlanningPlaceSearch {
    var query = ""
    private(set) var results: [PlanningPlace] = []
    private(set) var isBusy = false
    private var searchFailure: String?
    private var submittedQuery: String?
    private var normalizedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasSearched: Bool { submittedQuery == normalizedQuery }
    var error: String? { hasSearched ? searchFailure : nil }
    var showsPreviousResults: Bool { !results.isEmpty && (!hasSearched || isBusy || error != nil) }
    private var generation = 0

    func search(near point: PlanningPoint?) async {
        let text = normalizedQuery
        generation += 1
        let ticket = generation
        submittedQuery = text
        searchFailure = nil
        guard !text.isEmpty else { results = []; isBusy = false; return }
        isBusy = true
        defer { if ticket == generation { isBusy = false } }
        let request = MKLocalSearch.Request(); request.naturalLanguageQuery = text
        request.resultTypes = [.address, .pointOfInterest]
        if let point { request.region = MKCoordinateRegion(center: .init(latitude: point.latitude, longitude: point.longitude), latitudinalMeters: 20000, longitudinalMeters: 20000) }
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard ticket == generation, !Task.isCancelled, normalizedQuery == text else { return }
            results = response.mapItems.prefix(12).map(Self.place)
        } catch is CancellationError { }
        catch {
            guard ticket == generation, !Task.isCancelled, normalizedQuery == text else { return }
            if MapKitTripPlaceSearch.isEmptyResult(error) { results = [] }
            else { searchFailure = "Check your connection or try a different query." }
        }
    }

    /// Resolves a typed-ahead suggestion into a place with coordinates.
    func resolve(_ completion: MKLocalSearchCompletion) async throws -> PlanningPlace? {
        let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
        return response.mapItems.first.map(Self.place)
    }

    private static func place(_ item: MKMapItem) -> PlanningPlace {
        var place = PlanningPlace(id: UUID(), name: item.name ?? "Selected place",
                                  location: .init(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude),
                                  visitSeconds: 2700, website: item.url)
        place.address = item.placemark.title
        return place
    }
}

/// Type-ahead place suggestions while the traveller is still typing.
@MainActor @Observable
final class PlanningPlaceCompleter: NSObject, @preconcurrency MKLocalSearchCompleterDelegate {
    private(set) var completions: [MKLocalSearchCompletion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(_ query: String, near point: PlanningPoint?) {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            completer.cancel()
            completions = []
            return
        }
        if let point {
            completer.region = MKCoordinateRegion(center: .init(latitude: point.latitude, longitude: point.longitude),
                                                  latitudinalMeters: 20000, longitudinalMeters: 20000)
        }
        completer.queryFragment = text
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = Array(completer.results.prefix(8))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        completions = []
    }
}

/// Names the point under the map's centre pin.
@MainActor @Observable
final class PlanningPinnedLocation {
    private(set) var point: PlanningPoint?
    private(set) var name: String?
    private(set) var address: String?
    private(set) var isResolving = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let geocoder = CLGeocoder()

    var place: PlanningPlace? {
        guard let point, !isResolving else { return nil }
        var place = PlanningPlace(id: UUID(), name: name ?? String(localized: "Pinned location"),
                                  location: point, visitSeconds: 2700)
        place.address = address
        return place
    }

    /// Uses an already-known place, such as a search result, without another lookup.
    func show(_ place: PlanningPlace) {
        generation += 1
        geocoder.cancelGeocode()
        point = place.location
        name = place.name
        address = place.address
        isResolving = false
    }

    func resolve(_ coordinate: CLLocationCoordinate2D) async {
        let next = PlanningPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let point, Self.distance(point, next) < 15, !isResolving { return }
        generation += 1
        let ticket = generation
        geocoder.cancelGeocode()
        point = next
        isResolving = true
        defer { if ticket == generation { isResolving = false } }
        let mark = try? await geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)).first
        guard ticket == generation, !Task.isCancelled else { return }
        name = mark?.name ?? mark?.thoroughfare
        address = LocationAreaName.format(district: mark?.subLocality, city: mark?.locality, province: mark?.administrativeArea)
    }

    private static func distance(_ first: PlanningPoint, _ second: PlanningPoint) -> CLLocationDistance {
        CLLocation(latitude: first.latitude, longitude: first.longitude)
            .distance(from: CLLocation(latitude: second.latitude, longitude: second.longitude))
    }
}

@MainActor @Observable
final class PlanningLocation: NSObject, @preconcurrency CLLocationManagerDelegate {
    private(set) var point: PlanningPoint?
    private(set) var isRequesting = false
    private(set) var permissionDenied = false
    var error: String?
    @ObservationIgnored private let manager = CLLocationManager()

    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyHundredMeters }
    func request() {
        point = nil; error = nil; isRequesting = true
        permissionDenied = false
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default:
            isRequesting = false
            permissionDenied = true
            error = "Location is unavailable. Choose a starting point with place search."
        }
    }
    func cancel() { isRequesting = false; manager.stopUpdatingLocation() }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isRequesting else { return }
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
        else if manager.authorizationStatus != .notDetermined {
            isRequesting = false; permissionDenied = true
            error = "Location permission was not granted. Choose a starting point manually."
        }
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

enum LocationAreaName {
    static func shortName(_ name: String) -> String {
        name.split(separator: ",", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? name
    }
    static func format(district: String?, city: String?, province: String?) -> String? {
        let parts = [district, city, province].compactMap { value -> String? in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        var unique: [String] = []
        for part in parts where !unique.contains(where: { $0.localizedCaseInsensitiveCompare(part) == .orderedSame }) {
            unique.append(part)
        }
        let result = unique.prefix(2).joined(separator: ", ")
        return result.isEmpty ? nil : result
    }

    @MainActor static func resolve(_ point: PlanningPoint) async -> String? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first, !Task.isCancelled else { return nil }
        return format(district: placemark.subLocality, city: placemark.locality ?? placemark.subAdministrativeArea,
                      province: placemark.administrativeArea)
    }
}

enum PlanningDirections {
    @MainActor static func open(_ stop: ScheduledPlanningStop, mode: PlanningMode) {
        open(stop.location, name: stop.name, mode: mode)
    }

    @MainActor static func open(_ point: PlanningPoint, name: String, mode: PlanningMode) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: point.latitude, longitude: point.longitude)))
        item.name = name
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
    private(set) var permissionDenied = false
    private var target: CLLocation?
    private var lastRouteLocation: CLLocation?
    private var routeTask: Task<Void, Never>?
    private var arrivalSamples: [CLLocation] = []
    private var lastSampleDate: Date?
    private var generation = 0
    private var mode: PlanningMode = .automobile
    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .automotiveNavigation
    }

    func start(to point: PlanningPoint, mode: PlanningMode = .automobile) {
        stop()
        self.mode = mode
        manager.activityType = mode == .walking ? .otherNavigation : .automotiveNavigation
        target = CLLocation(latitude: point.latitude, longitude: point.longitude)
        location = nil; route = nil; error = nil; arrivalReady = false; permissionDenied = false; arrivalSamples = []; lastRouteLocation = nil; lastSampleDate = nil
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.startUpdatingLocation()
        default: permissionDenied = true; error = "Allow location access in Settings to show directions and detect arrival."
        }
    }

    func stop() {
        generation += 1
        manager.stopUpdatingLocation()
        routeTask?.cancel()
        routeTask = nil
        target = nil
        arrivalSamples = []
        arrivalReady = false
    }

    func canConfirmArrival(at point: PlanningPoint, now: Date = .now) -> Bool {
        guard let target, target.coordinate.latitude == point.latitude, target.coordinate.longitude == point.longitude,
              manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else { return false }
        return arrivalSamples.count == 2 && arrivalSamples.allSatisfy { Self.isArrivalSample($0, target: target, now: now) }
    }
    static func isArrivalSample(_ current: CLLocation, target: CLLocation, now: Date = .now) -> Bool {
        current.horizontalAccuracy >= 0 && current.horizontalAccuracy <= 50 &&
            abs(current.timestamp.timeIntervalSince(now)) < 20 &&
            current.distance(from: target) + current.horizontalAccuracy <= 100
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard target != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: permissionDenied = false; error = nil; manager.startUpdatingLocation()
        case .denied, .restricted:
            arrivalSamples = []
            arrivalReady = false
            permissionDenied = true
            error = "Allow location access in Settings to show directions and detect arrival."
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
            arrivalSamples = Array(arrivalSamples.filter { Self.isArrivalSample($0, target: target) }.suffix(1)) + [current]
            arrivalReady = arrivalSamples.count == 2
        } else {
            arrivalSamples = []
            arrivalReady = false
        }
        guard routeTask == nil, lastRouteLocation == nil || current.distance(from: lastRouteLocation!) >= 250 else { return }
        lastRouteLocation = current
        let ticket = generation
        routeTask = Task {
            defer { if ticket == generation { routeTask = nil } }
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: current.coordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: target.coordinate))
            request.transportType = mode == .walking ? .walking : .automobile
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

/// Places recently chosen in the place picker, kept on this device for the signed-in account only.
///
/// Entries are tagged with the account that chose them. A different account (or signing out)
/// never sees them; the stale list is erased the next time it is read or written.
@MainActor
enum PlanningRecentPlaces {
    static let limit = 5
    /// The account whose recents may be shown; `nil` when nobody is signed in (including mock mode).
    static var owner: UUID?
    private static let key = "io.pibeebee.c67.recentPlaces.v1"
    private static let duplicateDistance: CLLocationDistance = 30

    private struct Stored: Codable {
        var owner: UUID?
        var places: [PlanningPlace]
    }

    static func load(from defaults: UserDefaults = .standard) -> [PlanningPlace] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return [] }
        guard stored.owner == owner else {
            defaults.removeObject(forKey: key)
            return []
        }
        return stored.places
    }

    /// Moves `place` to the top, replacing an earlier entry at nearly the same spot.
    static func record(_ place: PlanningPlace, in defaults: UserDefaults = .standard) {
        let point = CLLocation(latitude: place.location.latitude, longitude: place.location.longitude)
        var places = load(from: defaults).filter { existing in
            CLLocation(latitude: existing.location.latitude, longitude: existing.location.longitude)
                .distance(from: point) > duplicateDistance
        }
        places.insert(place, at: 0)
        save(Array(places.prefix(limit)), in: defaults)
    }

    static func remove(_ place: PlanningPlace, in defaults: UserDefaults = .standard) {
        save(load(from: defaults).filter { $0.id != place.id }, in: defaults)
    }

    static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    private static func save(_ places: [PlanningPlace], in defaults: UserDefaults) {
        guard !places.isEmpty else { return clear(in: defaults) }
        guard let data = try? JSONEncoder().encode(Stored(owner: owner, places: places)) else { return }
        defaults.set(data, forKey: key)
    }
}
