import Foundation
import MapKit
import CoreLocation
import CoreSpotlight
import UniformTypeIdentifiers
import WeatherKit
import FoundationModels
import PocketEngine

struct PlaceHit: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let coordinate: Coordinate
    let item: MKMapItem
}

@MainActor
final class AppleServices: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<Coordinate, Error>?
    private var locationTimeout: Task<Void, Never>?
    private var hourly: [String: Forecast<HourWeather>] = [:]
    private(set) var attribution: WeatherAttribution?
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyHundredMeters }

    func search(_ text: String, area: VisitArea? = nil, extensionMeters: Double = 0) async throws -> [PlaceHit] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.pointOfInterest, .address]
        request.region = MKCoordinateRegion(center: .init(latitude: -6.24, longitude: 106.82), span: .init(latitudeDelta: 0.6, longitudeDelta: 0.7))
        if let area {
            let points = area.geometry.coordinates.flatMap { $0.flatMap { $0 } }
            let latitudes = points.map { $0[1] }, longitudes = points.map { $0[0] }
            if let south = latitudes.min(), let north = latitudes.max(), let west = longitudes.min(), let east = longitudes.max() {
                let padding = extensionMeters / 100_000
                request.region = MKCoordinateRegion(center: .init(latitude: (south + north) / 2, longitude: (west + east) / 2),
                                                    span: .init(latitudeDelta: north - south + 2 * padding, longitudeDelta: east - west + 2 * padding))
            }
        }
        request.regionPriority = .required
        let search = MKLocalSearch(request: request)
        let started = Date()
        let timeout = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(25)) } catch { return }
            search.cancel()
        }
        defer { timeout.cancel() }
        let result = try await withTaskCancellationHandler { try await search.start() } onCancel: { search.cancel() }
        guard Date().timeIntervalSince(started) < 25 else { throw URLError(.timedOut) }
        return result.mapItems.compactMap { item in
            let c = item.location.coordinate
            guard (-6.6 ... -5.9).contains(c.latitude), (106.5 ... 107.2).contains(c.longitude) else { return nil }
            let point = Coordinate(latitude: c.latitude, longitude: c.longitude)
            if let area, !area.permits(point, extensionMeters: extensionMeters) { return nil }
            return PlaceHit(name: item.name ?? "Lokasi", address: item.address?.fullAddress ?? "", coordinate: .init(latitude: c.latitude, longitude: c.longitude), item: item)
        }
    }
    func candidate(_ hit: PlaceHit) -> Venue {
        let category: String?
        switch hit.item.pointOfInterestCategory {
        case .restaurant: category = "restaurant"
        case .cafe: category = "cafe"
        case .bakery: category = "bakery"
        case .movieTheater: category = "cinema"
        case .theater: category = "performance_venue"
        case .museum: category = "museum"
        case .park, .nationalPark: category = "park"
        case .zoo, .aquarium: category = "animal"
        case .library: category = "library"
        default: category = nil
        }
        let id = "apple-session-" + CandidatePool.normalizedName(hit.name) + "-" +
            String(format: "%.5f-%.5f", hit.coordinate.latitude, hit.coordinate.longitude)
        return Venue(id: id, name: hit.name, branch: hit.name, address: hit.address,
                     coordinate: hit.coordinate, categories: category.map { [$0] } ?? [],
                     license: "Apple Maps · hasil sesi", facts: [])
    }
    func currentLocation() async throws -> Coordinate {
        guard locationContinuation == nil else { throw EngineError.invalid("Permintaan lokasi masih berjalan.") }
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            locationTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                self?.finishLocation(.failure(EngineError.invalid("Lokasi belum diterima. Pilih titik awal dari pencarian.")))
            }
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
            default: finishLocation(.failure(EngineError.invalid("Izin lokasi tidak tersedia. Pilih titik awal melalui pencarian Apple Maps.")))
            }
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard locationContinuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted: finishLocation(.failure(EngineError.invalid("Akses lokasi ditolak. Anda tetap dapat memilih titik awal lewat Apple Maps.")))
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let value = locations.last, value.horizontalAccuracy >= 0, abs(value.timestamp.timeIntervalSinceNow) < 120 else { return }
        finishLocation(.success(.init(latitude: value.coordinate.latitude, longitude: value.coordinate.longitude)))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { finishLocation(.failure(error)) }
    private func finishLocation(_ result: Result<Coordinate, Error>) {
        let continuation = locationContinuation; locationContinuation = nil
        locationTimeout?.cancel(); locationTimeout = nil
        continuation?.resume(with: result)
    }
    func route(from: Coordinate, to: Coordinate, at date: Date) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
        request.transportType = .automobile; request.departureDate = date
        let directions = MKDirections(request: request)
        let result = try await withTaskCancellationHandler { try await directions.calculate() } onCancel: { directions.cancel() }
        guard let route = result.routes.first else { throw EngineError.invalid("Apple Maps belum memberikan rute mobil.") }
        return route
    }
    func eta(from: Coordinate, to: Coordinate, at date: Date) async throws -> LegQuote {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
        request.transportType = .automobile; request.departureDate = date
        let directions = MKDirections(request: request)
        do {
            let result = try await withTaskCancellationHandler { try await directions.calculateETA() } onCancel: { directions.cancel() }
            return LegQuote(seconds: result.expectedTravelTime, meters: result.distance)
        } catch let error as MKError where error.code == .loadingThrottled {
            throw TravelQuoteError.throttled
        } catch let error as MKError where error.code == .serverFailure {
            throw TravelQuoteError.temporary(retryAfter: .milliseconds(500))
        } catch let error as URLError where [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code) {
            throw TravelQuoteError.temporary(retryAfter: .milliseconds(500))
        }
    }
    func weather(at point: Coordinate, from start: Date, through end: Date) async throws -> WeatherReading {
        if attribution == nil { attribution = try await WeatherService.shared.attribution }
        let key = "\(point.latitude),\(point.longitude)"
        let forecast: Forecast<HourWeather>
        if let known = hourly[key] { forecast = known }
        else {
            forecast = try await WeatherService.shared.weather(for: CLLocation(latitude: point.latitude, longitude: point.longitude), including: .hourly)
            hourly[key] = forecast
        }
        let rows = forecast.filter { $0.date < end && $0.date.addingTimeInterval(3600) > start }.sorted { $0.date < $1.date }
        var cursor = start
        for row in rows where row.date <= cursor { cursor = max(cursor, row.date.addingTimeInterval(3600)) }
        guard !rows.isEmpty, cursor >= end else { return .init(maxRainChance: nil, summary: "Prakiraan belum mencakup seluruh durasi kunjungan.") }
        let probability = rows.map(\.precipitationChance).max()!
        return .init(maxRainChance: probability, summary: "Peluang hujan tertinggi selama kunjungan: \(Int(probability * 100))%. Sumber: Apple Weather.")
    }
    func resetWeather() { hourly.removeAll() }
}

