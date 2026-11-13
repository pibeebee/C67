import Foundation
import CoreLocation
import CryptoKit

struct LiveSample: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let measuredAt: Date
    let simulated: Bool
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    func usable(at now: Date) -> Bool {
        latitude.isFinite && longitude.isFinite && accuracy.isFinite
            && (-90 ... 90).contains(latitude) && (-180 ... 180).contains(longitude)
            && (0 ... 65).contains(accuracy)
            && (-5 ... 30).contains(now.timeIntervalSince(measuredAt))
    }
}

struct PairingTicket {
    let service: String
    let keyData: Data
    var code: String { service + "." + keyData.base64EncodedString() }
    var key: SymmetricKey { SymmetricKey(data: keyData) }
    init() {
        service = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(10))
        keyData = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }
    init?(code: String) {
        let parts = code.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 10, parts[0].allSatisfy({ "0123456789abcdef".contains($0) }),
              let data = Data(base64Encoded: String(parts[1])), data.count == 32 else { return nil }
        service = String(parts[0]); keyData = data
    }
}

struct LocationEnvelope: Codable {
    let kind: String
    let epoch: UUID
    let sequence: Int
    let sample: LiveSample?
    let challenge: UUID?
    init(kind: String, epoch: UUID, sequence: Int, sample: LiveSample?, challenge: UUID? = nil) {
        self.kind = kind; self.epoch = epoch; self.sequence = sequence
        self.sample = sample; self.challenge = challenge
    }
}

enum LocationWire {
    static let maximumFrame = 4096
    static func seal(_ message: LocationEnvelope, key: SymmetricKey) throws -> Data {
        let plaintext = try JSONEncoder().encode(message)
        guard let encrypted = try AES.GCM.seal(plaintext, using: key).combined else { throw CocoaError(.coderInvalidValue) }
        var size = UInt32(encrypted.count).bigEndian
        var frame = withUnsafeBytes(of: &size) { Data($0) }
        frame.append(encrypted)
        return frame
    }
    static func open(_ data: Data, key: SymmetricKey) throws -> LocationEnvelope {
        let plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
        return try JSONDecoder().decode(LocationEnvelope.self, from: plaintext)
    }
    // TCP is a byte stream: retain partial frames and reject oversized input before allocating payloads.
    static func popFrame(from buffer: inout Data) throws -> Data? {
        guard buffer.count >= 4 else { return nil }
        let size = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard size > 0, size <= maximumFrame else { throw CocoaError(.coderInvalidValue) }
        guard buffer.count >= size + 4 else { return nil }
        let payload = Data(buffer.dropFirst(4).prefix(size))
        buffer = Data(buffer.dropFirst(size + 4))
        return payload
    }
}
