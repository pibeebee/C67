import Foundation
import CryptoKit

@main struct LiveChannelChecks {
    @MainActor static var count = 0
    @MainActor static func check(_ result: Bool, _ label: String) {
        precondition(result, "FAILED: " + label); count += 1; print("PASS " + label)
    }
    @MainActor static func waitUntil(_ predicate: () -> Bool, seconds: Double = 12) async -> Bool {
        let deadline = Date.now.addingTimeInterval(seconds)
        while Date.now < deadline {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return predicate()
    }
    @MainActor static func main() async throws {
        let ticket = PairingTicket()
        check(PairingTicket(code: ticket.code)?.keyData == ticket.keyData, "pairing code round trips 256-bit key")
        check(PairingTicket(code: "invalid") == nil, "invalid pairing code rejected")
        check(PairingTicket(code: ticket.service + ".AA==") == nil, "short key rejected")
        let now = Date.now
        let sample = LiveSample(latitude: -6.1785, longitude: 106.8227, accuracy: 8, measuredAt: now, simulated: true)
        check(sample.usable(at: now), "fresh accurate sample accepted")
        check(!sample.usable(at: now.addingTimeInterval(31)), "stale sample rejected")
        check(!sample.usable(at: now.addingTimeInterval(-6)), "future sample outside clock tolerance rejected")
        check(!LiveSample(latitude: 91, longitude: 0, accuracy: 8, measuredAt: now, simulated: false).usable(at: now), "invalid coordinate rejected")
        check(!LiveSample(latitude: 0, longitude: 0, accuracy: 66, measuredAt: now, simulated: false).usable(at: now), "low precision sample rejected")
        check(!LiveSample(latitude: .nan, longitude: 0, accuracy: -1, measuredAt: now, simulated: false).usable(at: now), "nonfinite coordinate and invalid accuracy rejected")
        let epoch = UUID()
        let frame = try LocationWire.seal(.init(kind: "location", epoch: epoch, sequence: 1, sample: sample), key: ticket.key)
        var buffer = Data(frame.prefix(3))
        let incomplete = try LocationWire.popFrame(from: &buffer)
        check(incomplete == nil && buffer.count == 3, "partial TCP header retained")
        buffer.append(frame.dropFirst(3).prefix(10))
        let partial = try LocationWire.popFrame(from: &buffer)
        check(partial == nil, "partial TCP payload retained")
        buffer = frame + frame
        let payload = try LocationWire.popFrame(from: &buffer)!
        let opened = try LocationWire.open(payload, key: ticket.key)
        check(opened.epoch == epoch && opened.sample?.latitude == sample.latitude, "encrypted location round trip")
        _ = try LocationWire.popFrame(from: &buffer)
        check(buffer.isEmpty, "coalesced TCP frames parsed independently")
        do { _ = try LocationWire.open(payload, key: PairingTicket().key); check(false, "wrong secret must fail") }
        catch { check(true, "wrong secret rejected by authentication tag") }
        var corrupt = payload; corrupt[corrupt.startIndex + 15] ^= 1
        do { _ = try LocationWire.open(corrupt, key: ticket.key); check(false, "tampering must fail") }
        catch { check(true, "tampered ciphertext rejected") }
        var oversized = Data([0, 0, 32, 0])
        do { _ = try LocationWire.popFrame(from: &oversized); check(false, "oversized frame must fail") }
        catch { check(true, "oversized frame rejected before payload allocation") }

        let host = LocalLocationChannel(), navigator = LocalLocationChannel()
        var received: LiveSample?
        navigator.onSample = { received = $0 }
        host.startHost(ticket: ticket)
        let wrongNavigator = LocalLocationChannel()
        let wrongTicket = PairingTicket(code: ticket.service + "." + PairingTicket().keyData.base64EncodedString())!
        wrongNavigator.startNavigator(ticket: wrongTicket)
        check(await waitUntil { wrongNavigator.rejected > 0 }, "actual TCP pairing with wrong key is rejected")
        check(!wrongNavigator.connected && !host.connected, "wrong key cannot authenticate either peer")
        wrongNavigator.stop()
        navigator.startNavigator(ticket: ticket)
        let connected = await waitUntil { host.connected && navigator.connected }
        if !connected { print("CHANNEL DIAGNOSTIC host=" + host.status + " navigator=" + navigator.status) }
        check(connected, "real Bonjour TCP peers authenticate on local host")
        let transportSample = LiveSample(latitude: sample.latitude, longitude: sample.longitude, accuracy: 8, measuredAt: .now, simulated: true)
        host.publish(transportSample)
        check(await waitUntil { received != nil }, "encrypted GPS packet delivered over actual TCP")
        check(received?.latitude == sample.latitude && navigator.received == 1, "receiver obtains target coordinate once")
        host.stop()
        check(await waitUntil { !navigator.connected }, "disconnect invalidates authenticated peer state")
        host.startHost(ticket: ticket)
        check(await waitUntil { host.connected && navigator.connected }, "navigator reconnects after listener returns with a new connection epoch")
        host.stop(); navigator.stop()
        check(!host.connected && !navigator.connected, "stop closes both transport sessions")
        print(String(count) + " live data/channel checks passed; same Mac, not two physical iPhones.")
    }
}
