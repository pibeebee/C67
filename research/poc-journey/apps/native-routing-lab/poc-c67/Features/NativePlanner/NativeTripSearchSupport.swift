import Foundation

enum NativeTripLookupKind: String, Equatable, Sendable {
    case searching, resolved, needsSelection, noResults, timedOut, offline, throttled, failed,
         deferred

    var title: String {
        switch self {
        case .searching: "Sedang dicari"
        case .resolved: "Lokasi dipilih"
        case .needsSelection: "Pilih kandidat lokasi"
        case .noResults: "Pencarian belum menemukan hasil"
        case .timedOut: "Pencarian timeout · lokasi belum diverifikasi"
        case .offline: "Pencarian gagal terhubung"
        case .throttled: "Pencarian sedang dibatasi layanan"
        case .failed: "Pencarian belum berhasil"
        case .deferred: "Pencarian ditunda"
        }
    }
}

struct NativeTripLookupState: Equatable, Sendable {
    var kind: NativeTripLookupKind
    var detail: String
}

struct NativeTripLookupFailure: LocalizedError, Sendable {
    var kind: NativeTripLookupKind
    var domain: String
    var code: Int
    var detail: String
    var underlyingCodes: [String] = []
    var errorDescription: String? { detail }
    var diagnostic: String { (["\(domain) [\(code)]"] + underlyingCodes).joined(separator: " → ") }

    static func chain(_ error: Error) -> [NSError] {
        var result = [error as NSError]
        for _ in 0 ..< 4 {
            guard let next = result.last?.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
            if result.contains(where: { $0 === next }) { break }
            result.append(next)
        }
        return result
    }

    static func classify(_ error: Error, deadlineExpired: Bool = false) -> Self {
        if let failure = error as? Self { return failure }
        let errors = chain(error)
        let root = errors.first!
        // MapKit codes are public MKError.Code values: loadingThrottled=3, placemarkNotFound=4.
        // Their bridge is handled here without depending on MapKit, so the policy can be checked on macOS.
        let kind: NativeTripLookupKind
        if deadlineExpired
            || errors.contains(where: {
                $0.domain == NSURLErrorDomain && $0.code == URLError.timedOut.rawValue
            })
        {
            kind = .timedOut
        } else if errors.contains(where: { $0.domain == "MKErrorDomain" && $0.code == 3 }) {
            kind = .throttled
        } else if errors.contains(where: {
            $0.domain == NSURLErrorDomain
                && [
                    URLError.notConnectedToInternet.rawValue, URLError.networkConnectionLost.rawValue,
                    URLError.cannotConnectToHost.rawValue, URLError.cannotFindHost.rawValue,
                    URLError.dnsLookupFailed.rawValue,
                ].contains($0.code)
        }) {
            kind = .offline
        } else if errors.contains(where: { $0.domain == "MKErrorDomain" && $0.code == 4 }) {
            kind = .noResults
        } else {
            kind = .failed
        }
        let detail: String
        switch kind {
        case .timedOut:
            detail =
                "Layanan pencarian belum menjawab dalam batas waktu. Lokasi belum diverifikasi; ini bukan bukti tempat tidak ada."
        case .throttled:
            detail = "Apple sedang membatasi pencarian. Antrean dijeda; coba lagi setelah beberapa saat."
        case .offline:
            detail =
                "Pencarian belum berhasil terhubung ke layanan. Periksa koneksi; hasil lokasi yang sudah dipilih dipertahankan."
        case .noResults:
            detail = "Pencarian belum menemukan lokasi. Coba nama alternatif atau pilih titik pada peta."
        default: detail = "Layanan pencarian belum berhasil: \(root.localizedDescription)"
        }
        return .init(
            kind: kind, domain: root.domain, code: root.code, detail: detail,
            underlyingCodes: errors.dropFirst().map { "\($0.domain) [\($0.code)]" })
    }
}

@MainActor enum NativeTripSearchPacing {
    private static var nextRequest = Date.distantPast
    private static var cooldownUntil = Date.distantPast

    static func wait() async throws {
        guard Date() >= cooldownUntil else {
            throw NativeTripLookupFailure(
                kind: .throttled, domain: "POC.SearchCooldown", code: 1,
                detail:
                "Pencarian sedang dijeda setelah pembatasan layanan. Coba lagi dalam \(Int(ceil(cooldownUntil.timeIntervalSinceNow))) detik."
            )
        }
        let reserved = max(Date(), nextRequest)
        nextRequest = reserved.addingTimeInterval(1.2)
        let delay = max(0, reserved.timeIntervalSinceNow)
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
    }

    static func record(_ failure: NativeTripLookupFailure) {
        if failure.kind == .throttled, failure.domain != "POC.SearchCooldown" {
            cooldownUntil = Date().addingTimeInterval(60)
        }
    }
}

struct NativeTripSearchAttempt: Sendable {
    var query: String
    var region: String
    var elapsed: TimeInterval
    var result: String
    var diagnostic: String?
}

struct NativeTripBulkSummary: Sendable {
    var attempted = 0
    var failed = 0
    var deferred = 0
}

@MainActor enum NativeTripBulkLookup {
    static func run<Item>(
        _ items: [Item], id: (Item) -> String,
        lookup: (Item) async throws -> NativeTripLookupState,
        update: (String, NativeTripLookupState) -> Void
    ) async throws -> NativeTripBulkSummary {
        var summary = NativeTripBulkSummary()
        var consecutiveServiceFailures = 0
        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            update(id(item), .init(kind: .searching, detail: "Mencari lokasi…"))
            summary.attempted += 1
            do {
                let state = try await lookup(item)
                try Task.checkCancellation()
                update(id(item), state)
                consecutiveServiceFailures = 0
            } catch is CancellationError { throw CancellationError() } catch {
                try Task.checkCancellation()
                let failure = NativeTripLookupFailure.classify(error)
                update(
                    id(item), .init(kind: failure.kind, detail: "\(failure.detail)\n\(failure.diagnostic)"))
                summary.failed += 1
                if [.timedOut, .failed].contains(failure.kind) {
                    consecutiveServiceFailures += 1
                } else {
                    consecutiveServiceFailures = 0
                }
                if [.throttled, .offline].contains(failure.kind) || consecutiveServiceFailures >= 2 {
                    for remaining in items.dropFirst(index + 1) {
                        update(
                            id(remaining),
                            .init(
                                kind: .deferred,
                                detail:
                                "Belum diminta karena layanan pencarian sedang bermasalah. Coba lagi setelah koneksi/layanan pulih."
                            ))
                        summary.deferred += 1
                    }
                    break
                }
            }
        }
        return summary
    }
}
