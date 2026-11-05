import Foundation
import MapKit

@MainActor final class FakeMapProvider: NativeTripMapDirectionsProviding {
    var calls = 0
    var failing = false
    var pause = false
    var pending: CheckedContinuation<NativeTripMapGeometry, any Error>?

    func route(for leg: NativeTripLeg) async throws -> NativeTripMapGeometry {
        calls += 1
        if pause {
            return try await withCheckedThrowingContinuation { pending = $0 }
        }
        if failing { throw NativeTripError.message("Synthetic provider failure") }
        return Self.geometry()
    }
    func cancel() {}
    static func geometry() -> NativeTripMapGeometry {
        var points = [
            CLLocationCoordinate2D(latitude: -6.2, longitude: 106.82),
            CLLocationCoordinate2D(latitude: -6.19, longitude: 106.83),
        ]
        return .init(
            polyline: MKPolyline(coordinates: &points, count: points.count), seconds: 45, distance: 100)
    }
}

@main struct MapChecks {
    @MainActor static func leg(_ id: String, mode: NativeTripMode = .automobile) -> NativeTripLeg {
        .init(
            id: id,
            from: .init(id: "a", title: "Start", query: "", latitude: -6.2, longitude: 106.82),
            to: .init(id: "b", title: "End", query: "", latitude: -6.19, longitude: 106.83),
            departure: Date(timeIntervalSince1970: 1_793_836_800), dwellMinutes: 30,
            dwellSource: "default", isReturn: false,
            chosen: .init(id: "eta", mode: mode, seconds: 30, status: "available", note: "Synthetic ETA"),
            options: [], notes: [])
    }

    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logs = NativeTripLogStore(directory: directory)
        let fake = FakeMapProvider()
        let store = NativeTripMapRouteStore(provider: fake, logs: logs)
        let first = leg("first")
        await store.load([first])
        precondition(store.state(for: first).status == .available && fake.calls == 1)
        precondition(store.state(for: first).geometry?.seconds == 45 && first.chosen?.seconds == 30)
        await store.load([first])
        var sameRequest = first
        sameRequest.id = "another-occurrence"
        await store.load([sameRequest])
        precondition(fake.calls == 1 && store.state(for: sameRequest).status == .available)
        print(
            "PASS 1: cache survives re-entry and distinct leg IDs; geometry ETA never mutates itinerary ETA"
        )

        var moved = first
        moved.to.longitude = 106.84
        await store.load([moved])
        var later = first
        later.departure.addTimeInterval(60)
        await store.load([later])
        let walking = leg("first", mode: .walking)
        await store.load([walking])
        precondition(fake.calls == 4)
        precondition(store.state(for: first).status == .pending)
        print("PASS 2: cache keys separate coordinates, departure and mode, even when leg ID is reused")

        fake.failing = true
        var bad = leg("bad")
        bad.to.longitude = 106.85
        await store.load([first, bad])
        precondition(
            store.state(for: first).status == .available && store.state(for: bad).status == .failed)
        let before = fake.calls
        await store.load([first, bad])
        precondition(fake.calls == before)
        fake.failing = false
        await store.load([first, bad], retryFailed: true)
        precondition(fake.calls == before + 1 && store.state(for: bad).status == .available)
        print(
            "PASS 3: partial failure preserves successful geometry; explicit retry requests only missing geometry"
        )

        let transit = leg("transit", mode: .transit)
        var stationary = leg("stationary")
        stationary.to = stationary.from
        var missing = leg("missing")
        missing.chosen = nil
        var unresolved = leg("unresolved")
        unresolved.from.latitude = nil
        let count = fake.calls
        await store.load([transit, stationary, missing, unresolved])
        precondition(fake.calls == count)
        precondition(store.state(for: transit).status == .unsupported)
        precondition(store.state(for: stationary).status == .stationary)
        precondition(store.state(for: missing).status == .missingInput)
        precondition(store.state(for: unresolved).status == .missingInput)
        print(
            "PASS 4: transit, same-point and incomplete input produce no provider requests or fabricated geometry"
        )

        let limited = NativeTripMapRouteStore(provider: fake, logs: logs, requestLimit: 1)
        await limited.load([first, bad])
        precondition(limited.requestCount == 1 && limited.state(for: bad).status == .failed)
        await limited.load([first, bad], retryFailed: true)
        precondition(limited.requestCount == 1 && limited.state(for: first).status == .available)
        print("PASS 5: retry obeys the per-report request budget and retains loaded geometry")

        let raceProvider = FakeMapProvider()
        raceProvider.pause = true
        let raceStore = NativeTripMapRouteStore(provider: raceProvider, logs: logs)
        let oldTask = Task { await raceStore.load([first]) }
        while raceProvider.pending == nil { await Task.yield() }
        raceStore.cancel()
        raceProvider.pause = false
        await raceStore.load([moved])
        raceProvider.pending?.resume(returning: FakeMapProvider.geometry())
        raceProvider.pending = nil
        await oldTask.value
        precondition(raceStore.state(for: moved).status == .available)
        precondition(raceStore.state(for: first).status == .pending && !raceStore.isLoading)
        print(
            "PASS 6: late response from cancelled load cannot overwrite a newer route or loading state")

        await logs.flush()
        let saved = try await logs.snapshot()
        let text = String(decoding: saved.data, as: UTF8.self)
        precondition(
            text.contains("map.route_cache_hit") && text.contains("map.route_failed")
                && text.contains("map.routes_cancelled"))
        print("6 local macOS map-state checks passed. Synthetic provider; no network or iOS tests.")
    }
}
