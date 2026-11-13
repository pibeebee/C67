import CoreLocation
import Observation
import UIKit

@MainActor @Observable final class DiaryPresence: NSObject, CLLocationManagerDelegate {
    private(set) var latest: CLLocation?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var precise = true
    private(set) var running = false
    private(set) var checkingUpload = false
    private(set) var failure: String?
    private(set) var activated = false
    private(set) var demo: String?
    private let manager = CLLocationManager()
    private var session: CLServiceSession?
    private var timeout: Task<Void, Never>?
    private var uploadRequest: UploadRequest?

    private struct UploadRequest {
        let id: UUID
        let pin: DiaryPin
        let pressedAt: Date
        let complete: (Result<(CLLocation, Date, Bool), Error>) -> Void
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.allowsBackgroundLocationUpdates = false
        authorization = manager.authorizationStatus
        precise = manager.accuracyAuthorization == .fullAccuracy
        #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "--diary-demo"), args.indices.contains(i + 1),
               ["inside", "outside", "uncertain"].contains(args[i + 1]) {
                demo = args[i + 1]
            }
        #endif
    }

    var simulated: Bool {
        #if targetEnvironment(simulator)
            return true
        #else
            return demo != nil || latest?.sourceInformation?.isSimulatedBySoftware == true
        #endif
    }
    var blocked: Bool { authorization == .denied || authorization == .restricted }

    func state(for pin: DiaryPin, now: Date = .now) -> DiaryPresenceState {
        if let failure { return .unavailable(failure) }
        if blocked { return .unavailable("Izinkan lokasi melalui Pengaturan untuk menambahkan jejak di tempat ini.") }
        return DiaryPresencePolicy.evaluate(latest, pin: pin, precise: precise, now: now)
    }

    func start(pin: DiaryPin) {
        activated = true
        failure = nil
        if demo != nil {
            authorization = .authorizedWhenInUse
            running = true
            refreshDemo(pin: pin)
            return
        }
        if session == nil { session = CLServiceSession(authorization: .whenInUse) }
        authorization = manager.authorizationStatus
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        startIfAuthorized()
    }

    func stop() {
        manager.stopUpdatingLocation()
        session?.invalidate()
        session = nil
        running = false
        latest = nil
        cancelUpload()
    }

    func cancelUpload() {
        guard uploadRequest != nil else { return }
        finish(.failure(DiaryError.message("Pemeriksaan lokasi dibatalkan. Foto belum ditambahkan.")))
    }

    func verifyUpload(pin: DiaryPin, completion: @escaping (Result<(CLLocation, Date, Bool), Error>) -> Void) {
        guard !checkingUpload else { return }
        guard running, !blocked else {
            completion(.failure(DiaryError.message("Aktifkan lokasi dahulu untuk memeriksa kehadiranmu.")))
            return
        }
        let pressedAt = Date.now
        let atPress = state(for: pin, now: pressedAt)
        guard atPress.canAddPhoto else {
            completion(.failure(DiaryError.message(atPress.explanation)))
            return
        }
        let request = UploadRequest(id: UUID(), pin: pin, pressedAt: pressedAt, complete: completion)
        uploadRequest = request
        checkingUpload = true
        failure = nil
        // Never reuse the arrival/unlock sample. Require a fix measured after this tap.
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, self.uploadRequest?.id == request.id else { return }
            self.finish(.failure(DiaryError.message("Posisi terbaru belum diterima. Coba lagi di area terbuka; foto tetap tersimpan di pratinjau.")))
        }
        if demo != nil { refreshDemo(pin: pin); considerUpload() }
        // Standard updates are already running. requestLocation() would do nothing here.
    }

    private func startIfAuthorized() {
        guard activated else { return }
        if authorization == .authorizedWhenInUse || authorization == .authorizedAlways {
            precise = manager.accuracyAuthorization == .fullAccuracy
            running = true
            manager.startUpdatingLocation()
        } else if blocked {
            stop()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard demo == nil else { return }
        authorization = manager.authorizationStatus
        precise = manager.accuracyAuthorization == .fullAccuracy
        startIfAuthorized()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard running, demo == nil, let location = locations.max(by: { $0.timestamp < $1.timestamp }),
              latest == nil || location.timestamp >= latest!.timestamp else { return }
        latest = location
        precise = manager.accuracyAuthorization == .fullAccuracy
        failure = nil
        considerUpload()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard running else { return }
        failure = "Lokasi belum dapat dibaca. Coba aktifkan lagi lokasi atau pindah ke area terbuka."
        latest = nil
        finish(.failure(error))
    }

    private func considerUpload() {
        guard let request = uploadRequest, let sample = latest, sample.timestamp >= request.pressedAt else { return }
        let state = DiaryPresencePolicy.evaluate(sample, pin: request.pin, precise: precise)
        guard DiaryPresencePolicy.permitsUpload(sample, pin: request.pin, precise: precise, requestedAt: request.pressedAt) else {
            finish(.failure(DiaryError.message(state.explanation)))
            return
        }
        finish(.success((sample, request.pressedAt, simulated)))
    }

    private func finish(_ result: Result<(CLLocation, Date, Bool), Error>) {
        timeout?.cancel()
        timeout = nil
        let callback = uploadRequest?.complete
        uploadRequest = nil
        checkingUpload = false
        callback?(result)
    }

    func refreshDemo(pin: DiaryPin) {
        guard let demo, running else { return }
        latest = CLLocation(coordinate: .init(latitude: pin.latitude + (demo == "outside" ? 0.004 : 0), longitude: pin.longitude),
                            altitude: 0, horizontalAccuracy: demo == "uncertain" ? 150 : 5,
                            verticalAccuracy: 5, timestamp: .now)
    }
}
