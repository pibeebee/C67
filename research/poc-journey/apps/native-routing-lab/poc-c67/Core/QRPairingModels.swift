import Foundation
import CryptoKit

struct JourneyInvite: Codable, Equatable, Identifiable {
    var version = 3
    var id = UUID()
    var runID: UUID
    var journey: String
    var leader: String
    var leaderRecord: String
    var token: String
    var publicKey: Data
    var expiresAt: Date
    static let prefix = "c67://join/"
    var encoded: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return Self.prefix + (try! encoder.encode(self)).base64EncodedString()
    }
    static func decode(_ text: String, now: Date = .now) throws -> Self {
        guard text.utf8.count < 4096, text.hasPrefix(prefix),
              let data = Data(base64Encoded: String(text.dropFirst(prefix.count))),
              let value = try? JSONDecoder().decode(Self.self, from: data) else {
            throw POCError.message("QR ini bukan undangan perjalanan C67 yang valid.")
        }
        try value.validate(now: now); return value
    }
    func validate(now: Date = .now) throws {
        guard version == 3, expiresAt > now, expiresAt.timeIntervalSince(now) <= 610,
              token.count == 64, token.allSatisfy({ $0.isHexDigit }), publicKey.count == 32,
              !leaderRecord.isEmpty, leaderRecord.utf8.count < 256,
              !journey.isEmpty, journey.count <= 60, !leader.isEmpty, leader.count <= 40 else {
            throw POCError.message("QR tidak didukung atau sudah kedaluwarsa. Minta TL menampilkan QR baru.")
        }
    }
    var discoveryID: String { String(SHA256.hash(data: Data(token.utf8)).compactMap { String(format: "%02x", $0) }.joined().prefix(24)) }
}

struct PairedMember: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var accountRecord: String
    var reference: CloudReference
}
struct JoinedJourney: Codable, Equatable {
    var journey: String
    var leader: String
    var leaderRecord: String
    var participantID: String
    var participantName: String
}

// Only bootstrap data crosses the nearby session. Location samples continue through private CloudKit shares.
struct PairingHello: Codable, Equatable {
    var challenge: UUID
    var accountRecord: String
    var name: String
}
struct PairingWelcome: Codable, Equatable {
    var inviteID: UUID
    var runID: UUID
    var challenge: UUID
    var participantID: String
    var accountRecord: String
    var signature: Data
    var leaderURL: String?
    var meetingPoint: MeetingPointSnapshot?
    func signedData() -> Data {
        Data([inviteID.uuidString, runID.uuidString, challenge.uuidString, participantID, accountRecord, leaderURL ?? "", meetingPoint?.signatureText ?? ""].joined(separator: "|").utf8)
    }
    func validate(invite: JourneyInvite, hello: PairingHello, now: Date = .now) throws {
        try invite.validate(now: now)
        guard meetingPoint == nil || meetingPoint?.valid == true,
              inviteID == invite.id, runID == invite.runID, challenge == hello.challenge,
              accountRecord == hello.accountRecord, UUID(uuidString: participantID) != nil,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: invite.publicKey),
              key.isValidSignature(signature, for: signedData()) else {
            throw POCError.message("Identitas koneksi TL tidak cocok dengan QR. Scan ulang dari iPhone TL.")
        }
    }
}
struct PairingReceipt: Codable, Equatable {
    var challenge: UUID
    var participantID: String
    var signature: Data
    func signedData() -> Data { Data(("accepted|" + challenge.uuidString + "|" + participantID).utf8) }
    func validate(invite: JourneyInvite, welcome: PairingWelcome) throws {
        guard challenge == welcome.challenge, participantID == welcome.participantID,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: invite.publicKey),
              key.isValidSignature(signature, for: signedData()) else { throw POCError.message("Konfirmasi TL tidak valid.") }
    }
}
struct PairingEnvelope: Codable {
    enum Kind: String, Codable { case hello, welcome, share, accepted, failure }
    var kind: Kind
    var hello: PairingHello?
    var welcome: PairingWelcome?
    var receipt: PairingReceipt?
    var url: String?
    var message: String?
}

extension RunState {
    var cloudBindings: [CloudReference] {
        var result = qrMembers?.map(\.reference) ?? []
        if let binding, !result.contains(binding) { result.append(binding) }
        return result
    }
    mutating func register(_ member: PairedMember) throws {
        guard mode == .real, qrMembers != nil, !ended, let index = activeIndex,
              member.reference.runID == runID, member.id == member.reference.participantID else {
            throw POCError.message("Perjalanan QR atau sesi pemeriksaan tidak lagi aktif.")
        }
        var members = qrMembers ?? []
        guard !members.contains(where: { $0.id == member.id && $0.accountRecord != member.accountRecord }) else { throw POCError.message("Identitas peserta tidak cocok.") }
        if let old = members.firstIndex(where: { $0.accountRecord == member.accountRecord }) {
            guard members[old].id == member.id else { throw POCError.message("Peserta sudah mempunyai ID lain.") }
            members[old] = member
        } else {
            guard members.count < 20 else { throw POCError.message("POC dibatasi 20 peserta per perjalanan QR.") }
            members.append(member)
        }
        qrMembers = members
        if !sessions[index].participants.contains(where: { $0.id == member.id }) {
            sessions[index].participants.append(Participant(id: member.id, name: member.name))
            sessions[index].events.append(AuditEvent(id: UUID(), at: .now, text: "\(member.name) bergabung lewat QR; belum diperiksa TL."))
        }
        if binding == nil || binding?.participantID == member.id { binding = member.reference }
    }
}

struct ParticipantLocation {
    var sample: LocationSample?
    var receivedAt: Date?
    var expiresAt: Date?
    var epoch: UUID?
    var status = "Belum ada lokasi"
}

struct LeaderShare: Codable, Equatable, Identifiable {
    var id: String { accountRecord }
    var accountRecord: String
    var reference: CloudReference
}

struct MeetingPointSnapshot: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var radius: Double
    var valid: Bool { latitude.isFinite && longitude.isFinite && radius.isFinite && (-90 ... 90).contains(latitude) && (-180 ... 180).contains(longitude) && (10 ... 5000).contains(radius) }
    var signatureText: String { "\(latitude)|\(longitude)|\(radius)" }
}
