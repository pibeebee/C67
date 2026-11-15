import Foundation
import CoreLocation
import MapKit
import Observation

struct RouteEvent: Identifiable {
    let id = UUID()
    let date: Date
    let message: String
}

@MainActor @Observable final class RouteLab {
    private(set) var stage: ExperimentStage = .staticRoute
    private(set) var area: TestArea = .jakarta
    var playbackRate: Double = 5
    var showsPaths = true
    var policy = ReroutePolicy()
    private(set) var simulationSeconds: Double = 0
    private(set) var running = false
    private(set) var finished = false
    private(set) var now = Date()
    private(set) var route: CalculatedRoute?
    private(set) var routeSnapshot: RouteSnapshot?
    private(set) var isCalculating = false
    private(set) var status = "Siap untuk uji rute statis"
    private(set) var lastReason = "Belum ada request"
    private(set) var errorMessage: String?
    private(set) var requests = 0
    private(set) var successes = 0
    private(set) var failures = 0
    private(set) var cancellations = 0
    private(set) var lastLatency: Double?
    private(set) var events: [RouteEvent] = []
    private var lastRequestAt: Date?
    private var retryNotBefore: Date?
    private var consecutiveFailures = 0
    private var generation = UUID()
    private var activeRequest: UUID?
    private var routeTask: Task<Void, Never>?
    private var previousTick: Date?
    private var liveOrigin: CLLocationCoordinate2D?
    private var liveTarget: CLLocationCoordinate2D?
    var liveInputsReady: Bool { liveOrigin != nil && liveTarget != nil }
    private let provider: any DirectionsProviding

    init(provider: (any DirectionsProviding)? = nil) { self.provider = provider ?? AppleDirectionsProvider() }

    var origin: CLLocationCoordinate2D {
        liveOrigin ?? area.navigatorPath.coordinate(at: stage == .bothMoving ? simulationSeconds * 1.8 : 0)
    }
    var target: CLLocationCoordinate2D {
        liveTarget ?? area.targetPath.coordinate(at: stage == .staticRoute ? 0 : simulationSeconds * 1.4)
    }
    var duration: Double {
        let targetDuration = area.targetPath.length / 1.4
        return stage == .bothMoving ? max(targetDuration, area.navigatorPath.length / 1.8) : targetDuration
    }
    var remainingCooldown: Double {
        let intervalEnd = lastRequestAt?.addingTimeInterval(policy.minimumInterval) ?? .distantPast
        return max(0, max(intervalEnd, retryNotBefore ?? .distantPast).timeIntervalSince(now))
    }
    var targetOffset: Double { routeSnapshot.map { meters(target, $0.target) } ?? 0 }
    var report: String {
        """
        Dynamic Destination · C67
        Lokasi: \(stage.isLive ? "Sumber lokasi rombongan" : "SIMULASI") · Rute: Apple MapKit (.walking)
        Area: \(stage.isLive ? "GPS perangkat (tanpa preset area)" : area.title)
        Tahap: \(stage.title)
        Waktu simulasi: \(Int(simulationSeconds)) s · Kecepatan pemutaran: \(Int(playbackRate))×
        Request: \(requests) · Berhasil: \(successes) · Gagal: \(failures) · Dibatalkan: \(cancellations)
        Interval minimum: \(Int(policy.minimumInterval)) s nyata
        Ambang B/A/off-route: \(Int(policy.targetMovement))/\(Int(policy.originMovement))/\(Int(policy.offRouteDistance)) m
        Status: \(status)
        Error: \(errorMessage ?? "—")
        Rute dihitung pada: \(routeSnapshot?.requestedAt.ISO8601Format() ?? "—")
        Jarak hasil routing: \(route.map { String(format: "%.0f m", $0.distance) } ?? "—")
        ETA hasil routing: \(route.map { String(format: "%.0f s", $0.expectedTravelTime) } ?? "—")

        \(events.reversed().map { "\($0.date.ISO8601Format()) · \($0.message)" }.joined(separator: "\n"))
        """
    }

    func updateLive(origin: CLLocationCoordinate2D?, target: CLLocationCoordinate2D?) {
        liveOrigin = origin; liveTarget = target
        if stage.isLive && !liveInputsReady {
            if isCalculating { cancelRequest() }
            status = "Menunggu dua posisi yang masih segar dan akurat"
        }
    }

    func select(stage: ExperimentStage) { self.stage = stage; reset() }
    func select(area: TestArea) { self.area = area; reset() }

    func reset() {
        cancelRequest()
        running = false; finished = false; simulationSeconds = 0; previousTick = nil
        liveOrigin = nil; liveTarget = nil
        route = nil; routeSnapshot = nil; errorMessage = nil; lastLatency = nil
        status = "Siap · \(stage.title)"
        lastReason = "Belum ada request untuk skenario ini"
        addEvent("Reset · \(area.title) · \(stage.title). Cooldown request tetap berlaku selama app berjalan.")
    }

    func start() {
        guard stage != .staticRoute else { calculateManually(); return }
        guard !finished else { return }
        running = true; previousTick = nil
        addEvent(stage.isLive ? "Routing GPS dimulai/dilanjutkan" : "Simulasi dimulai/dilanjutkan")
        evaluate()
    }

