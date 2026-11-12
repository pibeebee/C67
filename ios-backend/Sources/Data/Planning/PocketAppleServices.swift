#if canImport(MapKit)
    import Foundation
    @preconcurrency import MapKit
    import WeatherKit
    import C67Domain
    import PocketEngine

    @MainActor private final class PocketAppleServices {
        private var forecasts: [Coordinate: (Date, Forecast<HourWeather>)] = [:]
        private var attribution: WeatherAttribution?
        private var weatherRetryAfter: Date?

        func discover(profile: Profile, area: VisitArea) async throws -> [Venue] {
            let queries = profile.interests.isEmpty ? ["restaurant", "park", "museum"] : profile.interests.sorted()
            var venues: [Venue] = []
            var successful = 0
            for interest in queries.prefix(8) {
                try Task.checkCancellation()
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = profile.query(for: interest)
                request.resultTypes = [.pointOfInterest]
                let coordinates = area.geometry.coordinates.flatMap { $0.flatMap { $0 } }
                let latitude = coordinates.map { $0[1] }, longitude = coordinates.map { $0[0] }
                if let south = latitude.min(), let north = latitude.max(), let west = longitude.min(), let east = longitude.max() {
                    request.region = .init(center: .init(latitude: (south + north) / 2, longitude: (west + east) / 2),
                                           span: .init(latitudeDelta: north - south, longitudeDelta: east - west))
                }
                if #available(iOS 18, macOS 15, *) { request.regionPriority = .required }
                let search = MKLocalSearch(request: request)
                let timeout = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(25)) } catch { return }
                    search.cancel()
                }
                defer { timeout.cancel() }
                do {
                    let response = try await withTaskCancellationHandler { try await search.start() } onCancel: {
                        Task { @MainActor in search.cancel() }
                    }
                    successful += 1
                    for item in response.mapItems {
                        let point = Self.coordinate(item)
                        guard area.contains(point) else { continue }
                        let name = item.name ?? "Selected place"
                        let id = "apple-session-" + CandidatePool.normalizedName(name) + String(format: "-%.5f-%.5f", point.latitude, point.longitude)
                        venues.append(Venue(id: id, name: name, branch: name, address: Self.address(item), coordinate: point,
                                            categories: Self.category(item.pointOfInterestCategory, name: name).map { [$0] } ?? [], license: "Apple Maps · current search session"))
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { try Task.checkCancellation() }
            }
            guard successful > 0 else { throw PlanningError.unavailable }
            return venues
        }

        func travel(from: Coordinate, to: Coordinate, at date: Date, mode: C67Domain.PlanningMode) async throws -> LegQuote {
            let request = MKDirections.Request()
            request.source = Self.item(from); request.destination = Self.item(to)
            request.transportType = mode == .walking ? .walking : .automobile
            request.departureDate = date
            let directions = MKDirections(request: request)
            let timeout = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(25)) } catch { return }
                directions.cancel()
            }
            defer { timeout.cancel() }
            do {
                let quote = try await withTaskCancellationHandler { try await directions.calculateETA() } onCancel: {
                    Task { @MainActor in directions.cancel() }
                }
                return .init(seconds: quote.expectedTravelTime, meters: quote.distance)
            } catch {
                try Task.checkCancellation()
                throw error
            }
        }

        func weather(at point: Coordinate, start: Date, end: Date) async throws -> WeatherReading {
            do {
                let forecast: Forecast<HourWeather>
                if let cached = forecasts[point], Date().timeIntervalSince(cached.0) < 300 { forecast = cached.1 }
                else {
                    if let retryAfter = weatherRetryAfter, retryAfter > .now {
                        return .init(maxRainChance: nil, summary: "Weather unavailable; no forecast was invented.")
                    }
                    forecast = try await WeatherService.shared.weather(for: CLLocation(latitude: point.latitude, longitude: point.longitude), including: .hourly)
                    forecasts[point] = (.now, forecast)
                }
                // Do not publish weather data without the corresponding attribution.
                if attribution == nil { attribution = try await WeatherService.shared.attribution }
                let rows = forecast.filter { $0.date < end && $0.date.addingTimeInterval(3600) > start }.sorted { $0.date < $1.date }
                var cursor = start
                for row in rows where row.date <= cursor { cursor = max(cursor, row.date.addingTimeInterval(3600)) }
                guard !rows.isEmpty, cursor >= end else { return .init(maxRainChance: nil, summary: "Forecast does not cover the full visit.") }
                return .init(maxRainChance: rows.map(\.precipitationChance).max(), summary: "Apple Weather: maximum rain chance \(Int((rows.map(\.precipitationChance).max() ?? 0) * 100))% during the visit.")
            } catch {
                try Task.checkCancellation()
                // A shared auth/network failure can otherwise repeat for every coordinate and option.
                weatherRetryAfter = .now.addingTimeInterval(60)
                return .init(maxRainChance: nil, summary: "Weather unavailable; no forecast was invented.")
            }
        }

        func weatherEvidence() -> PlanningEvidence? {
            guard let attribution else { return nil }
            return .init(id: "apple-weather", label: attribution.serviceName, url: attribution.legalPageURL,
                         checkedAt: .now, kind: "weather", summary: "Apple Weather and data sources", synthetic: false,
                         attributionLogoURL: attribution.combinedMarkLightURL)
        }

        private static func item(_ point: Coordinate) -> MKMapItem {
            #if compiler(>=6.2)
                if #available(iOS 26, macOS 26, *) { return MKMapItem(location: CLLocation(latitude: point.latitude, longitude: point.longitude), address: nil) }
            #endif
            return MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: point.latitude, longitude: point.longitude)))
        }
        private static func coordinate(_ item: MKMapItem) -> Coordinate {
            #if compiler(>=6.2)
                if #available(iOS 26, macOS 26, *) { return .init(latitude: item.location.coordinate.latitude, longitude: item.location.coordinate.longitude) }
            #endif
            return .init(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
        }
        private static func address(_ item: MKMapItem) -> String {
            #if compiler(>=6.2)
                if #available(iOS 26, macOS 26, *) { return item.address?.fullAddress ?? "" }
            #endif
            return item.placemark.title ?? ""
        }
        private static func category(_ value: MKPointOfInterestCategory?, name: String) -> String? {
            // Some live .park results in the pilot are parking lots or named homes.
            // Require a park-like name for Apple-only matches; this is not access evidence.
            let words = CandidatePool.normalizedName(name).split(separator: " ").map(String.init)
            let parkWords: Set<String> = ["park", "taman", "rptra", "garden", "kebun", "hutan", "rimba", "forest"]
            let conflictingWords: Set<String> = ["parkir", "parking", "rumah", "residence", "apartment", "apartemen"]
            let parkLike = !parkWords.isDisjoint(with: words) && conflictingWords.isDisjoint(with: words)
            return
            switch value {
            case .restaurant: "restaurant"
            case .cafe: "cafe"
            case .bakery: "bakery"
            case .museum: "museum"
            case .park: parkLike ? "park" : nil
            case .nationalPark: "park"
            case .zoo, .aquarium: "animal"
            case .library: "library"
            case .movieTheater: "cinema"
            case .theater: "performance_venue"
            default: nil
            }
        }
    }

    public extension PocketPlanningServices {
        @MainActor static func live(connection: any PocketConnectionProviding) -> Self {
            let apple = PocketAppleServices()
            let client = PocketCatalogClient(connection: connection)
            return .init(catalog: { try await client.catalog() },
                         discover: { try await apple.discover(profile: $0, area: $1) },
                         travel: { try await apple.travel(from: $0, to: $1, at: $2, mode: $3) },
                         weather: { try await apple.weather(at: $0, start: $1, end: $2) },
                         advise: { try await client.advise($0) }, attribution: { await apple.weatherEvidence() })
        }
    }
#endif
