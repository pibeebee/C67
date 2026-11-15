import CoreLocation
import Foundation
import MapKit
import Observation

struct NativeTripMapRouteKey: Hashable {
    let fromLatitude: Double
    let fromLongitude: Double
    let toLatitude: Double
    let toLongitude: Double
    let mode: String
    let departure: Date

    init?(_ leg: NativeTripLeg) {
        guard let from = leg.from.coordinate, let to = leg.to.coordinate, let chosen = leg.chosen,
              chosen.usable
        else { return nil }
        fromLatitude = from.latitude
        fromLongitude = from.longitude
        toLatitude = to.latitude
        toLongitude = to.longitude
        mode = chosen.mode.rawValue
        departure = leg.departure
    }
}

struct NativeTripMapGeometry {
    let polyline: MKPolyline
    let seconds: Double
    let distance: Double
    var fetchedAt = Date()
}

enum NativeTripMapRouteStatus: String {
    case pending, loading, available, failed, unsupported, stationary, missingInput
}

struct NativeTripMapLegState {
    let key: NativeTripMapRouteKey?
    var status: NativeTripMapRouteStatus
    var message: String
    var geometry: NativeTripMapGeometry?
}

@MainActor protocol NativeTripMapDirectionsProviding: AnyObject {
    func route(for leg: NativeTripLeg) async throws -> NativeTripMapGeometry
    func cancel()
}

@MainActor final class NativeTripMapDirectionsProvider: NativeTripMapDirectionsProviding {
    private var active: MKDirections?
    private static var nextRequest = Date.distantPast

    func cancel() {
        active?.cancel()
        active = nil
    }

    func route(for leg: NativeTripLeg) async throws -> NativeTripMapGeometry {
        guard let from = leg.from.coordinate, let to = leg.to.coordinate, let chosen = leg.chosen,
              chosen.usable, chosen.mode != .transit
        else { throw NativeTripError.message("Data jalur belum tersedia untuk ruas ini.") }
        let slot = max(Date(), Self.nextRequest)
        Self.nextRequest = slot.addingTimeInterval(1.2)
        let delay = max(0, slot.timeIntervalSinceNow)
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
        let request = MKDirections.Request()
        request.source = mapItem(from)
        request.destination = mapItem(to)
        request.transportType = chosen.mode == .walking ? .walking : .automobile
        request.departureDate = leg.departure
        request.requestsAlternateRoutes = false
        let operation = MKDirections(request: request)
        active = operation
        defer { if active === operation { active = nil } }
        var expired = false
        let deadline = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(25)) } catch { return }
            guard !Task.isCancelled else { return }
            expired = true
            operation.cancel()
        }
        defer { deadline.cancel() }
        do {
            let response = try await operation.calculate()
            try Task.checkCancellation()
            guard !expired else {
                throw NativeTripError.message("Permintaan jalur melewati batas 25 detik.")
            }
            guard
                let route = response.routes.first(where: {
                    $0.transportType.contains(request.transportType)
                }),
                route.polyline.pointCount > 1, route.expectedTravelTime.isFinite,
                route.expectedTravelTime >= 0, route.distance.isFinite, route.distance >= 0
            else {
                throw NativeTripError.message("MapKit tidak memberikan geometri yang sesuai moda ruas.")
            }
            return .init(
                polyline: route.polyline, seconds: route.expectedTravelTime, distance: route.distance)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if expired { throw NativeTripError.message("Permintaan jalur melewati batas 25 detik.") }
            throw error
        }
    }

    private func mapItem(_ coordinate: CLLocationCoordinate2D) -> MKMapItem {
        if #available(iOS 26.0, macOS 26.0, *) {
            return MKMapItem(
                location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                address: nil)
        }
        return MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
    }
}

@MainActor @Observable final class NativeTripMapRouteStore {
    private(set) var states: [String: NativeTripMapLegState] = [:]
    private(set) var isLoading = false
    private(set) var requestCount = 0
    let requestLimit: Int
    @ObservationIgnored private var cache: [NativeTripMapRouteKey: NativeTripMapGeometry] = [:]
    @ObservationIgnored private let provider: any NativeTripMapDirectionsProviding
    @ObservationIgnored private let logs: NativeTripLogStore
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var operationID = UUID().uuidString
    @ObservationIgnored private var retryAfter = Date.distantPast

    init(
        provider: (any NativeTripMapDirectionsProviding)? = nil, logs: NativeTripLogStore? = nil,
        requestLimit: Int = 64
    ) {
        self.provider = provider ?? NativeTripMapDirectionsProvider()
        self.logs = logs ?? .shared
        self.requestLimit = max(1, requestLimit)
    }

    func state(for leg: NativeTripLeg) -> NativeTripMapLegState {
        let key = NativeTripMapRouteKey(leg)
        if let value = states[leg.id], value.key == key { return value }
        return .init(key: key, status: .pending, message: "Jalur belum dimuat.")
    }

    func cancel() {
        if isLoading { event("map.routes_cancelled") }
        generation = UUID()
        provider.cancel()
        isLoading = false
        for (id, value) in states where value.status == .loading {
            states[id] = .init(key: value.key, status: .pending, message: "Pemuatan ditunda.")
        }
    }

