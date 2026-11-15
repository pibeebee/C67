import Foundation
import CoreLocation
import Observation

enum GroupRouteDestination: Equatable {
    case person(String), activity(UUID), meeting
    var key: String {
        switch self {
        case .person(let id): "person:" + id
        case .activity(let id): "activity:" + id.uuidString
        case .meeting: "meeting"
        }
    }
}

struct RouteCoordinate: Equatable {
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    init(_ sample: LocationSample) { latitude = sample.latitude; longitude = sample.longitude }
    init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
}

struct GroupRouteInput {
    let scope: String
    let destination: GroupRouteDestination
    let name: String
    let origin: RouteCoordinate?
    let target: RouteCoordinate?
    let sourceRevision: String?
    let problem: String?
}

@MainActor extension POCController {
    func routingScope(for audience: MapAudience) -> String {
        "\(store.state.runID)|\(store.state.mode.rawValue)|\(audience == .leader ? "leader" : "participant")"
    }
    func routingInput(for audience: MapAudience, destination: GroupRouteDestination,
                      localSample: LocationSample? = nil, now: Date = .now) -> GroupRouteInput {
        let points = mapPoints(for: audience, localSample: localSample, now: now)
        let ownID = audience == .leader ? "TL" : "YOU"
        let own = points.first { $0.id == ownID }?.sample
        var target: RouteCoordinate?
        var revision: String?
        var targetSample: LocationSample?
        var name = "Tujuan belum tersedia"
        var problem: String?
        switch destination {
        case .person(let id):
            if id == ownID { problem = "Pilih orang lain sebagai tujuan." }
            if let point = points.first(where: { $0.id == id }) {
                name = point.name; targetSample = point.sample; target = RouteCoordinate(point.sample)
                revision = point.sample.epoch.uuidString
            } else { problem = "Lokasi tujuan tidak tersedia atau sesi berbagi sudah berakhir." }
        case .activity(let id):
            if let activity = store.state.effectivePlan.activities.first(where: { $0.id == id }), let place = activity.place {
                name = activity.title; target = .init(latitude: place.latitude, longitude: place.longitude)
                revision = "\(place.latitude)|\(place.longitude)"
            } else { problem = "Kegiatan sudah dihapus atau tidak memiliki lokasi." }
        case .meeting:
            if let point = store.state.meetingPoint {
                name = store.state.effectivePlan.meetingName ?? "Meeting point"
                target = .init(latitude: point.latitude, longitude: point.longitude)
                revision = "\(point.latitude)|\(point.longitude)"
            } else { problem = "Meeting point belum ditentukan atau telah dihapus." }
        }
        func quality(_ sample: LocationSample?, label: String) -> String? {
            guard let sample else { return "\(label): menunggu lokasi." }
            guard sample.valid, sample.runID == store.state.runID else { return "\(label): lokasi tidak valid untuk perjalanan ini." }
            if store.state.mode == .real && sample.simulated { return "\(label): sampel sintetis tidak dipakai pada run nyata." }
            let age = now.timeIntervalSince(sample.measuredAt)
            guard (-5 ... LocationRules.staleAfter).contains(age) else { return "\(label): posisi kedaluwarsa atau jam perangkat tidak cocok." }
            guard !sample.reduced, sample.accuracy <= 65 else { return "\(label): perlu lokasi presisi dengan akurasi ≤65 m." }
            return nil
        }
        if problem == nil { problem = quality(own, label: "Lokasi Anda") }
        if problem == nil, case .person = destination { problem = quality(targetSample, label: "Lokasi tujuan") }
        return GroupRouteInput(scope: routingScope(for: audience), destination: destination, name: name,
                               origin: own.map(RouteCoordinate.init), target: target,
                               sourceRevision: own.flatMap { own in revision.map { own.epoch.uuidString + "|" + $0 } }, problem: problem)
    }
}

@MainActor @Observable final class GroupRouteSession {
    let engine: RouteLab
    private(set) var destination: GroupRouteDestination?
    private(set) var active = false
    private(set) var inputsReady = false
    private(set) var targetName = ""
    private(set) var waitingReason: String?
    private var scope: String?
    private var sourceRevision: String?

    init(engine: RouteLab? = nil) { self.engine = engine ?? RouteLab() }

    func enter(scope: String) {
        stop(); self.scope = scope
        engine.select(stage: .realGPS)
    }
    func start(_ input: GroupRouteInput, now: Date = .now, foreground: Bool = true) {
        engine.select(stage: .realGPS)
        scope = input.scope; destination = input.destination; sourceRevision = nil; active = true
        refresh(input, now: now, foreground: foreground)
    }
    func refresh(_ input: GroupRouteInput, now: Date, foreground: Bool) {
        guard active else { return }
        guard scope == input.scope, destination == input.destination else { stop(); return }
        if let revision = input.sourceRevision {
            if let previous = sourceRevision, previous != revision { engine.reset() }
            sourceRevision = revision
        }
        targetName = input.name
        waitingReason = foreground ? input.problem : "Routing dijeda saat app tidak aktif."
        inputsReady = foreground && input.problem == nil && input.origin != nil && input.target != nil
        engine.updateLive(origin: inputsReady ? input.origin?.coordinate : nil, target: inputsReady ? input.target?.coordinate : nil)
        if !inputsReady { engine.pause() }
        engine.tick(at: now)
        if inputsReady, !engine.running { engine.start() }
    }
    func stop() {
        active = false; inputsReady = false; destination = nil; waitingReason = nil; sourceRevision = nil
        engine.pause(); engine.reset()
    }
    var report: String {
        """
        Routing rombongan · tujuan \(destination.map { value in
            switch value { case .person: "orang"; case .activity: "kegiatan"; case .meeting: "meeting point" }
        } ?? "belum dipilih")
        Aktif: \(active) · input layak: \(inputsReady)
        Status: \(waitingReason ?? engine.status)
        Ambang umur sumber rombongan: \(Int(LocationRules.staleAfter)) detik, akurasi ≤65 m
        Nama, koordinat dan kredensial tidak dimasukkan dalam laporan routing ini.

        \(engine.report)
        """
    }
}
