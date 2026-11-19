#if DEBUG
import Foundation

enum DevelopmentFixture {
    static func url(named name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "json") { return url }
        #if os(macOS)
            // SwiftPM tests run outside the iOS app bundle.
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<5 { root.deleteLastPathComponent() }
            let url = root.appendingPathComponent("contracts/fixtures/\(name).json")
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        #else
            return nil
        #endif
    }
}
#endif
