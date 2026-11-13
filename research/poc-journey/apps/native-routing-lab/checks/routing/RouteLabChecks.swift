import Foundation
import CoreLocation
import MapKit

@MainActor final class ControlledDirections: DirectionsProviding {
    struct Request {
        let origin: CLLocationCoordinate2D
        let target: CLLocationCoordinate2D
        let continuation: CheckedContinuation<CalculatedRoute, Error>
    }
    var requests: [Request] = []
    var cancellations = 0
    func calculate(origin: CLLocationCoordinate2D, target: CLLocationCoordinate2D) async throws -> CalculatedRoute {
        try await withCheckedThrowingContinuation { continuation in
            requests.append(Request(origin: origin, target: target, continuation: continuation))
        }
    }
    // Deliberately allow cancelled requests to finish, exercising stale-completion protection.
    func cancel() { cancellations += 1 }
    func succeed(_ index: Int, latitudeOffset: Double = 0) {
        let request = requests[index]
        let points = [request.origin, request.target].map {
            CLLocationCoordinate2D(latitude: $0.latitude + latitudeOffset, longitude: $0.longitude)
        }
        let polyline = MKPolyline(coordinates: points, count: 2)
        request.continuation.resume(returning: CalculatedRoute(polyline: polyline, distance: 500,
                                                               expectedTravelTime: 360, instructions: ["Fixture pengujian"]))
    }
    func fail(_ index: Int, error: Error) { requests[index].continuation.resume(throwing: error) }
}

