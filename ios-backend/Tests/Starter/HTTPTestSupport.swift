import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import C67Data

struct StubResponse: Sendable {
    let status: Int
    let body: Data
    init(_ json: String) { status = 200; body = Data(json.utf8) }
    init(_ status: Int, _ json: String) { self.status = status; body = Data(json.utf8) }
    init(_ status: Int = 200, data: Data) { self.status = status; body = data }
}

actor RequestLog {
    private var values: [URLRequest] = []
    func append(_ request: URLRequest) { values.append(request) }
    func requests() -> [URLRequest] { values }
}

actor TestLatch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func signal() { isOpen = true; waiters.forEach { $0.resume() }; waiters = [] }
}

/// Lock-protected test fixtures; no real credentials or networking.
final class MemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var shouldFail = false
    init(_ data: Data? = nil) { self.data = data }
    func read() throws -> Data? { lock.withLock { data } }
    func write(_ value: Data?) throws {
        try lock.withLock {
            if shouldFail { throw TestFailure.storage }
            data = value
        }
    }
    func failWrites() { lock.withLock { shouldFail = true } }
    enum TestFailure: Error { case storage }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date { lock.withLock { value } }
    func advance(_ seconds: Double) { lock.withLock { value.addTimeInterval(seconds) } }
}

final class TestHTTPRegistry: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async throws -> StubResponse
    static let shared = TestHTTPRegistry()
    private let lock = NSLock()
    private var handlers: [String: Handler] = [:]
    func set(_ host: String, _ handler: @escaping Handler) { lock.withLock { handlers[host] = handler } }
    func handler(_ host: String) -> Handler? { lock.withLock { handlers[host] } }
    func remove(_ host: String) { _ = lock.withLock { handlers.removeValue(forKey: host) } }
}

final class StubHTTPProtocol: URLProtocol, @unchecked Sendable {
    private var responseTask: Task<Void, Never>?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        responseTask = Task {
            do {
                guard let handler = TestHTTPRegistry.shared.handler(request.url!.host!) else { throw URLError(.badURL) }
                let response = try await handler(request)
                try Task.checkCancellation()
                let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: response.body)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() { responseTask?.cancel() }
}

final class HTTPHarness: Sendable {
    let baseURL: URL
    let session: URLSession
    let log: RequestLog
    init(_ handler: @escaping TestHTTPRegistry.Handler) {
        let host = UUID().uuidString.lowercased() + ".example.test"
        baseURL = URL(string: "https://" + host)!
        let log = RequestLog()
        self.log = log
        TestHTTPRegistry.shared.set(host) { request in
            await log.append(request)
            return try await handler(request)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubHTTPProtocol.self]
        session = URLSession(configuration: config)
    }
    deinit { session.invalidateAndCancel(); TestHTTPRegistry.shared.remove(baseURL.host!) }
}

func requestBody(_ request: URLRequest) throws -> [String: Any] {
    let data: Data
    if let body = request.httpBody { data = body }
    else if let stream = request.httpBodyStream {
        stream.open(); defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 1024), bytes = Data()
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            bytes.append(buffer, count: count)
        }
        data = bytes
    } else { data = Data("{}".utf8) }
    return try JSONSerialization.jsonObject(with: data) as! [String: Any]
}

func contractFixture(_ name: String) throws -> Data {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("contracts/fixtures/" + name + ".json"))
}
