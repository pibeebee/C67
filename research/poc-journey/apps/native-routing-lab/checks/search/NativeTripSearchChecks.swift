import Foundation

@main struct NativeTripSearchChecks {
    @MainActor static func main() async throws {
        var passed = 0
        func identifier(_ value: String) -> String { value }
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message)
        }
        func done(_ name: String) {
            passed += 1
            print("PASS: \(name)")
        }
        let timeout = NSError(domain: NSURLErrorDomain, code: URLError.timedOut.rawValue)
        let wrapped = NSError(
            domain: "MKErrorDomain", code: 2, userInfo: [NSUnderlyingErrorKey: timeout])
        check(
            NativeTripLookupFailure.classify(wrapped).kind == .timedOut,
            "Underlying timeout must remain a service timeout.")
        check(
            NativeTripLookupFailure.classify(wrapped).diagnostic.contains("-1001"),
            "Underlying code must be retained.")
        check(
            NativeTripLookupFailure.classify(NSError(domain: "MKErrorDomain", code: 3)).kind
                == .throttled, "Throttle classification.")
        check(
            NativeTripLookupFailure.classify(NSError(domain: "MKErrorDomain", code: 4)).kind
                == .noResults, "No result classification.")
        check(
            NativeTripLookupFailure.classify(
                NSError(domain: NSURLErrorDomain, code: URLError.cancelled.rawValue), deadlineExpired: true
            ).kind == .timedOut, "App deadline is not user cancellation.")
        done("timeouts, missing results, throttling and deadline cancellation are distinct")

        var calls: [String] = []
        var selected: [String] = []
        var states: [String: NativeTripLookupState] = [:]
        let isolated = try await NativeTripBulkLookup.run(["A", "B", "C"], id: identifier) { item in
            calls.append(item)
            if item == "B" { throw timeout }
            selected.append(item)
            return .init(kind: .resolved, detail: "Synthetic result")
        } update: {
            states[$0] = $1
        }
        check(calls == ["A", "B", "C"], "An isolated timeout must not abort the queue.")
        check(selected == ["A", "C"], "Successful selections before and after the error must survive.")
        check(
            states["B"]?.kind == .timedOut && isolated.failed == 1, "Timeout cannot become noResults.")
        done("one timeout preserves successful places and continues to the next place")

        calls = []
        states = [:]
        let consecutive = try await NativeTripBulkLookup.run(["A", "B", "C", "D"], id: identifier) {
            item in
            calls.append(item)
            throw timeout
        } update: {
            states[$0] = $1
        }
        check(
            calls == ["A", "B"], "Repeated service failure must pause, not issue every remaining request."
        )
        check(
            consecutive.deferred == 2 && states["C"]?.kind == .deferred && states["D"]?.kind == .deferred,
            "Untested places remain deferred.")
        done("two consecutive service failures pause remaining places without declaring them invalid")

        calls = []
        states = [:]
        let empty = try await NativeTripBulkLookup.run(["A", "B"], id: identifier) { item in
            calls.append(item)
            return .init(kind: item == "A" ? .noResults : .resolved, detail: "Synthetic result")
        } update: {
            states[$0] = $1
        }
        check(
            empty.failed == 0 && calls == ["A", "B"] && states["A"]?.kind == .noResults,
            "An empty successful search isn't a network failure.")
        done("a real empty response does not block unrelated places")

        calls = []
        states = [:]
        let throttled = try await NativeTripBulkLookup.run(["A", "B", "C"], id: identifier) { item in
            calls.append(item)
            throw NSError(domain: "MKErrorDomain", code: 3)
        } update: {
            states[$0] = $1
        }
        check(
            calls == ["A"] && throttled.deferred == 2 && states["A"]?.kind == .throttled,
            "Throttling must stop the batch immediately.")
        done("throttling does not trigger repeated retries")

        calls = []
        states = [:]
        let offline = try await NativeTripBulkLookup.run(["A", "B"], id: identifier) { item in
            calls.append(item)
            throw NSError(domain: NSURLErrorDomain, code: URLError.notConnectedToInternet.rawValue)
        } update: {
            states[$0] = $1
        }
        check(
            calls == ["A"] && offline.deferred == 1 && states["A"]?.kind == .offline,
            "Offline is not a missing place.")
        done("offline pauses without classifying places as nonexistent")

        calls = []
        states = [:]
        do {
            _ = try await NativeTripBulkLookup.run(["A", "B"], id: identifier) { item in
                calls.append(item)
                throw CancellationError()
            } update: {
                states[$0] = $1
            }
            preconditionFailure("Cancellation should propagate.")
        } catch is CancellationError {}
        check(
            calls == ["A"] && states["A"]?.kind == .searching && states["B"] == nil,
            "Cancellation must not apply an error or a late success to another place.")
        done("user cancellation propagates without a false timeout or stale result")
        print("\(passed) synthetic policy checks passed; no MapKit service or iOS runtime was called.")
    }
}
