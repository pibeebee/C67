import CoreLocation
import Foundation
import Observation

struct DiaryPin: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = "Sore di Monas"
    var creator = "Dara"
    var story = "Aku berhenti sebentar di sini saat langit mulai berubah warna. Kalau kamu ke sini suatu hari, ceritakan sore versimu lewat satu foto."
    var visitedAt = Date(timeIntervalSince1970: 1_714_953_600)
    var latitude = -6.175392
    var longitude = 106.827153
    var radius = 100.0
    var photo: Data?

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var location: CLLocation { .init(latitude: latitude, longitude: longitude) }
    var isValid: Bool {
        CLLocationCoordinate2DIsValid(coordinate) && latitude.isFinite && longitude.isFinite
            && radius.isFinite && (50 ... 300).contains(radius)
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !creator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum DiaryPresenceState: Equatable {
    case unavailable(String)
    case outside(Double)
    case uncertain(String)
    case inside(Double)

    var canAddPhoto: Bool { if case .inside = self { return true }; return false }
    var title: String {
        switch self {
        case .inside: "Kamu berada di titik ini"
        case .outside(let distance): distance >= 1000
            ? String(format: "%.1f km dari kenangan ini", distance / 1000)
            : "\(Int(distance.rounded())) m dari kenangan ini"
        case .uncertain: "Lokasi belum cukup pasti"
        case .unavailable: "Temukan posisimu"
        }
    }
    var explanation: String {
        switch self {
        case .inside: "Kini giliranmu meninggalkan foto dari tempat yang sama."
        case .outside: "Datangi titik ini untuk menambahkan jejak fotomu."
        case .uncertain(let message), .unavailable(let message): message
        }
    }
}

/// Experiment parameters, not Apple guarantees. Treat the accuracy circle conservatively.
enum DiaryPresencePolicy {
    static let maximumAge: TimeInterval = 5
    static let maximumAccuracy: CLLocationAccuracy = 35

    static func evaluate(_ sample: CLLocation?, pin: DiaryPin, precise: Bool,
                         now: Date = .now) -> DiaryPresenceState {
        guard pin.isValid else { return .unavailable("Lokasi pin belum valid.") }
        guard precise else { return .uncertain("Aktifkan Lokasi Tepat untuk memeriksa area pin.") }
        guard let sample else { return .unavailable("Aktifkan lokasi saat kamu siap menyusuri peta.") }
        let age = now.timeIntervalSince(sample.timestamp)
        guard age >= -1, age <= maximumAge else {
            return .uncertain("Menunggu posisi terbaru. Posisi lama tidak dipakai untuk unggahan.")
        }
        guard CLLocationCoordinate2DIsValid(sample.coordinate), sample.coordinate.latitude.isFinite,
              sample.coordinate.longitude.isFinite, sample.horizontalAccuracy.isFinite,
              sample.horizontalAccuracy >= 0 else {
            return .uncertain("Posisi belum valid. Coba lagi di area yang lebih terbuka.")
        }
        let distance = sample.distance(from: pin.location)
        let accuracy = sample.horizontalAccuracy
        guard accuracy <= min(maximumAccuracy, pin.radius / 2) else {
            return .uncertain("Sinyal lokasi belum akurat. Coba lagi di area yang lebih terbuka.")
        }
        if distance + accuracy <= pin.radius { return .inside(distance) }
        if distance - accuracy > pin.radius { return .outside(distance) }
        return .uncertain("Kamu dekat batas area. Mendekatlah ke pin lalu coba lagi.")
    }

    static func permitsUpload(_ sample: CLLocation?, pin: DiaryPin, precise: Bool,
                              requestedAt: Date, now: Date = .now) -> Bool {
        guard let sample, sample.timestamp >= requestedAt else { return false }
        return evaluate(sample, pin: pin, precise: precise, now: now).canAddPhoto
    }
}

struct DiaryFootprint: Codable, Identifiable {
    var id = UUID()
    let pinID: UUID
    let name: String
    let photo: Data
    let uploadedAt: Date
    let requestedAt: Date
    let measuredAt: Date
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let simulated: Bool
}

struct DiaryArchive: Codable {
    var pin = DiaryPin()
    var footprints: [DiaryFootprint] = []
}

enum DiaryError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let message): message } }
}

@MainActor @Observable final class DiaryStore {
    private(set) var archive = DiaryArchive()
    private(set) var loadError: String?
    private let url: URL?
    private var writable = true

    init(url: URL?) {
        self.url = url
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        do { archive = try JSONDecoder().decode(DiaryArchive.self, from: Data(contentsOf: url)) }
        catch {
            writable = false
            loadError = "Kenangan tersimpan belum dapat dibuka. File dipertahankan dan tidak ditimpa. \(error.localizedDescription)"
        }
    }

    static func live() -> DiaryStore {
        let directory = URL.applicationSupportDirectory.appending(path: "C6TravelDiary", directoryHint: .isDirectory)
        return DiaryStore(url: directory.appending(path: "memories-v1.json"))
    }

    var pin: DiaryPin { archive.pin }
    var footprints: [DiaryFootprint] { archive.footprints.filter { $0.pinID == pin.id } }

    func savePin(_ edited: DiaryPin) throws {
        guard edited.isValid else { throw DiaryError.message("Isi judul, nama, dan lokasi pin yang valid.") }
        var next = archive
        var pin = edited
        if pin.latitude != archive.pin.latitude || pin.longitude != archive.pin.longitude || pin.radius != archive.pin.radius {
            // Old footprints retain their original pin identity; moving a test pin never relocates proof.
            pin.id = UUID()
        }
        next.pin = pin
        try commit(next)
    }

    @discardableResult
    func addPhoto(_ photo: Data, name: String, sample: CLLocation, precise: Bool,
                  pinID: UUID, requestedAt: Date, simulated: Bool, now: Date = .now) throws -> DiaryFootprint {
        guard pinID == pin.id, DiaryPresencePolicy.permitsUpload(sample, pin: pin, precise: precise,
                                                                 requestedAt: requestedAt, now: now) else {
            throw DiaryError.message("Lokasimu belum terkonfirmasi di dalam area pin. Foto belum ditambahkan.")
        }
        guard !photo.isEmpty, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DiaryError.message("Pilih foto dan isi namamu terlebih dahulu.")
        }
        let footprint = DiaryFootprint(pinID: pin.id, name: name, photo: photo, uploadedAt: now,
                                       requestedAt: requestedAt, measuredAt: sample.timestamp,
                                       latitude: sample.coordinate.latitude, longitude: sample.coordinate.longitude,
                                       accuracy: sample.horizontalAccuracy, simulated: simulated)
        var next = archive
        next.footprints.insert(footprint, at: 0)
        try commit(next)
        return footprint
    }

    private func commit(_ next: DiaryArchive) throws {
        guard writable else { throw DiaryError.message(loadError ?? "Penyimpanan belum dapat digunakan.") }
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
        }
        archive = next // Publish only after the write succeeds.
    }
}