    func load(_ legs: [NativeTripLeg], retryFailed: Bool = false) async {
        cancel()
        let token = generation
        operationID = UUID().uuidString
        isLoading = true
        event(
            "map.routes_started",
            fields: ["legs": String(legs.count), "retryFailed": String(retryFailed)])
        defer { if generation == token { isLoading = false } }
        for leg in legs {
            guard !Task.isCancelled, generation == token else { return }
            let key = NativeTripMapRouteKey(leg)
            var value = NativeTripMapLegState(key: key, status: .pending, message: "Jalur belum dimuat.")
            guard let key else {
                value.status = .missingInput
                value.message = "Koordinat atau moda terpilih belum tersedia; jalur tidak digambar."
                states[leg.id] = value
                event("map.route_skipped", leg: leg, fields: ["reason": value.status.rawValue])
                continue
            }
            if key.fromLatitude == key.toLatitude && key.fromLongitude == key.toLongitude {
                value.status = .stationary
                value.message = "Titik sama; tidak ada perpindahan untuk digambar."
                states[leg.id] = value
                continue
            }
            if key.mode == NativeTripMode.transit.rawValue {
                value.status = .unsupported
                value.message =
                    "MapKit memberi ETA transit, tetapi tidak menyediakan garis jalurnya. Periksa di Apple Maps."
                states[leg.id] = value
                event("map.route_skipped", leg: leg, fields: ["reason": value.status.rawValue])
                continue
            }
            if let geometry = cache[key] {
                value.status = .available
                value.message = "Jalur MapKit tersimpan sementara."
                value.geometry = geometry
                states[leg.id] = value
                event(
                    "map.route_cache_hit", leg: leg, fields: ["points": String(geometry.polyline.pointCount)])
                continue
            }
            if state(for: leg).status == .failed && !retryFailed { continue }
            guard requestCount < requestLimit, Date() >= retryAfter else {
                value.status = .failed
                value.message =
                    requestCount >= requestLimit
                        ? "Batas permintaan jalur untuk laporan ini tercapai."
                        : "MapKit sedang membatasi permintaan. Tunggu sebentar sebelum mencoba lagi."
                states[leg.id] = value
                event("map.route_skipped", leg: leg, fields: ["reason": value.message])
                continue
            }
            value.status = .loading
            value.message = "Mengambil jalur MapKit…"
            states[leg.id] = value
            requestCount += 1
            let started = Date()
            event("map.route_requested", leg: leg, fields: ["requestCount": String(requestCount)])
            do {
                let geometry = try await provider.route(for: leg)
                guard !Task.isCancelled, generation == token else { return }
                value.status = .available
                value.message = "Jalur MapKit tersedia."
                value.geometry = geometry
                if cache.count >= 128,
                   let oldest = cache.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key
                {
                    cache[oldest] = nil
                }
                cache[key] = geometry
                states[leg.id] = value
                event(
                    "map.route_result", leg: leg,
                    fields: [
                        "status": value.status.rawValue, "points": String(geometry.polyline.pointCount),
                        "routeSeconds": String(geometry.seconds),
                        "itinerarySeconds": String(leg.chosen!.seconds!),
                        "distanceMeters": String(geometry.distance),
                        "elapsedSeconds": String(Date().timeIntervalSince(started)),
                    ])
            } catch {
                guard !Task.isCancelled, generation == token, !(error is CancellationError) else {
                    if generation == token {
                        states[leg.id] = .init(key: key, status: .pending, message: "Pemuatan ditunda.")
                    }
                    return
                }
                let native = error as NSError
                if native.domain == MKErrorDomain && native.code == MKError.Code.loadingThrottled.rawValue {
                    retryAfter = Date().addingTimeInterval(15)
                }
                value.status = .failed
                value.message = "Jalur belum tersedia: \(error.localizedDescription)"
                states[leg.id] = value
                event(
                    "map.route_failed", leg: leg,
                    fields: NativeTripLogStore.errorFields(error).merging([
                        "elapsedSeconds": String(Date().timeIntervalSince(started))
                    ]) { _, new in new })
            }
        }
        event(
            "map.routes_completed",
            fields: [
                "legs": String(legs.count),
                "available": String(legs.filter { state(for: $0).status == .available }.count),
                "failed": String(legs.filter { state(for: $0).status == .failed }.count),
                "requestCount": String(requestCount),
            ])
    }

    func select(_ leg: NativeTripLeg?) {
        event("map.leg_selected", leg: leg, fields: ["selection": leg?.id ?? "all"])
    }

    private func event(_ name: String, leg: NativeTripLeg? = nil, fields: [String: String] = [:]) {
        var details = fields
        if let leg {
            details["legID"] = leg.id
            details["from"] = leg.from.title
            details["to"] = leg.to.title
            details["mode"] = leg.chosen?.mode.rawValue ?? "unknown"
            details["departure"] = leg.departure.ISO8601Format()
        }
        logs.record(name, category: "route_map", operationID: operationID, fields: details)
    }
}