@MainActor
final class CatalogSearch {
    func index(_ venues: [Venue]) async throws {
        let items = venues.map { venue in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = venue.name
            attributes.contentDescription = ([venue.branch, venue.address] + venue.categories + venue.facts.filter { $0.fresh(at: .now) }.map(\.value)).joined(separator: " ")
            attributes.keywords = venue.categories + venue.aliases
            return CSSearchableItem(uniqueIdentifier: venue.id, domainIdentifier: "giovanchristoffel.c67-pocket", attributeSet: attributes)
        }
        try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: ["giovanchristoffel.c67-pocket"])
        try await CSSearchableIndex.default().indexSearchableItems(items)
    }
    func find(_ text: String) async throws -> [String] {
        let context = CSUserQueryContext()
        context.fetchAttributes = ["title"]; context.maxResultCount = 50; context.enableRankedResults = true
        let query = CSUserQuery(userQueryString: text, userQueryContext: context)
        var ids: [String] = []
        for try await result in query.responses {
            switch result {
            case .item(let value): ids.append(value.item.uniqueIdentifier)
            default: break
            }
        }
        return ids
    }
}

@Generable
struct AppleReasonSelection {
    @Guide(description: "Choose only IDs present in the provided allowedReasonIDs array. Never invent an ID.")
    var reasonIDs: [Int]
}

@MainActor
enum AppleExplanation {
    static var availability: String {
        switch SystemLanguageModel.default.availability {
        case .available: "Model Apple di perangkat tersedia; alasan tetap berasal dari fakta yang diperiksa."
        case .unavailable: "Model Apple belum tersedia pada perangkat atau pengaturan ini."
        }
    }
    static func select(from assessment: Assessment) async throws -> [String] {
        let model = SystemLanguageModel.default
        guard case .available = model.availability, model.supportsLocale(Locale(identifier: "en_US")) else {
            throw EngineError.invalid("Foundation Models belum tersedia dalam bahasa yang didukung.")
        }
        let ids = Array(assessment.reasons.indices)
        let items = zip(ids, assessment.reasonDescriptors).map { ["id": String($0.0), "reason": $0.1] }
        let data = try JSONSerialization.data(withJSONObject: items)
        let prompt = "Select up to three allowedReasonIDs that best explain this recommendation. Prioritize evidence for required activities, then liked activities, then category match. Do not treat an unpersonalized candidate as a verified match. allowedReasonIDs: \(ids). Reasons: " + String(decoding: data, as: UTF8.self)
        let session = LanguageModelSession(instructions: "Select identifiers only. You do not provide venue facts or alter itinerary feasibility.")
        let answer = try await session.respond(to: prompt, generating: AppleReasonSelection.self).content.reasonIDs
        guard !answer.isEmpty, answer.count <= 3, Set(answer).count == answer.count, answer.allSatisfy(ids.contains) else {
            throw EngineError.invalid("Pilihan alasan AI tidak sesuai daftar bukti.")
        }
        return answer.map { assessment.reasons[$0] }
    }
}
