#if canImport(MapKit)
    import Foundation
    @preconcurrency import MapKit
    import WeatherKit
    import C67Domain
    import C67PlannerV5
    import PocketEngine

    @MainActor private final class PocketAppleServices {
        private var forecasts: [Coordinate: (Date, Forecast<HourWeather>)] = [:]
        private var attribution: WeatherAttribution?
        private var weatherRetryAfter: Date?
        private var openForecasts: [Coordinate: (Date, PocketScheduleForecast)] = [:]
        private var openRetryAfter: Date?

        private func hourly(_ point: Coordinate) async throws -> Forecast<HourWeather> {
            if let cached = forecasts[point], Date().timeIntervalSince(cached.0) < 300 { return cached.1 }
            if let retryAfter = weatherRetryAfter, retryAfter > .now { throw URLError(.resourceUnavailable) }
            let forecast = try await WeatherService.shared.weather(
                for: CLLocation(latitude: point.latitude, longitude: point.longitude), including: .hourly)
            if attribution == nil { attribution = try await WeatherService.shared.attribution }
            forecasts[point] = (.now, forecast)
            return forecast
        }

        func scheduleForecast(_ point: PlanningPoint, start: Date, end: Date, direct: Bool) async throws -> PocketScheduleForecast {
            let coordinate = Coordinate(latitude: point.latitude, longitude: point.longitude)
            let window = DateInterval(start: start, end: end)
            var forecast = PocketScheduleForecast()
            do {
                let hours = try await hourly(coordinate).filter { $0.date < end && $0.date.addingTimeInterval(3600) > start }
                if !hours.isEmpty, let evidence = weatherEvidence() {
                    let source = evidence.label
                    let kinds: [PlannerV51WeatherKind] = [.apparentTemperature, .uvIndex]
                    forecast.series = kinds.map { kind in
                        .init(kind: kind, source: source, samples: hours.compactMap { hour in
                            let value = kind == .uvIndex ? Double(hour.uvIndex.value) : hour.apparentTemperature.converted(to: .celsius).value
                            guard value.isFinite, kind != .uvIndex || value >= 0 else { return nil }
                            return .init(interval: .init(start: hour.date, duration: 3600), value: value)
                        })
                    }
                    forecast.rain = hours.compactMap { hour in
                        guard (0 ... 1).contains(hour.precipitationChance) else { return nil }
                        return .init(interval: .init(start: hour.date, duration: 3600), probability: hour.precipitationChance, source: source)
                    }
                    forecast.evidence = [evidence]
                }
            } catch {
                try Task.checkCancellation()
                weatherRetryAfter = .now.addingTimeInterval(60)
            }
            let kinds: [PlannerV51WeatherKind] = direct ? [.apparentTemperature, .uvIndex, .directIrradiance] : [.apparentTemperature, .uvIndex]
            let byKind = Dictionary(uniqueKeysWithValues: forecast.series.map { ($0.kind, $0) })
            let missing = kinds.filter { kind in
                Self.coverage(byKind[kind]?.samples.map(\.interval) ?? [], in: window) < window.duration
            }
            let rainCoverage = Self.coverage(forecast.rain.map(\.interval), in: window)
            guard !missing.isEmpty || rainCoverage < window.duration else { return forecast }
            do {
                let open: PocketScheduleForecast
                if let saved = openForecasts[coordinate], Date().timeIntervalSince(saved.0) < 300 {
                    open = saved.1
                } else {
                    if let retry = openRetryAfter, retry > .now { return forecast }
                    open = try await PocketOpenMeteoScheduleForecast.load(point)
                    openForecasts[coordinate] = (.now, open)
                }
                var usedOpen = false
                for series in open.series where missing.contains(series.kind) {
                    let original = Self.coverage(byKind[series.kind]?.samples.map(\.interval) ?? [], in: window)
                    let samples = series.samples.filter { $0.interval.start < end && $0.interval.end > start }
                    guard Self.coverage(samples.map(\.interval), in: window) > original else { continue }
                    forecast.series.removeAll { $0.kind == series.kind }
                    forecast.series.append(.init(kind: series.kind, source: series.source, samples: samples))
                    usedOpen = true
                }
                let rain = open.rain.filter { $0.interval.start < end && $0.interval.end > start }
                if Self.coverage(rain.map(\.interval), in: window) > rainCoverage {
                    forecast.rain = rain
                    usedOpen = true
                }
                if usedOpen { forecast.evidence += open.evidence }
            } catch {
                try Task.checkCancellation()
                openRetryAfter = .now.addingTimeInterval(60)
            }
            return forecast
        }

        private static func coverage(_ intervals: [DateInterval], in window: DateInterval) -> TimeInterval {
            var cursor = window.start
            var total: TimeInterval = 0
            for interval in intervals.sorted(by: { $0.start < $1.start }) {
                let start = max(interval.start, cursor)
                let end = min(interval.end, window.end)
                guard end > start else { continue }
                total += end.timeIntervalSince(start)
                cursor = end
            }
            return total
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
                let providerError = error as NSError
                if providerError.domain == MKErrorDomain, providerError.code == Int(MKError.Code.loadingThrottled.rawValue) {
                    throw TravelQuoteError.throttled
                }
                throw error
            }
        }

        func weather(at point: Coordinate, start: Date, end: Date) async throws -> WeatherReading {
            do {
                let forecast = try await hourly(point)
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

    }

    public extension PocketPlanningServices {
        @MainActor static func live(connection: any PocketConnectionProviding) -> Self {
            let apple = PocketAppleServices()
            let client = PocketResearchClient(connection: connection)
            var services = Self(travel: { try await apple.travel(from: $0, to: $1, at: $2, mode: $3) },
                         weather: { try await apple.weather(at: $0, start: $1, end: $2) },
                         advise: { try await client.advise($0) }, resolve: { try await client.resolve($0, requestID: $1) },
                         order: { try await client.order($0, requestID: $1) },
                         experience: { try await client.experience($0, requestID: $1) },
                         foundationExperience: { inputs, _ in try await V42FoundationExperience.generate(for: inputs) },
                         hours: { await client.openingHours(placeID: $0) },
                         attribution: { await apple.weatherEvidence() })
            services.scheduleForecast = { try await apple.scheduleForecast($0, start: $1, end: $2, direct: $3) }
            services.batchHours = { try await client.openingHours(placeIDs: $0) }
            return services
        }
    }
#endif