    func pause() {
        guard running || isCalculating else { return }
        running = false; previousTick = nil; cancelRequest()
        status = "Dijeda · posisi dan rute terakhir dipertahankan"
        addEvent("Dijeda; request aktif dibatalkan")
    }

    func tick(at date: Date) {
        now = date
        let elapsed = previousTick.map { max(0, min(2, date.timeIntervalSince($0))) } ?? 0
        previousTick = date
        guard running else { return }
        if stage.isLive { evaluate(); return }
        simulationSeconds = min(duration, simulationSeconds + elapsed * playbackRate)
        if simulationSeconds >= duration {
            // Keep evaluating until the final position has a route or an explicit failure.
            finished = true
        }
        evaluate()
        if finished, !isCalculating {
            let needsFinalRoute = policy.reason(origin: origin, target: target, previous: routeSnapshot, offRoute: nil) != nil
            if !needsFinalRoute || errorMessage != nil {
                running = false
                status = errorMessage == nil ? "Lintasan simulasi selesai" : "Lintasan selesai · routing terakhir gagal"
                addEvent(status)
            }
        }
    }

    func calculateManually() {
        guard !isCalculating, !stage.isLive || liveInputsReady else { return }
        guard remainingCooldown <= 0 else { status = "Menunggu cooldown sebelum request berikutnya"; return }
        requestRoute(reason: "Hitung manual")
    }

    private func evaluate() {
        guard !isCalculating else { return }
        guard !stage.isLive || liveInputsReady else { status = "Menunggu dua posisi yang masih segar dan akurat"; return }
        // MapKit may snap an input point onto a nearby accessible road/path.
        // Compare with that original offset, so a stationary A is not treated as deviating.
        let offRoute: Double?
        if let route, let snapshot = routeSnapshot, (stage == .bothMoving || stage.isLive) {
            offRoute = max(0, distanceFromRoute(origin, polyline: route.polyline)
                - distanceFromRoute(snapshot.origin, polyline: route.polyline))
        } else { offRoute = nil }
        guard let reason = policy.reason(origin: origin, target: target, previous: routeSnapshot, offRoute: offRoute) else {
            status = "Rute dipertahankan · pergeseran di bawah ambang"
            return
        }
        guard remainingCooldown <= 0 else {
            status = "Perubahan menunggu cooldown"
            return
        }
        requestRoute(reason: reason)
    }

    private func requestRoute(reason: String) {
        let requestID = UUID(), session = generation
        let snapshot = RouteSnapshot(origin: origin, target: target, requestedAt: now, simulationSeconds: simulationSeconds)
        activeRequest = requestID; isCalculating = true; requests += 1; lastRequestAt = now
        lastReason = reason; errorMessage = nil; status = "Menghitung rute berjalan kaki…"
        addEvent("Request #\(requests): \(reason)")
        routeTask = Task { [weak self] in
            guard let self, !Task.isCancelled, self.generation == session, self.activeRequest == requestID else { return }
            let started = Date()
            do {
                let result = try await self.provider.calculate(origin: snapshot.origin, target: snapshot.target)
                guard !Task.isCancelled, self.generation == session, self.activeRequest == requestID else { return }
                self.route = result; self.routeSnapshot = snapshot; self.successes += 1
                self.consecutiveFailures = 0; self.retryNotBefore = nil
                self.lastLatency = Date().timeIntervalSince(started)
                self.status = "Rute tersedia"
                self.addEvent("Berhasil · \(Int(result.distance)) m · ETA \(Int(result.expectedTravelTime)) s")
            } catch {
                guard !Task.isCancelled, self.generation == session, self.activeRequest == requestID else { return }
                self.failures += 1; self.consecutiveFailures += 1
                let nsError = error as NSError
                let throttled = nsError.domain == MKErrorDomain && nsError.code == MKError.Code.loadingThrottled.rawValue
                let noRoute = nsError.domain == MKErrorDomain && nsError.code == MKError.Code.directionsNotFound.rawValue
                let delay = throttled ? 60.0 : min(120, 15 * pow(2, Double(min(3, self.consecutiveFailures - 1))))
                self.retryNotBefore = self.now.addingTimeInterval(delay)
                self.errorMessage = noRoute
                    ? "MapKit tidak menemukan rute berjalan kaki untuk pasangan titik ini. Coba area atau titik lain; ini belum membuktikan seluruh wilayah tidak didukung."
                    : throttled ? "MapKit membatasi request. Percobaan berikutnya ditunda setidaknya 60 detik."
                    : "\(error.localizedDescription) (\(nsError.domain), \(nsError.code))"
                self.status = "Routing gagal · rute sebelumnya tetap bertanggal lama"
                self.addEvent("Gagal · \(nsError.domain)/\(nsError.code) · jeda \(Int(delay)) s")
            }
            // Old completions must never clear the new request's loading state.
            guard self.generation == session, self.activeRequest == requestID else { return }
            self.activeRequest = nil; self.isCalculating = false; self.routeTask = nil
        }
    }

    private func cancelRequest() {
        generation = UUID()
        if activeRequest != nil { cancellations += 1 }
        routeTask?.cancel(); provider.cancel(); routeTask = nil
        activeRequest = nil; isCalculating = false
    }

    private func addEvent(_ message: String) {
        events.insert(RouteEvent(date: now, message: message), at: 0)
        if events.count > 100 { events.removeLast(events.count - 100) }
    }
}
