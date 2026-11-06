import Foundation
import CoreLocation
import MapKit

enum ExperimentStage: Int, CaseIterable, Identifiable {
    case staticRoute, movingTarget, bothMoving, realGPS, twoDevices, backgroundTracking
    var isLive: Bool { rawValue >= 3 }
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .staticRoute: "0 · Statis"
        case .movingTarget: "1 · B bergerak"
        case .bothMoving: "2 · A + B"
        case .realGPS: "3 · GPS nyata"
        case .twoDevices: "4 · Dua iPhone"
        case .backgroundTracking: "5 · Background"
        }
    }
    var explanation: String {
        switch self {
        case .staticRoute: "A dan B tetap. Periksa apakah MapKit menyediakan rute berjalan kaki di area ini."
        case .movingTarget: "A tetap. B bergerak pada lintasan simulasi; aplikasi mengevaluasi ulang rutenya."
        case .bothMoving: "A dan B bergerak pada lintasan simulasi terpisah. Rute mengikuti posisi terbaru keduanya."
        case .realGPS: "A memakai GPS perangkat. B adalah simulasi dekat posisi awal A."
        case .twoDevices: "B berbagi GPS ke A melalui koneksi lokal terenkripsi. Kedua app tetap foreground."
        case .backgroundTracking: "Sesi GPS berlanjut di background. Rute dihitung saat Navigator foreground; pengiriman tetap bergantung pada koneksi dan iOS."
        }
    }
}

enum TestArea: String, CaseIterable, Identifiable {
    case jakarta, singapore, tokyo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .jakarta: "Jakarta · Monas"
        case .singapore: "Singapura · Civic District"
        case .tokyo: "Tokyo · Marunouchi"
        }
    }
    var targetPath: SimulationPath {
        switch self {
        case .jakarta:
            SimulationPath([(-6.1755, 106.8294), (-6.1786, 106.8294), (-6.1801, 106.8278), (-6.1802, 106.8242)])
        case .singapore:
            SimulationPath([(1.2954, 103.8533), (1.2940, 103.8523), (1.2925, 103.8512), (1.2908, 103.8501)])
        case .tokyo:
            SimulationPath([(35.6836, 139.7640), (35.6821, 139.7628), (35.6805, 139.7616), (35.6790, 139.7605)])
        }
    }
    var navigatorPath: SimulationPath {
        switch self {
        case .jakarta:
            SimulationPath([(-6.1785, 106.8227), (-6.1802, 106.8242), (-6.1801, 106.8278), (-6.1786, 106.8294)])
        case .singapore:
            SimulationPath([(1.2901, 103.8501), (1.2915, 103.8506), (1.2925, 103.8512), (1.2940, 103.8523)])
        case .tokyo:
            SimulationPath([(35.6780, 139.7595), (35.6790, 139.7605), (35.6805, 139.7616), (35.6821, 139.7628)])
        }
    }
    var region: MKCoordinateRegion {
        let a = navigatorPath.coordinate(at: 0)
        let b = targetPath.coordinate(at: 0)
        return MKCoordinateRegion(center: .init(latitude: (a.latitude + b.latitude) / 2,
                                                longitude: (a.longitude + b.longitude) / 2),
                                  latitudinalMeters: 1800, longitudinalMeters: 1800)
    }
}

struct SimulationPath {
    let coordinates: [CLLocationCoordinate2D]
    init(_ points: [(Double, Double)]) {
        precondition(points.count >= 2)
        coordinates = points.map { .init(latitude: $0.0, longitude: $0.1) }
    }
    var length: Double {
        zip(coordinates, coordinates.dropFirst()).reduce(0) { $0 + meters($1.0, $1.1) }
    }
    func coordinate(at distance: Double) -> CLLocationCoordinate2D {
        var remaining = max(0, distance)
        for (start, end) in zip(coordinates, coordinates.dropFirst()) {
            let segment = meters(start, end)
            if remaining <= segment, segment > 0 {
                let fraction = remaining / segment
                return .init(latitude: start.latitude + (end.latitude - start.latitude) * fraction,
                             longitude: start.longitude + (end.longitude - start.longitude) * fraction)
            }
            remaining -= segment
        }
        return coordinates.last!
    }
}

func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
    CLLocation(latitude: a.latitude, longitude: a.longitude)
        .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
}

func distanceFromRoute(_ coordinate: CLLocationCoordinate2D, polyline: MKPolyline) -> Double {
    guard polyline.pointCount > 1 else { return .infinity }
    let point = MKMapPoint(coordinate)
    let vertices = polyline.points()
    var closest = Double.infinity
    for index in 0 ..< (polyline.pointCount - 1) {
        let a = vertices[index], b = vertices[index + 1]
        let dx = b.x - a.x, dy = b.y - a.y
        let squaredLength = dx * dx + dy * dy
        let t = squaredLength > 0 ? min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / squaredLength)) : 0
        closest = min(closest, point.distance(to: MKMapPoint(x: a.x + t * dx, y: a.y + t * dy)))
    }
    return closest
}

struct RouteSnapshot {
    let origin: CLLocationCoordinate2D
    let target: CLLocationCoordinate2D
    let requestedAt: Date
    let simulationSeconds: Double
}

struct ReroutePolicy {
    var minimumInterval: Double = 10
    var targetMovement: Double = 30
    var originMovement: Double = 60
    var offRouteDistance: Double = 40

    func reason(origin: CLLocationCoordinate2D, target: CLLocationCoordinate2D,
                previous: RouteSnapshot?, offRoute: Double?) -> String? {
        guard let previous else { return "Rute pertama" }
        if meters(target, previous.target) >= targetMovement { return "B bergeser ≥ \(Int(targetMovement)) m" }
        if let offRoute, offRoute >= offRouteDistance { return "A menjauh dari rute ≥ \(Int(offRouteDistance)) m" }
        if meters(origin, previous.origin) >= originMovement { return "A bergeser ≥ \(Int(originMovement)) m" }
        return nil
    }
}
