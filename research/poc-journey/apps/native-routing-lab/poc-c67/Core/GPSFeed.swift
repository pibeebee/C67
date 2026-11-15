import Foundation
import CoreLocation
import Observation

@MainActor @Observable final class GPSFeed {
    private(set) var status = "GPS belum dimulai"
    private(set) var latest: LiveSample?
    private(set) var accepted = 0
    private(set) var rejected = 0
    private(set) var backgroundFixes = 0
    var inBackground = false
    @ObservationIgnored var onSample: ((LiveSample) -> Void)?
    @ObservationIgnored var onUnavailable: (() -> Void)?
    private let authorizationReader = CLLocationManager()
    private var service: CLServiceSession?
    private var background: CLBackgroundActivitySession?
    private var task: Task<Void, Never>?
    var authorization: String {
        switch authorizationReader.authorizationStatus {
        case .notDetermined: "Belum dipilih"
        case .denied: "Ditolak — buka Settings"
        case .restricted: "Dibatasi sistem"
        case .authorizedWhenInUse: "When In Use"
        case .authorizedAlways: "Always"
        @unknown default: "Tidak diketahui"
        }
    }
    var reducedAccuracy: Bool { authorizationReader.accuracyAuthorization == .reducedAccuracy }

    func start(backgroundEnabled: Bool) {
        stop(); latest = nil
        status = "Menunggu izin dan GPS"
        service = CLServiceSession(authorization: .whenInUse)
        if backgroundEnabled { background = CLBackgroundActivitySession() }
        task = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.default) {
                    guard let self, !Task.isCancelled else { return }
                    if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                        self.status = "Izin GPS tidak tersedia — buka Settings untuk mengizinkan lokasi"
                        self.stop(); self.onUnavailable?(); return
                    }
                    guard let location = update.location else { continue }
                    #if targetEnvironment(simulator)
                        let synthetic = true
                    #else
                        let synthetic = location.sourceInformation?.isSimulatedBySoftware ?? false
                    #endif
                    let sample = LiveSample(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                            accuracy: location.horizontalAccuracy, measuredAt: location.timestamp,
                                            simulated: synthetic)
                    guard sample.usable(at: .now), self.latest.map({ sample.measuredAt > $0.measuredAt }) ?? true else {
                        self.rejected += 1; self.status = "Sampel ditolak: umur, akurasi >65 m, atau urutan waktu"; continue
                    }
                    self.latest = sample; self.accepted += 1
                    if self.inBackground { self.backgroundFixes += 1 }
                    self.status = sample.simulated ? "Lokasi Core Location sintetis (Simulator/GPX)" : "GPS diterima"
                    self.onSample?(sample)
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.status = "GPS gagal: \(error.localizedDescription)"
                self.stop(); self.onUnavailable?()
            }
        }
    }
    func stop() {
        task?.cancel(); task = nil
        background?.invalidate(); background = nil
        service?.invalidate(); service = nil
    }
}
