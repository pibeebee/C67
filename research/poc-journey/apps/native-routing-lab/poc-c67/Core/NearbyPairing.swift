import Foundation
import MultipeerConnectivity
import Observation

@MainActor @Observable final class NearbyPairing: NSObject {
    static let service = "c67-pair"
    private(set) var status = "Belum dimulai"
    private(set) var active = false
    var onMessage: ((PairingEnvelope, MCPeerID) -> Void)?
    var onConnect: ((MCPeerID) -> Void)?
    var onDisconnect: ((MCPeerID) -> Void)?
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var invite: JourneyInvite?
    private var host = false
    private var invited = Set<MCPeerID>()
    private var timeout: Task<Void, Never>?
    private var generation = UUID()

    func start(invite: JourneyInvite, hosting: Bool) throws {
        try invite.validate()
        stop(); self.invite = invite; host = hosting; active = true
        let peer = MCPeerID(displayName: "C67-" + String(UUID().uuidString.prefix(8)))
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self; self.session = session
        if hosting {
            let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: ["journey": invite.discoveryID], serviceType: Self.service)
            advertiser.delegate = self; self.advertiser = advertiser; advertiser.startAdvertisingPeer()
            status = "QR aktif. Menunggu peserta di dekat TL."
        } else {
            let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.service)
            browser.delegate = self; self.browser = browser; browser.startBrowsingForPeers()
            status = "Mencari iPhone TL di sekitar…"
        }
        let deadline = hosting ? invite.expiresAt : min(invite.expiresAt, .now.addingTimeInterval(120))
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            self.stop(); self.status = hosting ? "QR kedaluwarsa. Tampilkan QR baru." : "Pairing belum selesai. Periksa jaringan lokal dan coba scan ulang. Jika share sudah dibuat, selesaikan cleanup dahulu."
        }
    }
    func stop() {
        generation = UUID(); timeout?.cancel(); timeout = nil
        advertiser?.stopAdvertisingPeer(); browser?.stopBrowsingForPeers()
        advertiser = nil; browser = nil; session?.disconnect(); session = nil
        invited.removeAll(); active = false; invite = nil; onConnect = nil; onMessage = nil; onDisconnect = nil
    }
    func send(_ message: PairingEnvelope, to peer: MCPeerID) throws {
        guard let session, session.connectedPeers.contains(peer) else { throw POCError.message("Koneksi lokal terputus. Scan ulang di dekat TL.") }
        let data = try JSONEncoder().encode(message)
        guard data.count < 8192 else { throw POCError.message("Pesan pairing terlalu besar.") }
        try session.send(data, toPeers: [peer], with: .reliable)
    }
    func fail(_ text: String) { status = text }
    private func connected(_ peer: MCPeerID, state: MCSessionState, from source: MCSession) {
        guard source === session else { return }
        if state == .connected { status = "Terhubung lokal; menyiapkan akses iCloud privat…"; onConnect?(peer) }
        if state == .notConnected { onDisconnect?(peer) }
        if state == .notConnected, !host { status = "Koneksi lokal terputus. Jika belum terhubung, scan ulang." }
    }
}

extension NearbyPairing: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor [weak self] in
            guard let self, advertiser === self.advertiser, self.active, self.host, let invite = self.invite, invite.expiresAt > .now,
                  context == Data(invite.token.utf8), let session = self.session, session.connectedPeers.count < 6 else { invitationHandler(false, nil); return }
            invitationHandler(true, session)
        }
    }
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor [weak self] in
            guard let self, advertiser === self.advertiser else { return }
            self.status = "Tidak dapat membuka pairing. Izinkan Jaringan Lokal di Pengaturan dan aktifkan Wi-Fi/Bluetooth."
        }
    }
}
extension NearbyPairing: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor [weak self] in
            guard let self, browser === self.browser, let invite = self.invite, info?["journey"] == invite.discoveryID,
                  !self.invited.contains(peerID), let session = self.session else { return }
            self.invited.insert(peerID)
            browser.invitePeer(peerID, to: session, withContext: Data(invite.token.utf8), timeout: 30)
        }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in self?.invited.remove(peerID) }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor [weak self] in
            guard let self, browser === self.browser else { return }
            self.status = "Pencarian gagal. Izinkan Jaringan Lokal di Pengaturan dan aktifkan Wi-Fi/Bluetooth."
        }
    }
}
extension NearbyPairing: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor [weak self] in self?.connected(peerID, state: state, from: session) }
    }
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard data.count < 8192 else { return }
        Task { @MainActor [weak self] in
            guard let self, session === self.session, self.active,
                  let message = try? JSONDecoder().decode(PairingEnvelope.self, from: data) else { return }
            self.onMessage?(message, peerID)
        }
    }
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