@main struct RouteLabChecks {
    @MainActor static var count = 0
    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        precondition(condition(), "FAILED: \(name)")
        count += 1
        print("PASS \(name)")
    }
    @MainActor static func settle() async {
        for _ in 0 ..< 8 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(5))
    }

    @MainActor static func main() async {
        let path = SimulationPath([(0, 0), (0, 0.001), (0.001, 0.001)])
        check(meters(path.coordinate(at: -1), path.coordinates[0]) < 0.01, "path clamps negative progress")
        check(meters(path.coordinate(at: 99999), path.coordinates.last!) < 0.01, "path ends without teleport or wrap")
        check(abs(meters(path.coordinate(at: 55), path.coordinates[0]) - 55) < 0.5, "path interpolates by distance")
        let line = MKPolyline(coordinates: [.init(latitude: 0, longitude: 0), .init(latitude: 0, longitude: 0.002)], count: 2)
        check(distanceFromRoute(.init(latitude: 0, longitude: 0.001), polyline: line) < 0.1, "off-route uses segment projection, not nearest vertex")
        check(distanceFromRoute(.init(latitude: 0.001, longitude: 0.001), polyline: line) > 100, "off-route detects perpendicular separation")
        let policy = ReroutePolicy()
        let base = Date()
        let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let target = CLLocationCoordinate2D(latitude: 0, longitude: 0.001)
        let snapshot = RouteSnapshot(origin: origin, target: target, requestedAt: base, simulationSeconds: 0)
        check(policy.reason(origin: origin, target: target, previous: nil, offRoute: nil) != nil, "initial route is requested")
        check(policy.reason(origin: origin, target: target, previous: snapshot, offRoute: 0) == nil, "unchanged positions preserve route")
        check(policy.reason(origin: origin, target: .init(latitude: 0, longitude: 0.0015), previous: snapshot, offRoute: 0) != nil, "target movement triggers route")
        check(policy.reason(origin: .init(latitude: 0, longitude: 0.0007), target: target, previous: snapshot, offRoute: 0) != nil, "origin movement triggers route")
        check(policy.reason(origin: origin, target: target, previous: snapshot, offRoute: 45) != nil, "off-route triggers route")

        let provider = ControlledDirections()
        let lab = RouteLab(provider: provider)
        lab.tick(at: base)
        lab.calculateManually(); lab.calculateManually()
        await settle()
        check(provider.requests.count == 1 && lab.isCalculating, "only one request can be active")
        provider.succeed(0); await settle()
        check(lab.successes == 1 && lab.route != nil && !lab.isCalculating, "successful request publishes route and clears loading")
        lab.reset(); lab.calculateManually(); await settle()
        check(lab.requests == 1 && lab.route == nil, "reset preserves device cooldown")
        lab.tick(at: base.addingTimeInterval(11)); lab.calculateManually(); await settle()
        check(provider.requests.count == 2, "request resumes after cooldown")
        lab.reset(); lab.tick(at: base.addingTimeInterval(22)); lab.calculateManually(); await settle()
        check(provider.requests.count == 3 && lab.isCalculating, "new session can start while cancelled completion is pending")
        provider.succeed(1); await settle()
        check(lab.route == nil && lab.isCalculating && lab.successes == 1, "stale success cannot publish route or clear newer loading")
        provider.succeed(2); await settle()
        check(lab.successes == 2 && !lab.isCalculating, "current completion remains authoritative")

        let earlyProvider = ControlledDirections()
        let early = RouteLab(provider: earlyProvider)
        early.calculateManually(); early.reset(); await settle()
        check(earlyProvider.requests.isEmpty, "cancel before task starts makes no provider call")

        let dynamicProvider = ControlledDirections()
        let dynamic = RouteLab(provider: dynamicProvider)
        dynamic.select(area: .singapore); dynamic.select(stage: .movingTarget)
        dynamic.tick(at: base); dynamic.start(); await settle()
        let initialOrigin = dynamic.origin, initialTarget = dynamic.target
        dynamic.tick(at: base)
        for second in 1 ... 6 { dynamic.tick(at: base.addingTimeInterval(Double(second))) }
        check(meters(dynamic.origin, initialOrigin) < 0.01 && meters(dynamic.target, initialTarget) > 30, "stage 1 moves B and keeps A fixed")
        check(dynamicProvider.requests.count == 1, "moving target never cancels and starves active request")
        dynamicProvider.succeed(0); await settle()
        dynamic.tick(at: base.addingTimeInterval(11)); await settle()
        check(dynamicProvider.requests.count == 2, "pending movement reroutes after cooldown")
        check(meters(dynamicProvider.requests[1].target, dynamic.target) < 0.01, "rerouting uses newest target, not queued old coordinates")
        dynamic.pause()
        let pausedSeconds = dynamic.simulationSeconds
        dynamic.tick(at: base.addingTimeInterval(30))
        dynamicProvider.succeed(1); await settle()
        check(dynamic.simulationSeconds == pausedSeconds && !dynamic.running && !dynamic.isCalculating, "pause freezes simulation and rejects pending completion")
        check(dynamic.successes == 1, "cancelled result does not count as success")
        dynamic.select(stage: .bothMoving)
        dynamic.tick(at: base.addingTimeInterval(40)); dynamic.start(); await settle()
        let a = dynamic.origin, b = dynamic.target
        dynamic.tick(at: base.addingTimeInterval(40)); dynamic.tick(at: base.addingTimeInterval(41))
        check(meters(dynamic.origin, a) > 8 && meters(dynamic.target, b) > 6, "stage 2 moves both points")
        dynamicProvider.succeed(2); await settle(); dynamic.pause()

        let failingProvider = ControlledDirections()
        let failing = RouteLab(provider: failingProvider)
        failing.tick(at: base); failing.calculateManually(); await settle()
        failingProvider.fail(0, error: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)); await settle()
        check(failing.failures == 1 && failing.errorMessage != nil && !failing.isCalculating, "network error is visible and loading terminates")
        failing.tick(at: base.addingTimeInterval(14)); failing.calculateManually(); await settle()
        check(failingProvider.requests.count == 1, "network failure applies backoff")
        failing.tick(at: base.addingTimeInterval(16)); failing.calculateManually(); await settle()
        failingProvider.fail(1, error: MKError(.loadingThrottled)); await settle()
        check(failing.remainingCooldown >= 60, "MapKit throttling applies 60-second backoff")
        failing.select(area: .tokyo); failing.tick(at: base.addingTimeInterval(60)); failing.calculateManually(); await settle()
        check(failingProvider.requests.count == 2, "area changes cannot bypass throttle backoff")
        failing.tick(at: base.addingTimeInterval(77)); failing.calculateManually(); await settle()
        failingProvider.succeed(2); await settle()
        check(failing.successes == 1 && failing.errorMessage == nil, "successful retry recovers from error")
        let snappedProvider = ControlledDirections()
        let snapped = RouteLab(provider: snappedProvider)
        snapped.select(stage: .movingTarget); snapped.playbackRate = 1
        snapped.tick(at: base); snapped.start(); await settle()
        snappedProvider.succeed(0, latitudeOffset: 0.002); await settle()
        snapped.tick(at: base)
        for second in 1 ... 11 { snapped.tick(at: base.addingTimeInterval(Double(second))) }
        check(snappedProvider.requests.count == 1, "stationary origin does not reroute because MapKit snapped the route")
        snapped.pause()

        let finalProvider = ControlledDirections()
        let finalLab = RouteLab(provider: finalProvider)
        finalLab.select(stage: .bothMoving); finalLab.playbackRate = 10000
        finalLab.tick(at: base); finalLab.start(); await settle()
        finalLab.tick(at: base); finalLab.tick(at: base.addingTimeInterval(1))
        check(finalLab.finished && finalLab.simulationSeconds == finalLab.duration, "simulation clamps at final positions")
        finalProvider.succeed(0); await settle()
        finalLab.tick(at: base.addingTimeInterval(11)); await settle()
        check(finalProvider.requests.count == 2, "simulation routes the final positions after cooldown")
        finalProvider.succeed(1); await settle()
        finalLab.tick(at: base.addingTimeInterval(12))
        check(!finalLab.running && finalLab.finished && finalLab.successes == 2, "simulation stops after final route without restarting")

        let liveProvider = ControlledDirections()
        let live = RouteLab(provider: liveProvider)
        live.select(stage: .realGPS); live.tick(at: base); live.start(); await settle()
        check(liveProvider.requests.isEmpty, "live mode does not route using preset fallback coordinates")
        live.updateLive(origin: origin, target: target); live.tick(at: base); await settle()
        check(liveProvider.requests.count == 1, "live input requests real origin and target")
        live.updateLive(origin: nil, target: nil)
        check(!live.isCalculating && !live.liveInputsReady, "stale live input cancels active request")
        liveProvider.succeed(0); await settle()
        check(live.route == nil && live.successes == 0, "late response cannot publish after live input expires")
        live.updateLive(origin: origin, target: target); live.tick(at: base.addingTimeInterval(11)); await settle()
        check(liveProvider.requests.count == 2 && live.simulationSeconds == 0, "live rerouting resumes without advancing simulation")
        liveProvider.succeed(1); await settle(); live.pause()
        live.tick(at: base.addingTimeInterval(30)); await settle()
        check(liveProvider.requests.count == 2, "paused live routing cannot issue background requests")

        print("\n\(count) deterministic checks passed. Fake provider only; no Apple service coverage claim.")
    }
}
