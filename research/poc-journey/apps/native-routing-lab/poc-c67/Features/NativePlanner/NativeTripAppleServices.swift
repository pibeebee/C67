import CoreLocation
import Foundation
import MapKit
import OSLog
import WeatherKit

@MainActor final class NativeTripAppleServices {
    private static let searchLog = Logger(
        subsystem: "giovanchristoffel.poc-c67", category: "NativePlaceSearch")
    private(set) var searchAttempts: [NativeTripSearchAttempt] = []
    private var search: MKLocalSearch?
    private var directions: MKDirections?
    private var cache: [String: NativeTripETA] = [:]
    private var throttled = false
    private static var nextETARequest = Date.distantPast
    private(set) var directionRequests = 0
    private(set) var attribution: WeatherAttribution?
    private let openMeteo = NativeTripOpenMeteoClient()
    private let simulated: Bool
    private let requestLimit: Int
    var remainingETARequests: Int { max(0, requestLimit - directionRequests) }
    var canRequestETA: Bool { remainingETARequests > 0 && !throttled }
    let logs: NativeTripLogStore
    let operationID: String

    init(
        logs: NativeTripLogStore? = nil, operationID: String = UUID().uuidString,
        requestLimit: Int = 96, simulated: Bool = false
    ) {
        self.simulated = simulated
        self.logs = logs ?? .shared
        self.requestLimit = min(1024, max(16, requestLimit))
        self.operationID = operationID
    }

    func event(
        _ name: String, category: String = "mapkit", level: String = "info",
        fields: [String: String] = [:]
    ) {
        logs.record(name, category: category, level: level, operationID: operationID, fields: fields)
    }

    func resetRun() {
        cancel()
        cache = [:]
        throttled = false
        directionRequests = 0
        attribution = nil
    }
    func cancel() {
        if search != nil || directions != nil {
            event(
                "service.cancel_requested",
                fields: ["search": String(search != nil), "directions": String(directions != nil)])
        }
        search?.cancel()
        directions?.cancel()
        search = nil
        directions = nil
    }

