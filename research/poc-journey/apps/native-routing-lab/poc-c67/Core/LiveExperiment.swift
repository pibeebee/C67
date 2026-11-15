import Foundation
import CoreLocation
import Observation
import OSLog

enum DeviceRole: String, CaseIterable, Identifiable {
    case navigator, target
    var id: String { rawValue }
    var title: String { self == .navigator ? "A · Navigator" : "B · Target" }
}

@MainActor @Observable final class LiveExperiment {
    let stage: ExperimentStage
    let gps = GPSFeed()
    let channel = LocalLocationChannel()
    let routing: RouteLab
    var role: DeviceRole = .navigator
    var enteredCode = ""
    private(set) var pairingCode = ""
    private(set) var active = false
    private(set) var foreground = true
    private(set) var now = Date()
    private(set) var remote: LiveSample?
    private(set) var remoteReceivedAt: Date?
    private(set) var note = "Mulai sesi untuk meminta izin GPS"
    private(set) var expiresAt: Date?
    private(set) var backgroundReceived = 0
    private(set) var log: [String] = []
    private var anchor: CLLocationCoordinate2D?
    private var syntheticStartedAt: Date?
    private var lastSentAt: Date?
    private var lastSent: LiveSample?
    private var expiry: Task<Void, Never>?

    init(stage: ExperimentStage, routing: RouteLab) {
        self.routing = routing
        self.stage = stage
        gps.onSample = { [weak self] sample in self?.accepted(sample) }
        gps.onUnavailable = { [weak self] in self?.stop(reason: "GPS tidak tersedia; sesi dihentikan") }
        channel.onSample = { [weak self] sample in
            guard let self, self.active, self.role == .navigator else { return }
            guard self.remote.map({ sample.measuredAt >= $0.measuredAt }) ?? true else { return }
            self.remote = sample; self.remoteReceivedAt = .now
            if !self.foreground { self.backgroundReceived += 1; self.record("Paket lokasi diterima saat background") }
            self.refresh(at: .now)
        }
        channel.onConnection = { [weak self] connected in
            guard let self, self.active else { return }
            self.record(connected ? "Peer terverifikasi" : "Peer terputus; rute menunggu data segar")
            if connected, self.role == .target, let sample = self.gps.latest { self.publish(sample, at: .now) }
            self.refresh(at: .now)
        }
        channel.onRemoteStop = { [weak self] in self?.stop(reason: "Peer menghentikan sesi") }
    }
    var targetRole: Bool { stage != .realGPS && role == .target }
    var localUsable: Bool { active && gps.latest?.usable(at: now) == true }
    var remoteUsable: Bool {
        active && channel.connected && remote?.usable(at: now) == true
            && remoteReceivedAt.map { (0 ... 30).contains(now.timeIntervalSince($0)) } == true
    }
    var origin: CLLocationCoordinate2D? { targetRole ? nil : gps.latest?.coordinate }
    var target: CLLocationCoordinate2D? {
        if stage == .realGPS { return syntheticTarget }
        return targetRole ? gps.latest?.coordinate : remote?.coordinate
    }
    var syntheticTarget: CLLocationCoordinate2D? {
        guard let anchor, let syntheticStartedAt else { return nil }
        // Deliberately synthetic geometry, anchored near the first accepted GPS fix.
        let lat = anchor.latitude, lon = anchor.longitude
        let scale = max(0.1, cos(lat * .pi / 180))
        let path = SimulationPath([(lat + 0.0022, lon), (lat + 0.0022, lon + 0.002 / scale),
                                   (lat + 0.0005, lon + 0.002 / scale)])
        return path.coordinate(at: max(0, now.timeIntervalSince(syntheticStartedAt)) * 1.4)
    }
    var inputsReady: Bool { localUsable && (stage == .realGPS ? syntheticTarget != nil : remoteUsable) && !targetRole }
    var report: String {
        """
        Dynamic Destination · \(stage.title) · \(role.title)
        GPS: \(gps.status) · izin \(gps.authorization) · reduced accuracy \(gps.reducedAccuracy)
        Aktif: \(active) · foreground: \(foreground)
        GPS diterima/ditolak/background: \(gps.accepted)/\(gps.rejected)/\(gps.backgroundFixes)
        Kanal: \(channel.status)
        Lokasi dikirim/diterima: \(channel.sent)/\(channel.received) · paket ditolak \(channel.rejected)
        Diterima saat background: \(backgroundReceived)
        Target segar: \(remoteUsable) · input routing siap: \(inputsReady)
        Sesi berakhir: \(expiresAt?.ISO8601Format() ?? "—")
        Kode pairing dan koordinat tidak dimasukkan dalam laporan ini.

        \(routing.report)

        \(log.joined(separator: "\n"))
        """
    }
    func start() {
        guard !active, foreground else { return }
        let ticket: PairingTicket?
        if stage != .realGPS && role == .navigator {
            guard let parsed = PairingTicket(code: enteredCode) else {
                note = "Tempel kode lengkap dari iPhone B sebelum Mulai"; return
            }
            ticket = parsed
        } else { ticket = stage == .realGPS ? nil : PairingTicket() }
        active = true; now = .now; expiresAt = now.addingTimeInterval(1800)
        remote = nil; remoteReceivedAt = nil; anchor = nil; syntheticStartedAt = nil
        lastSentAt = nil; lastSent = nil; routing.select(stage: stage)
        note = "Sesi aktif · maksimum 30 menit · Hentikan untuk mengakhiri GPS dan koneksi"
        record("Mulai \(stage.title), \(role.title)")
        if let ticket {
            if role == .target { pairingCode = ticket.code; channel.startHost(ticket: ticket) }
            else { channel.startNavigator(ticket: ticket) }
        }
        gps.start(backgroundEnabled: stage == .backgroundTracking)
        if !targetRole { routing.start() }
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1800)) } catch { return }
            self?.stop(reason: "Batas sesi 30 menit tercapai")
        }
    }
    func stop(reason: String = "Sesi dihentikan oleh pengguna") {
        active = false
        gps.stop(); channel.stop()
        if routing.stage == stage { routing.pause(); routing.updateLive(origin: nil, target: nil) }
        expiry?.cancel(); expiry = nil; expiresAt = nil; pairingCode = ""
        note = reason; record(reason)
    }
    func setForeground(_ value: Bool) {
        foreground = value; gps.inBackground = !value
        guard active else { return }
        record(value ? "Kembali foreground" : "Masuk background")
        if !value {
            routing.pause()
            if stage != .backgroundTracking { stop(reason: "Tahap 3–4 berhenti saat background. Tekan Mulai untuk sesi baru.") }
        } else {
            channel.resume()
            refresh(at: .now)
            if active, !targetRole { routing.start() }
        }
    }
    func refresh(at date: Date) {
        now = date
        guard active else { return }
        if let expiresAt, date >= expiresAt { stop(reason: "Batas sesi 30 menit tercapai"); return }
        routing.updateLive(origin: inputsReady ? origin : nil, target: inputsReady ? target : nil)
        if foreground, !targetRole { routing.tick(at: date) }
        if targetRole, let sample = gps.latest, sample.usable(at: date),
           lastSentAt.map({ date.timeIntervalSince($0) >= 10 }) ?? true { publish(sample, at: date) }
    }
    private func accepted(_ sample: LiveSample) {
        guard active else { return }
        if let expiresAt, Date.now >= expiresAt { stop(reason: "Batas sesi 30 menit tercapai"); return }
        if !foreground { record("Sampel Core Location diterima saat background") }
        if anchor == nil { anchor = sample.coordinate; syntheticStartedAt = .now }
        if targetRole {
            let interval = lastSentAt.map { Date.now.timeIntervalSince($0) } ?? .infinity
            let moved = lastSent.map { meters(sample.coordinate, $0.coordinate) } ?? .infinity
            if interval >= 2, moved >= 3 || interval >= 10 { publish(sample, at: .now) }
        }
        refresh(at: .now)
    }
    private func publish(_ sample: LiveSample, at date: Date) {
        guard channel.connected else { return }
        channel.publish(sample); lastSentAt = date; lastSent = sample
    }
    private func record(_ message: String) {
        Logger(subsystem: "giovanchristoffel.poc-c67", category: "LiveExperiment").info("\(message, privacy: .public)")
        log.insert("\(Date.now.ISO8601Format()) · \(message)", at: 0)
        if log.count > 100 { log.removeLast(log.count - 100) }
    }
}
