import CryptoKit
import Foundation
@preconcurrency import OnnxRuntimeBindings
import Tokenizers

public actor E5Embedding: PreferenceEmbedding {
    public static let revision = "614241f622f53c4eeff9890bdc4f31cfecc418b3"
    private let folder: URL?
    private var tokenizer: (any Tokenizer)?
    private var environment: ORTEnv?
    private var session: ORTSession?
    private var info: EmbeddingMetadata?
    private var cache: [String: [Float]] = [:]
    public init(folder: URL? = nil) {
        self.folder = folder ?? Bundle.module.url(forResource: "Model", withExtension: nil)
    }
    private struct Manifest: Decodable {
        struct File: Decodable {
            var sha256: String
            var bytes: Int
        }
        var model: String
        var revision: String
        var files: [String: File]
    }
    private func load() async throws {
        if session != nil { return }
        try Task.checkCancellation()
        guard let folder else {
            throw PreferenceError.invalid(
                "Model lokal belum tersedia; pembanding kategori tetap dapat digunakan.")
        }
        let manifest = try JSONDecoder().decode(
            Manifest.self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
        guard manifest.model == "intfloat/multilingual-e5-small", manifest.revision == Self.revision,
              manifest.files["model.onnx"]?.sha256
              == "dd476dd0c2514e9b9be83aeb3853fac0763e0bdf4a71645407587d77c48a2d88"
        else { throw PreferenceError.invalid("Identitas model tidak sesuai versi eksperimen.") }
        for name in ["model.onnx", "tokenizer.json", "tokenizer_config.json", "config.json"] {
            guard let expected = manifest.files[name] else {
                throw PreferenceError.invalid("Manifest model tidak lengkap.")
            }
            let data = try Data(contentsOf: folder.appendingPathComponent(name), options: .mappedIfSafe)
            guard data.count == expected.bytes,
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expected.sha256
            else { throw PreferenceError.invalid("Pemeriksaan integritas model gagal.") }
        }
        let loadedTokenizer = try await AutoTokenizer.from(modelFolder: folder)
        try Task.checkCancellation()
        let env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(2)
        try options.setGraphOptimizationLevel(.all)
        let loadedSession = try ORTSession(
            env: env, modelPath: folder.appendingPathComponent("model.onnx").path, sessionOptions: options
        )
        guard
            Set(try loadedSession.inputNames())
            == Set(["input_ids", "attention_mask", "token_type_ids"]),
            (try loadedSession.outputNames()).contains("last_hidden_state")
        else { throw PreferenceError.invalid("Kontrak tensor model tidak sesuai.") }
        tokenizer = loadedTokenizer
        environment = env
        session = loadedSession
        info = .init(
            model: manifest.model, revision: manifest.revision,
            artifactSHA256: manifest.files["model.onnx"]!.sha256,
            runtime: "ONNX Runtime \(ORTVersion() ?? "unknown") / CPU / int8", dimensions: 384)
    }
    public func metadata() async throws -> EmbeddingMetadata {
        try await load()
        return info!
    }
    public func tokenIDs(_ text: String, query: Bool) async throws -> [Int] {
        try await load()
        let ids = tokenizer!.encode(
            text: (query ? "query: " : "passage: ") + text, addSpecialTokens: true)
        guard ids.count >= 2, ids.count <= 512 else {
            throw PreferenceError.invalid("Teks melebihi batas 512 token; tidak dipotong diam-diam.")
        }
        return ids
    }
    public func encode(_ text: String, query: Bool) async throws -> [Float] {
        try Task.checkCancellation()
        let key = (query ? "query: " : "passage: ") + text
        if let value = cache[key] { return value }
        let ids = try await tokenIDs(text, query: query)
        func tensor(_ values: [Int64]) throws -> ORTValue {
            let data = values.withUnsafeBufferPointer {
                NSMutableData(bytes: $0.baseAddress!, length: $0.count * MemoryLayout<Int64>.size)
            }
            return try ORTValue(
                tensorData: data, elementType: .int64, shape: [1, NSNumber(value: values.count)])
        }
        let outputs = try session!.run(
            withInputs: [
                "input_ids": try tensor(ids.map(Int64.init)),
                "attention_mask": try tensor(Array(repeating: 1, count: ids.count)),
                "token_type_ids": try tensor(Array(repeating: 0, count: ids.count)),
            ],
            outputNames: ["last_hidden_state"], runOptions: nil)
        try Task.checkCancellation()
        guard let output = outputs["last_hidden_state"],
              try output.tensorTypeAndShapeInfo().shape.map(\.intValue) == [1, ids.count, 384]
        else { throw PreferenceError.invalid("Bentuk embedding tidak sesuai.") }
        let data = try output.tensorData() as Data
        guard data.count == ids.count * 384 * MemoryLayout<Float>.size else {
            throw PreferenceError.invalid("Ukuran tensor tidak sesuai.")
        }
        var mean = Array(repeating: Float(0), count: 384)
        data.withUnsafeBytes { raw in
            let values = raw.bindMemory(to: Float.self)
            for token in 0 ..< ids.count {
                for dimension in 0 ..< 384 {
                    mean[dimension] += values[token * 384 + dimension] / Float(ids.count)
                }
            }
        }
        let norm = sqrt(mean.reduce(Float(0)) { $0 + $1 * $1 })
        guard norm.isFinite, norm > 0 else { throw PreferenceError.invalid("Embedding tidak valid.") }
        let result = mean.map { $0 / norm }
        if cache.count >= 128 { cache.removeAll() }
        cache[key] = result
        return result
    }
}
