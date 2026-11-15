import CoreLocation
import Observation

@MainActor @Observable final class LocationService {
    private(set) var running = false
    private(set) var latest: LocationSample?
    private(set) var status = "Belum dimulai"
    private let authorizationReader = CLLocationManager()
    private var serviceSession: CLServiceSession?
    private var backgroundSession: CLBackgroundActivitySession?
    private var task: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    var onSample: ((LocationSample) -> Void)?
    var onEvent: ((String) -> Void)?
    var onExpiration: (() -> Void)?
    var authorization: String {
        switch authorizationReader.authorizationStatus {
        case .notDetermined: "Belum dipilih"
        case .denied: "Ditolak"
        case .restricted: "Dibatasi sistem"
        case .authorizedWhenInUse: "When In Use"
        case .authorizedAlways: "Always (pilihan pengguna)"
        @unknown default: "Tidak diketahui"
        }
    }
    var reduced: Bool { authorizationReader.accuracyAuthorization == .reducedAccuracy }
    func start(runID: UUID, epoch: UUID, expiresAt: Date, background: Bool) {
        stop(); latest = nil; running = true; status = "Menunggu izin dan sampel"
        serviceSession = CLServiceSession(authorization: .whenInUse)
        if background { backgroundSession = CLBackgroundActivitySession() }
        onEvent?("Sensor start; background=\(background); expires=\(expiresAt.ISO8601Format())")
        expiryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, expiresAt.timeIntervalSinceNow))) } catch { return }
            guard let self, self.running else { return }
            self.stop(); self.status = "Sesi berbagi berakhir"; self.onExpiration?()
        }
        task = Task { [weak self] in
            var sequence = 0
            do {
                for try await update in CLLocationUpdate.liveUpdates(.default) {
                    guard let self, !Task.isCancelled, self.running else { return }
                    if Date.now >= expiresAt { self.stop(); self.onExpiration?(); return }
                    if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                        self.status = "Izin lokasi tidak tersedia; pemeriksaan manual tetap berjalan"
                        self.onEvent?("Sensor authorization unavailable")
                        self.stop(); self.onExpiration?(); return
                    }
                    guard let location = update.location else {
                        self.status = "Menunggu lokasi; izin: \(self.authorization)"
                        continue
                    }
                    if let previous = self.latest, location.timestamp <= previous.measuredAt { continue }
                    sequence += 1
                    let sample = LocationSample(runID: runID, epoch: epoch, sequence: sequence,
                                                latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                                measuredAt: location.timestamp, accuracy: location.horizontalAccuracy,
                                                reduced: self.reduced, simulated: location.sourceInformation?.isSimulatedBySoftware ?? false)
                    guard sample.valid else { self.onEvent?("Sensor invalid accuracy/coordinate"); continue }
                    self.latest = sample; self.status = "Sampel diterima · \(self.authorization)"
                    self.onEvent?("sensor sequence=\(sequence) accuracy=\(Int(sample.accuracy))m reduced=\(sample.reduced) simulated=\(sample.simulated)")
                    self.onSample?(sample)
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.status = "Sensor gagal: \(error.localizedDescription)"; self.onEvent?("Sensor error")
                self.stop(); self.onExpiration?()
            }
        }
    }
    func stop() {
        running = false
        task?.cancel(); task = nil; expiryTask?.cancel(); expiryTask = nil
        backgroundSession?.invalidate(); backgroundSession = nil
        serviceSession?.invalidate(); serviceSession = nil
    }
}
