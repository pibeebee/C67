import Foundation
import Observation
import UIKit

struct DiagnosticEntry: Codable, Identifiable {
    var id = UUID(); var at = Date(); var event: String
}

struct FreshnessObservation: Codable {
    var at: Date
    var sampleAge: Double?
}

@MainActor @Observable final class POCDiagnostics {
    private(set) var entries: [DiagnosticEntry] = []
    private(set) var observations: [FreshnessObservation] = []
    private(set) var uniqueReceives: [Date] = []
    private(set) var receiveAges: [Double] = []
    private(set) var startedAt = Date()
    private var startBattery: Float = -1
    var scenario = "Foreground"
    init() { UIDevice.current.isBatteryMonitoringEnabled = true; startBattery = UIDevice.current.batteryLevel }
    func log(_ event: String) {
        entries.append(DiagnosticEntry(event: event))
        if entries.count > 1000 { entries.removeFirst(entries.count - 1000) }
    }
    func received(_ sample: LocationSample, at: Date = .now) {
        uniqueReceives.append(at); receiveAges.append(at.timeIntervalSince(sample.measuredAt))
        log("receive sequence=\(sample.sequence) accuracy=\(Int(sample.accuracy))m reduced=\(sample.reduced)")
    }
    func observe(_ sample: LocationSample?, at: Date = .now) {
        let age = sample.flatMap { $0.valid && $0.measuredAt <= at.addingTimeInterval(5) ? max(0, at.timeIntervalSince($0.measuredAt)) : nil }
        observations.append(FreshnessObservation(at: at, sampleAge: age))
    }
    func reset() { entries = []; observations = []; uniqueReceives = []; receiveAges = []; startedAt = .now; startBattery = UIDevice.current.batteryLevel; log("Mulai pengukuran; warm-up 60 detik") }
    func report(run: RunState) -> String {
        let valid = observations.filter { $0.at.timeIntervalSince(startedAt) >= 60 }
        func percent(_ limit: Double) -> Double {
            guard !valid.isEmpty else { return 0 }
            return Double(valid.filter { ($0.sampleAge ?? .infinity) <= limit }.count) / Double(valid.count) * 100
        }
        let ages = receiveAges.filter { $0 >= 0 }.sorted()
        func percentile(_ p: Double) -> String { ages.isEmpty ? "n/a" : String(format: "%.1f", ages[min(ages.count - 1, Int(Double(ages.count - 1) * p))]) }
        let gaps = zip(uniqueReceives, uniqueReceives.dropFirst()).map { $1.timeIntervalSince($0) }
        let leadingGap = (uniqueReceives.first ?? .now).timeIntervalSince(startedAt)
        let trailingGap = Date.now.timeIntervalSince(uniqueReceives.last ?? startedAt)
        let longest = max(gaps.max() ?? 0, leadingGap, trailingGap)
        let battery = UIDevice.current.batteryLevel
        let duration = Date.now.timeIntervalSince(startedAt)
        let expectedObservations = max(1, Int(max(0, duration - 60) / 30))
        let coverage = min(1, Double(valid.count) / Double(expectedObservations))
        let gate = scenario == "Foreground" ? (duration >= 660 && uniqueReceives.count >= 10 && percent(60) >= 90) :
            (duration >= 1260 && uniqueReceives.count >= 10 && percent(90) >= 90 && longest <= 180)
        let status = run.mode == .simulation ? "SIMULASI: bukan bukti H1/H2" : valid.isEmpty || coverage < 0.9 || duration < (scenario == "Foreground" ? 660 : 1260) ? "INCONCLUSIVE: durasi/sampel/coverage belum cukup; TL harus foreground" :
            (gate ? "Memenuhi gate diagnostik run ini; ulangi konfigurasi sebelum simpulan" : "Belum memenuhi gate diagnostik")
        let events = entries.map { "\($0.at.ISO8601Format()) \($0.event)" }.joined(separator: "\n")
        return """
        POC C67 — metadata saja, tanpa koordinat/email
        Run: \(run.runID.uuidString)
        Scope: peserta lokasi yang dipilih; bukan agregat rombongan. Pilihan berubah mereset pengukuran.
        Mode: \(run.mode.rawValue); skenario: \(scenario)
        Perangkat: \(UIDevice.current.model); OS: \(UIDevice.current.systemVersion)
        Build: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "?")
        Mulai: \(startedAt.ISO8601Format()); durasi: \(Int(duration)) detik
        Parameter: upload >=20s; fetch TL 15s foreground; observasi 30s; stale 60s
        Unique samples: \(uniqueReceives.count); observasi setelah warm-up: \(valid.count)
        Coverage observasi: \(String(format: "%.0f", coverage * 100))% (TL wajib foreground)
        Umur saat receive p50/p95 (detik; bukan latency upload murni): \(percentile(0.5))/\(percentile(0.95))
        Observasi umur <=60s: \(String(format: "%.1f", percent(60)))%; <=90s: \(String(format: "%.1f", percent(90)))%
        Gap terpanjang termasuk awal/akhir: \(Int(longest)) detik
        Baterai awal/akhir: \(startBattery)/\(battery) (-1 berarti tidak tersedia)
        Gate: \(status)
        Model iPhone, izin, jaringan, Precise, Low Power Mode, lingkungan dan debugger: isi manual saat evaluasi.
        P01–P15: belum dinyatakan lulus otomatis. GPS/background/ACL perlu perangkat fisik.
        \(events)
        """
    }
}
