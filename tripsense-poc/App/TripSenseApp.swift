import SwiftUI
import UIKit
import TripSenseCore

@main struct TripSenseApp: App {
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--osm-network-probe") { OSMNetworkProbeView() }
            else { TripSenseView() }
        }
    }
}

private struct OSMNetworkProbeView: View {
    @State private var report = "Running the fixed public Jakarta request…"
    @State private var started = false
    var body: some View {
        ScrollView { Text(report).font(.caption.monospaced()).textSelection(.enabled).padding() }
            .task {
                guard !started else { return }
                started = true
                UIApplication.shared.isIdleTimerDisabled = true
                defer { UIApplication.shared.isIdleTimerDisabled = false }
                report = await OSMNetworkProbe.run()
                print(report)
                // Public fixed-query diagnostic only. Export with devicectl; no personal network metadata.
                if let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    do {
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        try Data(report.utf8).write(to: folder.appendingPathComponent("osm-network-probe.txt"),
                                                   options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    } catch {
                        report += "\nReport export failed: \(type(of: error))"
                        print(report)
                    }
                }
            }
    }
}

struct OSMProbeControls: View {
    @State private var report = ""
    @State private var requestID = 0
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Compare this fixed public Jakarta request on Wi-Fi or cellular. It does not use your current location.").font(.caption)
            Button("Run Overpass network probe") { busy = true; requestID += 1 }.disabled(busy)
            if busy { ProgressView("Checking Overpass…") }
            if !report.isEmpty {
                Text(report).font(.caption.monospaced()).textSelection(.enabled)
                ShareLink("Export probe report", item: report)
            }
        }
        .task(id: requestID) {
            guard requestID > 0 else { return }
            defer { busy = false }
            report = await OSMNetworkProbe.run()
        }
    }
}