    func searchPlaces(_ query: String, region: NativeTripSearchRegion? = nil) async throws
        -> [NativeTripMatch]
    {
        let started = Date()
        let requestID = UUID().uuidString
        event(
            "search.requested",
            fields: [
                "requestID": requestID, "query": query, "region": region?.label ?? "none",
                "timeoutSeconds": "35",
                "regionCenter": region.map { "\($0.latitude),\($0.longitude) radius=\($0.radiusMeters)m" }
                    ?? "none",
            ])
        do {
            try Task.checkCancellation()
            try await NativeTripSearchPacing.wait()
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if let region {
                request.region = MKCoordinateRegion(
                    center: .init(latitude: region.latitude, longitude: region.longitude),
                    latitudinalMeters: region.radiusMeters * 2, longitudinalMeters: region.radiusMeters * 2)
            }
            let operation = MKLocalSearch(request: request)
            search?.cancel()
            search = operation
            defer { if search === operation { search = nil } }
            var deadlineExpired = false
            let timeout = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(35)) } catch { return }
                guard !Task.isCancelled else { return }
                deadlineExpired = true
                operation.cancel()
            }
            defer { timeout.cancel() }
            let response: MKLocalSearch.Response
            do { response = try await operation.start() } catch {
                try Task.checkCancellation()
                throw NativeTripLookupFailure.classify(error, deadlineExpired: deadlineExpired)
            }
            try Task.checkCancellation()
            let matches = response.mapItems.prefix(10).enumerated().map { index, item in
                let coordinate: CLLocationCoordinate2D
                let address: String
                if #available(iOS 26.0, *) {
                    coordinate = item.location.coordinate
                    address = item.address?.fullAddress ?? ""
                } else {
                    coordinate = item.placemark.coordinate
                    address = item.placemark.title ?? ""
                }
                return NativeTripMatch(
                    id: "\(index):\(coordinate.latitude):\(coordinate.longitude)", name: item.name ?? query,
                    address: address, latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
            searchAttempts.append(
                .init(
                    query: query, region: region?.label ?? "Tanpa petunjuk area",
                    elapsed: Date().timeIntervalSince(started), result: "\(matches.count) hasil",
                    diagnostic: nil))
            event(
                "search.completed",
                fields: [
                    "requestID": requestID, "elapsedSeconds": String(Date().timeIntervalSince(started)),
                    "resultCount": String(matches.count),
                ])
            logs.recordJSON(
                "search.candidates", category: "mapkit", operationID: operationID, value: matches)
            Self.searchLog.debug(
                "Search completed: results=\(matches.count), seconds=\(Date().timeIntervalSince(started))")
            return matches
        } catch {
            if error is CancellationError || Task.isCancelled {
                event(
                    "search.cancelled",
                    fields: [
                        "requestID": requestID, "elapsedSeconds": String(Date().timeIntervalSince(started)),
                    ])
                throw CancellationError()
            }
            let failure = NativeTripLookupFailure.classify(error)
            NativeTripSearchPacing.record(failure)
            event(
                "search.failed", level: "error",
                fields: [
                    "requestID": requestID, "elapsedSeconds": String(Date().timeIntervalSince(started)),
                    "classification": failure.kind.rawValue, "domain": failure.domain,
                    "code": String(failure.code), "underlying": failure.diagnostic,
                    "description": failure.detail,
                ])
            searchAttempts.append(
                .init(
                    query: query, region: region?.label ?? "Tanpa petunjuk area",
                    elapsed: Date().timeIntervalSince(started), result: failure.kind.rawValue,
                    diagnostic: failure.diagnostic))
            Self.searchLog.error(
                "Search failed: kind=\(failure.kind.rawValue, privacy: .public), domain=\(failure.domain, privacy: .public), code=\(failure.code), seconds=\(Date().timeIntervalSince(started))"
            )
            if failure.kind == .noResults { return [] }
            throw failure
        }
    }

    static func mapItem(_ point: NativeTripPoint) -> MKMapItem {
        let coordinate = point.coordinate!
        let item: MKMapItem
        if #available(iOS 26.0, *) {
            item = MKMapItem(
                location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                address: nil)
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        }
        item.name = point.title
        return item
    }

    func options(
        from: NativeTripPoint, to: NativeTripPoint, departure: Date, draft: NativeTripDraft,
        retryUnavailable: Bool = false
    ) async throws -> [NativeTripETA] {
        var options: [NativeTripETA] = []
        for mode in draft.modes {
            try Task.checkCancellation()
            var value = try await eta(
                from: from, to: to, departure: departure, mode: mode,
                retryUnavailable: retryUnavailable && mode != .transit)
            if mode == .walking, let seconds = value.seconds,
               seconds > Double(draft.maximumWalkingMinutes * 60), value.usable
            {
                value.status = "excluded_by_walking_limit"
                value.note =
                    "ETA berjalan \(Int(ceil(seconds / 60))) menit melebihi batas \(draft.maximumWalkingMinutes) menit per ruas. Tidak dipilih otomatis."
            }
            if value.status == "timed_out", canRequestETA {
                event(
                    "eta.retrying",
                    fields: [
                        "from": from.id, "to": to.id, "mode": mode.rawValue,
                        "reason": "timeout", "attempt": "2",
                    ])
                value = try await eta(
                    from: from, to: to, departure: departure, mode: mode,
                    retryUnavailable: true)
                if mode == .walking, let seconds = value.seconds,
                   seconds > Double(draft.maximumWalkingMinutes * 60), value.usable
                {
                    value.status = "excluded_by_walking_limit"
                    value.note = "ETA berjalan melebihi batas yang dipilih; tidak dipilih otomatis."
                }
            }
            event(
                "route.option",
                fields: [
                    "from": from.id, "to": to.id, "mode": mode.rawValue, "status": value.status,
                    "note": value.note,
                ])
            options.append(value)
        }
        return options
    }

    private func eta(
        from: NativeTripPoint, to: NativeTripPoint, departure: Date, mode: NativeTripMode,
        retryUnavailable: Bool = false
    ) async throws -> NativeTripETA {
        let key =
            "\(from.id)>\(to.id):\(mode.rawValue):\(mode == .walking ? 0 : departure.timeIntervalSince1970)"
        var value = NativeTripETA(id: key, mode: mode, status: "unavailable", note: "")
        let requestID = UUID().uuidString
        let started = Date()
        var errorDetails: [String: String] = [:]
        var source = "provider"
        event(
            "eta.requested",
            fields: [
                "requestID": requestID, "from": from.title, "to": to.title,
                "fromCoordinate": "\(from.latitude!),\(from.longitude!)",
                "toCoordinate": "\(to.latitude!),\(to.longitude!)", "mode": mode.rawValue,
                "departure": departure.ISO8601Format(), "timeoutSeconds": "25",
            ])
        defer {
            event(
                "eta.result", level: value.usable || Task.isCancelled ? "info" : "warning",
                fields: errorDetails.merging([
                    "requestID": requestID, "source": source,
                    "elapsedSeconds": String(Date().timeIntervalSince(started)),
                    "status": Task.isCancelled ? "cancelled" : value.status,
                    "seconds": value.seconds.map(String.init(describing:)) ?? "unknown",
                    "distance": value.distance.map(String.init(describing:)) ?? "unknown",
                    "expectedDeparture": value.expectedDeparture?.ISO8601Format() ?? "unknown",
                    "expectedArrival": value.expectedArrival?.ISO8601Format() ?? "unknown",
                    "note": value.note,
                ]) { _, new in new })
        }
        if retryUnavailable, let saved = cache[key], !saved.usable,
           !["throttled", "request_limit"].contains(saved.status)
        {
            cache[key] = nil
            event("eta.retry", fields: ["from": from.title, "to": to.title, "mode": mode.rawValue])
        }
        if var saved = cache[key] {
            if mode == .walking, let seconds = saved.seconds {
                saved.expectedDeparture = departure
                saved.expectedArrival = departure.addingTimeInterval(seconds)
            }
            source = "cache"
            value = saved
            return value
        }
        if from.latitude == to.latitude && from.longitude == to.longitude {
            source = "same_coordinate"
            value.seconds = 0
            value.distance = 0
            value.status = "available"
            value.expectedDeparture = departure
            value.expectedArrival = departure
            value.note =
                "Titik pilihan sama. Aktivitas tetap terpisah; periksa apakah salah satunya hanya referensi area."
            return value
        }
        guard directionRequests < requestLimit, !throttled else {
            value.status = throttled ? "throttled" : "request_limit"
            value.note = "Permintaan MapKit dibatasi. Tidak mengisi durasi pengganti."
            return value
        }
        if simulated {
            source = "simulation"
            directionRequests += 1
            value.seconds = NativeTripActiveSimulation.seconds(from: from.id, to: to.id)
            value.status = "available"
            value.expectedDeparture = departure
            value.expectedArrival = departure.addingTimeInterval(value.seconds!)
            value.note = "ETA sintetis eksplisit; bukan data MapKit."
            cache[key] = value
            return value
        }
        let reserved = max(Date(), Self.nextETARequest)
        Self.nextETARequest = reserved.addingTimeInterval(1.2)
        let delay = max(0, reserved.timeIntervalSinceNow)
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
        directionRequests += 1
        let request = MKDirections.Request()
        request.source = Self.mapItem(from)
        request.destination = Self.mapItem(to)
        switch mode {
        case .walking: request.transportType = .walking
        case .transit: request.transportType = .transit
        case .automobile: request.transportType = .automobile
        }
        request.departureDate = departure
        let operation = MKDirections(request: request)
        directions = operation
        defer { if directions === operation { directions = nil } }
        var deadlineExpired = false
        let timeout = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(25)) } catch { return }
            if !Task.isCancelled {
                deadlineExpired = true
                operation.cancel()
            }
        }
        defer { timeout.cancel() }
        do {
            // Apple's transit transport type supports ETA only, not calculate() route geometry/steps.
            let response = try await operation.calculateETA()
            try Task.checkCancellation()
            event(
                "eta.provider_response",
                fields: [
                    "requestID": requestID, "transportType": String(response.transportType.rawValue),
                    "expectedTravelSeconds": String(response.expectedTravelTime),
                    "expectedDeparture": response.expectedDepartureDate.ISO8601Format(),
                    "expectedArrival": response.expectedArrivalDate.ISO8601Format(),
                    "distance": String(response.distance),
                ])
            guard response.transportType.contains(request.transportType),
                  response.expectedTravelTime.isFinite, response.expectedTravelTime >= 0
            else {
                value.note = "MapKit tidak mengembalikan estimasi yang cocok dengan moda yang diminta."
                cache[key] = value
                return value
            }
            if mode == .transit,
               response.expectedArrivalDate < departure
               || response.expectedDepartureDate < departure.addingTimeInterval(-60)
            {
                value.note = "ETA transit tidak mencakup waktu keberangkatan yang diminta."
                cache[key] = value
                return value
            }
            let seconds =
                mode == .transit
                    ? max(
                        response.expectedTravelTime, response.expectedArrivalDate.timeIntervalSince(departure))
                    : response.expectedTravelTime
            value.seconds = seconds
            value.distance = response.distance
            value.status = "available"
            value.expectedDeparture = mode == .transit ? response.expectedDepartureDate : departure
            value.expectedArrival = departure.addingTimeInterval(seconds)
            switch mode {
            case .walking:
                value.note =
                    "Estimasi berjalan MapKit; kondisi cuaca tidak ditambahkan sebagai keterlambatan buatan."
            case .transit:
                value.note =
                    "Estimasi MapKit untuk waktu yang diminta; bukan jadwal kereta, nama jalur, atau rincian transfer yang diverifikasi. Waktu tunggu awal yang tercermin di ETA dihitung satu kali."
            case .automobile:
                value.note =
                    "Estimasi mobil MapKit pada waktu yang diminta. Belum termasuk mencari kendaraan, parkir atau berjalan dari parkir; bukan ETA motor atau transit."
            }
        } catch {
            errorDetails = NativeTripLogStore.errorFields(error)
            try Task.checkCancellation()
            if deadlineExpired || NativeTripLookupFailure.classify(error).kind == .timedOut {
                value.status = "timed_out"
            }
            if let error = error as? MKError, error.code == .directionsNotFound {
                value.status = "directions_not_available"
            }
            if let error = error as? MKError, error.code == .loadingThrottled {
                throttled = true
                value.status = "throttled"
            }
            value.note = "MapKit belum memberi ETA: \(error.localizedDescription)"
        }
        cache[key] = value
        return value
    }

    func forecasts(points: [NativeTripPoint], draft: NativeTripDraft, progress: (String) -> Void)
        async throws -> [NativeTripForecast]
    {
        if simulated { return [] }
        attribution = nil
        let day =
            draft.calendar.dateComponents(
                [.day], from: draft.calendar.startOfDay(for: .now),
                to: draft.calendar.startOfDay(for: draft.departure)
            ).day ?? 99
        var attributionFailure: String?
        if !draft.isJakartaProfile, (0 ... 9).contains(day), !points.isEmpty {
            event(
                "weather.attribution_requested", category: "weather", fields: ["provider": "weatherkit"])
            do {
                attribution = try await WeatherService.shared.attribution
                try Task.checkCancellation()
            } catch {
                try Task.checkCancellation()
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }
                event(
                    "weather.attribution_failed", category: "weather", level: "error",
                    fields: NativeTripLogStore.errorFields(error).merging(["provider": "weatherkit"]) {
                        _, new in new
                    })
                attributionFailure = "Atribusi WeatherKit belum tersedia: \(error.localizedDescription)"
            }
        }
        var groups: [String: NativeTripForecast] = [:]
        var output: [NativeTripForecast] = []
        for (index, point) in points.enumerated() {
            try Task.checkCancellation()
            progress("Cuaca \(index + 1)/\(points.count)")
            guard let coordinate = point.coordinate else {
                output.append(
                    .init(
                        pointID: point.id, hours: [], status: "unavailable", note: "Koordinat belum dipilih."))
                continue
            }
            let key = String(format: "%.2f:%.2f", coordinate.latitude, coordinate.longitude)
            if var saved = groups[key] {
                saved.pointID = point.id
                output.append(saved)
                event(
                    "weather.result", category: "weather",
                    fields: [
                        "pointID": point.id, "status": saved.status, "source": "cache",
                        "provider": saved.provider?.rawValue ?? "none", "hourCount": String(saved.hours.count),
                    ])
                continue
            }
            let started = Date()
            let result = try await NativeTripWeatherFallback.resolve(
                pointID: point.id, primaryEnabled: !draft.isJakartaProfile,
                primary: {
                    guard (0 ... 9).contains(day) else {
                        throw NativeTripWeatherFailure.outsideHorizon(
                            "Tanggal di luar horizon prakiraan WeatherKit sekitar 10 hari.")
                    }
                    if let attributionFailure {
                        throw NativeTripWeatherFailure.unavailable(attributionFailure)
                    }
                    self.event(
                        "weather.requested", category: "weather",
                        fields: [
                            "pointID": point.id, "provider": "weatherkit",
                            "coordinate": "\(coordinate.latitude),\(coordinate.longitude)",
                        ])
                    let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    let weather = try await WeatherService.shared.weather(for: location)
                    try Task.checkCancellation()
                    let hours = weather.hourlyForecast.forecast.filter { hour in
                        hour.date < draft.endOfDay && hour.date.addingTimeInterval(3600) > draft.departure
                            && hour.precipitationChance.isFinite && (0 ... 1).contains(hour.precipitationChance)
                    }.map {
                        NativeTripHour(
                            date: $0.date, rainChance: $0.precipitationChance,
                            temperatureC: $0.temperature.converted(to: .celsius).value)
                    }
                    return NativeTripForecast(
                        pointID: point.id, hours: hours, status: hours.isEmpty ? "unavailable" : "available",
                        note:
                        "Prakiraan area Apple Weather, bukan jaminan kondisi tepat di tempat. Titik dekat berbagi prakiraan sementara per sekitar 0,01 derajat.",
                        fetchedAt: weather.hourlyForecast.metadata.date, provider: .weatherKit,
                        retrievedAt: .now)
                },
                backup: {
                    self.event(
                        "weather.fallback_requested", category: "weather",
                        fields: [
                            "pointID": point.id, "provider": "open_meteo",
                            "coordinate": "\(coordinate.latitude),\(coordinate.longitude)",
                            "dayOffset": String(day),
                        ])
                    return try await self.openMeteo.forecast(
                        pointID: point.id, latitude: coordinate.latitude, longitude: coordinate.longitude,
                        start: draft.departure, end: draft.endOfDay)
                },
                onFailure: { provider, error in
                    self.event(
                        "weather.failed", category: "weather", level: "warning",
                        fields: NativeTripLogStore.errorFields(error).merging([
                            "pointID": point.id, "provider": provider.rawValue,
                        ]) { _, new in new })
                })
            event(
                "weather.result", category: "weather", level: result.hours.isEmpty ? "warning" : "info",
                fields: [
                    "pointID": point.id, "status": result.status, "source": "provider",
                    "provider": result.provider?.rawValue ?? "none", "hourCount": String(result.hours.count),
                    "elapsedSeconds": String(Date().timeIntervalSince(started)),
                    "fetchedAt": result.fetchedAt?.ISO8601Format() ?? "unknown",
                    "retrievedAt": result.retrievedAt?.ISO8601Format() ?? "unknown", "note": result.note,
                ])
            groups[key] = result
            output.append(result)
        }
        return output
    }

    static func openMaps(from: NativeTripPoint, to: NativeTripPoint, mode: NativeTripMode) {
        guard from.coordinate != nil, to.coordinate != nil else { return }
        let launchMode: String
        switch mode {
        case .walking: launchMode = MKLaunchOptionsDirectionsModeWalking
        case .transit: launchMode = MKLaunchOptionsDirectionsModeTransit
        case .automobile: launchMode = MKLaunchOptionsDirectionsModeDriving
        }
        MKMapItem.openMaps(
            with: [mapItem(from), mapItem(to)],
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey: launchMode
            ])
    }
}
