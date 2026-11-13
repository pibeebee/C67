import Foundation
import Network
import Observation

/// Bonjour/TCP transports AES-GCM authenticated frames; the pairing secret is never advertised.
/// One target and one navigator per session. No internet relay and no persistent location storage.
@MainActor @Observable final class LocalLocationChannel {
    static let serviceType = "_dds-route._tcp"
    private(set) var status = "Koneksi belum dimulai"
    private(set) var connected = false
    private(set) var sent = 0
    private(set) var received = 0
    private(set) var rejected = 0
    @ObservationIgnored var onSample: ((LiveSample) -> Void)?
    @ObservationIgnored var onConnection: ((Bool) -> Void)?
    @ObservationIgnored var onRemoteStop: (() -> Void)?
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var endpoints: [NWEndpoint] = []
    private var ticket: PairingTicket?
    private var host = false
    private var buffer = Data()
    private var epoch: UUID?
    private var challenge: UUID?
    private var sequence = 0
    private var lastReceived = -1
    private var generation = UUID()
    private var retry: Task<Void, Never>?
    private var handshake: Task<Void, Never>?

    private func parameters() -> NWParameters {
        let p = NWParameters.tcp
        p.includePeerToPeer = true
        return p
    }
    func startHost(ticket: PairingTicket) {
        stop(); self.ticket = ticket; host = true
        let run = generation
        do {
            let listener = try NWListener(using: parameters())
            self.listener = listener
            listener.service = .init(name: ticket.service, type: Self.serviceType)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == run else { return }
                    switch state {
                    case .ready: if !self.connected { self.status = "Menunggu Navigator dengan kode pairing" }
                    case .failed(let error): self.status = "Listener gagal: \(error.localizedDescription)"; self.listener?.cancel()
                    case .waiting(let error): self.status = "Menunggu jaringan/izin lokal: \(error.localizedDescription)"
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] c in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == run, self.connection == nil else { c.cancel(); return }
                    self.attach(c)
                }
            }
            listener.start(queue: .main)
            status = "Membuka sesi Target"
        } catch { status = "Listener gagal: \(error.localizedDescription)" }
    }
    func startNavigator(ticket: PairingTicket) {
        stop(); self.ticket = ticket; host = false
        let run = generation
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters())
        self.browser = browser
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.generation == run else { return }
                switch state {
                case .failed(let error), .waiting(let error): self.status = "Pencarian menunggu/gagal: \(error.localizedDescription). Periksa izin Local Network."
                default: break
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == run else { return }
                self.endpoints = results.compactMap { result in
                    if case .service(let name, _, _, _) = result.endpoint, name == ticket.service { return result.endpoint }
                    return nil
                }
                self.connectIfAvailable()
            }
        }
        browser.start(queue: .main)
        status = "Mencari Target di jaringan lokal…"
    }
    private func connectIfAvailable() {
        guard !host, connection == nil, let endpoint = endpoints.first else { return }
        attach(NWConnection(to: endpoint, using: parameters()))
    }
    private func attach(_ c: NWConnection) {
        connection = c; buffer = Data(); epoch = host ? UUID() : nil; lastReceived = -1; sequence = 0
        challenge = host ? nil : UUID()
        status = "Menghubungkan dan memverifikasi pairing…"
        let run = generation
        c.stateUpdateHandler = { [weak self, weak c] state in
            Task { @MainActor [weak self, weak c] in
                guard let self, let c, self.generation == run, self.connection === c else { return }
                switch state {
                case .ready:
                    if self.host { self.send(kind: "hello") }
                    self.receive(on: c, run: run)
                case .failed(let error), .waiting(let error):
                    self.status = "Koneksi terputus: \(error.localizedDescription)"; self.disconnected(c)
                case .cancelled: self.disconnected(c)
                default: break
                }
            }
        }
        c.start(queue: .main)
        handshake = Task { [weak self, weak c] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard let self, let c, self.connection === c, !self.connected else { return }
            self.status = "Pairing timeout. Periksa kode, jaringan, dan izin Local Network."
            self.disconnected(c)
        }
    }
    private func receive(on c: NWConnection, run: UUID) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self, weak c] data, _, complete, error in
            Task { @MainActor [weak self, weak c] in
                guard let self, let c, self.generation == run, self.connection === c else { return }
                do {
                    if let data {
                        self.buffer.append(data)
                        while let payload = try LocationWire.popFrame(from: &self.buffer) {
                            guard let key = self.ticket?.key else { return }
                            let message = try LocationWire.open(payload, key: key)
                            try self.handle(message)
                        }
                        guard self.buffer.count <= LocationWire.maximumFrame + 4 else { throw CocoaError(.coderInvalidValue) }
                    }
                } catch {
                    self.rejected += 1; self.status = "Pairing/paket ditolak. Gunakan kode sesi yang benar."
                    self.disconnected(c); return
                }
                if complete || error != nil { self.status = "Peer terputus; mencari koneksi kembali"; self.disconnected(c) }
                else { self.receive(on: c, run: run) }
            }
        }
    }
    private func handle(_ message: LocationEnvelope) throws {
        if !host, epoch == nil, message.kind == "hello" {
            epoch = message.epoch; lastReceived = message.sequence
            send(kind: "ack"); return
        }
        guard message.epoch == epoch, message.sequence > lastReceived else { throw CocoaError(.coderInvalidValue) }
        lastReceived = message.sequence
        if host, !connected, message.kind == "ack", let nonce = message.challenge {
            challenge = nonce; send(kind: "ready"); authenticated(); return
        }
        guard message.challenge == challenge else { throw CocoaError(.coderInvalidValue) }
        if !host, !connected, message.kind == "ready" { authenticated(); return }
        guard connected else { throw CocoaError(.coderInvalidValue) }
        if message.kind == "stop" { onRemoteStop?(); return }
        guard !host, message.kind == "location", let sample = message.sample else { throw CocoaError(.coderInvalidValue) }
        guard sample.usable(at: .now) else { rejected += 1; status = "GPS Target terlalu lama/tidak akurat; menunggu sampel baru"; return }
        received += 1; onSample?(sample)
    }
    private func authenticated() {
        handshake?.cancel(); handshake = nil
        connected = true; status = "Terhubung · pairing terverifikasi · lokasi terenkripsi"
        onConnection?(true)
    }
    func publish(_ sample: LiveSample) {
        guard host, connected, sample.usable(at: .now) else { return }
        send(kind: "location", sample: sample); sent += 1
    }
    private func send(kind: String, sample: LiveSample? = nil) {
        guard let c = connection, let ticket, let epoch else { return }
        sequence += 1
        do {
            let data = try LocationWire.seal(.init(kind: kind, epoch: epoch, sequence: sequence, sample: sample, challenge: challenge), key: ticket.key)
            let run = generation
            c.send(content: data, completion: .contentProcessed { [weak self, weak c] error in
                guard error != nil else { return }
                Task { @MainActor [weak self, weak c] in
                    guard let self, let c, self.generation == run, self.connection === c else { return }
                    self.status = "Pengiriman gagal"; self.disconnected(c)
                }
            })
        } catch { status = "Enkripsi paket gagal"; disconnected(c) }
    }
    private func disconnected(_ c: NWConnection) {
        guard connection === c else { return }
        connection = nil; c.stateUpdateHandler = nil; c.cancel(); connected = false
        buffer = Data(); epoch = nil; challenge = nil; handshake?.cancel(); handshake = nil
        onConnection?(false)
        guard !host else { return }
        retry?.cancel()
        let run = generation
        retry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, self.generation == run else { return }
            self.connectIfAvailable()
        }
    }
    // Recreate a failed discovery/listener when returning from suspension. Active connections remain intact.
    func resume() {
        guard !connected, let ticket else { return }
        if host {
            if listener == nil { startHost(ticket: ticket); return }
            if let state = listener?.state {
                switch state {
                case .failed, .cancelled: startHost(ticket: ticket)
                default: break
                }
            }
        } else {
            if browser == nil { startNavigator(ticket: ticket); return }
            if let state = browser?.state {
                switch state {
                case .failed, .cancelled: startNavigator(ticket: ticket)
                default: connectIfAvailable()
                }
            }
        }
    }
    func stop() {
        generation = UUID(); retry?.cancel(); retry = nil; handshake?.cancel(); handshake = nil
        listener?.cancel(); listener = nil; browser?.cancel(); browser = nil
        connection?.stateUpdateHandler = nil; connection?.cancel(); connection = nil
        connected = false; ticket = nil; buffer = Data(); epoch = nil; challenge = nil; endpoints = []
        status = "Koneksi dihentikan"; onConnection?(false)
    }
}
