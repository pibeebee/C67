import Foundation

extension ParticipantLocation {
    func displayable(runID: UUID, now: Date = .now) -> LocationSample? {
        guard let sample, sample.valid, sample.runID == runID, let expiresAt, expiresAt > now,
              sample.measuredAt <= now.addingTimeInterval(5) else { return nil }
        return sample
    }
    func applying(_ result: RemoteLocation, runID: UUID, now: Date = .now) -> Self {
        var next = self
        if next.epoch != result.epoch { next.sample = nil; next.receivedAt = nil }
        next.epoch = result.epoch; next.expiresAt = result.expiresAt
        guard result.state == "active", now < result.expiresAt else {
            next.sample = nil; next.receivedAt = nil
            next.status = result.state == "ready" ? "TL belum memulai berbagi lokasi" : "TL menghentikan/sesi berbagi berakhir"
            return next
        }
        next.status = "Lokasi TL tersedia; lihat umur pengukuran"
        if let sample = result.sample, let epoch = result.epoch,
           LocationRules.canReplace(sample, old: next.sample, runID: runID, epoch: epoch, now: now) {
            next.sample = sample; next.receivedAt = now
        }
        return next
    }
}

struct GroupMapPoint: Identifiable, Equatable {
    enum Kind: String { case participant, leader, you }
    var id: String
    var name: String
    var kind: Kind
    var sample: LocationSample
    var stale: Bool { Date.now.timeIntervalSince(sample.measuredAt) > LocationRules.staleAfter }
}
enum MapAudience { case leader, participant }

@MainActor extension POCController {
    func mapPoints(for audience: MapAudience, localSample: LocationSample? = nil, now: Date = .now) -> [GroupMapPoint] {
        var points: [GroupMapPoint] = []
        func usable(_ sample: LocationSample?) -> LocationSample? {
            guard let sample, sample.valid, sample.runID == store.state.runID,
                  sample.measuredAt <= now.addingTimeInterval(5) else { return nil }
            return sample
        }
        let own = usable(localSample)
        if audience == .leader {
            for p in store.state.sessions.last?.participants ?? [] {
                let sample = store.state.mode == .simulation ? self.sample(for: p.id) : locations[p.id]?.displayable(runID: store.state.runID, now: now)
                if let sample { points.append(GroupMapPoint(id: p.id, name: "\(p.name) · \(p.displayID)", kind: .participant, sample: sample)) }
            }
            let sharedOwn = leaderSharing.sensor.running ? usable(leaderSharing.sensor.latest) : nil
            if store.state.mode == .real, let sample = own ?? sharedOwn ?? (sensor.running ? usable(sensor.latest) : nil) {
                points.append(GroupMapPoint(id: "TL", name: "Anda · TL", kind: .you, sample: sample))
            } else if store.state.mode == .simulation, let sample = leaderLocation.sample {
                points.append(GroupMapPoint(id: "TL", name: "Anda · TL (simulasi)", kind: .leader, sample: sample))
            }
        } else {
            let tl = store.state.mode == .simulation ? leaderLocation.sample : leaderLocation.displayable(runID: store.state.runID, now: now)
            if let tl { points.append(GroupMapPoint(id: "TL", name: store.state.joinedQR?.leader ?? "Tour leader", kind: .leader, sample: tl)) }
            if store.state.mode == .real, let sample = own ?? (sensor.running ? usable(sensor.latest) : nil) {
                points.append(GroupMapPoint(id: "YOU", name: "Anda", kind: .you, sample: sample))
            } else if store.state.mode == .simulation, let sample = received {
                points.append(GroupMapPoint(id: "YOU", name: "Anda (simulasi)", kind: .you, sample: sample))
            }
        }
        return points
    }
}
