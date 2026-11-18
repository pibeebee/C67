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
            results = response.mapItems.prefix(12).map { item in
                var place = PlanningPlace(id: UUID(), name: item.name ?? "Selected place",
                                          location: .init(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude),
                                          visitSeconds: 2700, website: item.url)
                place.address = item.placemark.title
                return place
            }
        } catch is CancellationError { }
        catch {
            guard ticket == generation, !Task.isCancelled, normalizedQuery == text else { return }
            if MapKitTripPlaceSearch.isEmptyResult(error) { results = [] }
            else { searchFailure = "Check your connection or try a different query." }
        }
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
    private(set) var permissionDenied = false
    private var target: CLLocation?
    private var lastRouteLocation: CLLocation?
    private var routeTask: Task<Void, Never>?
    private var goodSamples = 0
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
        location = nil; route = nil; error = nil; arrivalReady = false; permissionDenied = false; goodSamples = 0; lastRouteLocation = nil; lastSampleDate = nil
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.startUpdatingLocation()
        default: permissionDenied = true; error = "Allow location access in Settings to show directions and detect arrival."
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
        case .authorizedAlways, .authorizedWhenInUse: permissionDenied = false; error = nil; manager.startUpdatingLocation()
        case .denied, .restricted: permissionDenied = true; error = "Allow location access in Settings to show directions and detect arrival."
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
