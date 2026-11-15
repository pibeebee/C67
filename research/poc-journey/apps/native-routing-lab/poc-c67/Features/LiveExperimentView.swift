import SwiftUI
import MapKit
import UIKit

struct LiveExperimentView: View {
    @State private var experiment: LiveExperiment
    @State private var camera: MapCameraPosition = .automatic
    @State private var details = false
    @State private var centered = false
    @Environment(\.scenePhase) private var scenePhase
    init(stage: ExperimentStage, routing: RouteLab) { _experiment = State(initialValue: LiveExperiment(stage: stage, routing: routing)) }

    var body: some View {
        @Bindable var experiment = experiment
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(experiment.stage.explanation).font(.caption).foregroundStyle(.secondary)
                    if experiment.stage != .realGPS {
                        Picker("Peran perangkat", selection: $experiment.role) {
                            ForEach(DeviceRole.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).disabled(experiment.active)
                        if experiment.role == .navigator {
                            TextField("Tempel kode dari iPhone B", text: $experiment.enteredCode, axis: .vertical)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .font(.caption.monospaced()).textFieldStyle(.roundedBorder)
                                .disabled(experiment.active).privacySensitive()
                        } else if !experiment.pairingCode.isEmpty {
                            Text(experiment.pairingCode).font(.caption.monospaced()).textSelection(.enabled).privacySensitive()
                            HStack {
                                Button("Salin kode", systemImage: "doc.on.doc") {
                                    UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: experiment.pairingCode]],
                                                                  options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(1800)])
                                }
                                ShareLink("Bagikan kode", item: experiment.pairingCode)
                            }.font(.caption)
                        }
                    }
                    Text(experiment.note).font(.caption)
                    if experiment.stage != .realGPS {
                        Text("B membagikan GPS kepada pemegang kode. Gunakan Wi-Fi lokal yang sama untuk uji awal; peer-to-peer bergantung pada perangkat dan kondisi jaringan. Kode baru dibuat setiap sesi B.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(experiment.active ? "Hentikan sesi" : "Mulai sesi",
                               systemImage: experiment.active ? "stop.fill" : "location.fill") {
                            if experiment.active { experiment.stop() }
                            else { centered = false; experiment.start() }
                        }.buttonStyle(.borderedProminent)
                        Button("Diagnostik", systemImage: "list.bullet.rectangle") { details = true }
                            .buttonStyle(.bordered)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(experiment.gps.status)
                        if experiment.stage != .realGPS { Text(experiment.channel.status) }
                        if !experiment.targetRole {
                            Text(experiment.inputsReady ? experiment.routing.status : "Rute ditahan: menunggu posisi segar/akurat dan koneksi")
                                .foregroundStyle(experiment.inputsReady ? Color.primary : .orange)
                        }
                    }.font(.caption).accessibilityIdentifier("liveStatus")
                }.padding()
            }.frame(maxHeight: experiment.stage == .realGPS ? 190 : 280)
            Map(position: $camera) {
                if let route = experiment.routing.route {
                    MapPolyline(route.polyline).stroke(experiment.inputsReady && experiment.routing.errorMessage == nil ? .indigo : .gray, lineWidth: 6)
                }
                if let origin = experiment.origin {
                    Annotation("A · GPS Navigator", coordinate: origin) { badge("A", color: experiment.localUsable ? .blue : .gray) }
                }
                if let target = experiment.target {
                    Annotation(experiment.stage == .realGPS ? "B · SIMULASI" : "B · GPS Target", coordinate: target) {
                        badge("B", color: experiment.stage == .realGPS || experiment.targetRole && experiment.localUsable || experiment.remoteUsable ? .orange : .gray)
                    }
                }
            }
            .mapControls { MapCompass(); MapScaleView() }
            .overlay(alignment: .topLeading) {
                Text(experiment.stage == .realGPS ? "A: Core Location · B: SINTETIS" : "A/B: Core Location · koneksi lokal")
                    .font(.caption2).padding(8).background(.regularMaterial, in: Capsule()).padding(8)
            }
            .overlay(alignment: .bottomTrailing) {
                Button("Lihat posisi terkini", systemImage: "scope") { camera = .automatic }
                    .labelStyle(.iconOnly).buttonStyle(.borderedProminent).padding()
            }.frame(minHeight: 150)
            VStack(alignment: .leading, spacing: 4) {
                if let route = experiment.routing.route, let snapshot = experiment.routing.routeSnapshot {
                    Text("\(Int(route.distance)) m · ETA snapshot \(max(1, Int(ceil(route.expectedTravelTime / 60)))) mnt · \(Int(max(0, experiment.now.timeIntervalSince(snapshot.requestedAt)))) dtk lalu")
                    Text("Menuju posisi B saat request; ETA bukan prediksi waktu bertemu.").foregroundStyle(.secondary)
                }
                if let error = experiment.routing.errorMessage { Text(error).foregroundStyle(.red) }
                if experiment.stage != .realGPS, experiment.role == .navigator {
                    Text("B: \(sampleDescription(experiment.remote)) · diterima \(experiment.channel.received) kali")
                }
                Text("GPS lokal: \(sampleDescription(experiment.gps.latest))")
                Text("Request \(experiment.routing.requests) · berhasil \(experiment.routing.successes) · gagal \(experiment.routing.failures)")
            }.font(.caption2).frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .sheet(isPresented: $details) { diagnostics }
        .task {
            configureArguments()
            while !Task.isCancelled {
                experiment.refresh(at: .now)
                if !centered, let coordinate = experiment.gps.latest?.coordinate {
                    camera = .region(.init(center: coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)); centered = true
                }
                do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { experiment.setForeground(false) }
            else if phase == .active { experiment.setForeground(true) }
        }
        .onDisappear { experiment.stop(reason: "Keluar dari tahap eksperimen") }
    }
    private func badge(_ title: String, color: Color) -> some View {
        Text(title).font(.headline.bold()).foregroundStyle(.white).frame(width: 34, height: 34)
            .background(color, in: Circle()).overlay(Circle().stroke(.white, lineWidth: 3))
    }
    private func sampleDescription(_ sample: LiveSample?) -> String {
        guard let sample else { return "belum ada sampel" }
        return "±\(Int(sample.accuracy)) m, umur \(Int(max(0, experiment.now.timeIntervalSince(sample.measuredAt)))) dtk\(sample.simulated ? ", sintetis/GPX" : "")"
    }
    private var diagnostics: some View {
        NavigationStack {
            Form {
                Section("Izin dan kualitas") {
                    Text("Izin: \(experiment.gps.authorization)")
                    Text("Precise Location: \(experiment.gps.reducedAccuracy ? "nonaktif" : "aktif")")
                    Text("Batas awal: akurasi ≤65 m, umur ≤30 dtk; waktu masa depan ditoleransi 5 dtk. Samakan waktu otomatis kedua iPhone.")
                    Link("Buka Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                }
                Section("Pengukuran") {
                    LabeledContent("GPS diterima / ditolak", value: "\(experiment.gps.accepted) / \(experiment.gps.rejected)")
                    LabeledContent("GPS saat background", value: "\(experiment.gps.backgroundFixes)")
                    LabeledContent("Dikirim / diterima", value: "\(experiment.channel.sent) / \(experiment.channel.received)")
                    LabeledContent("Paket ditolak", value: "\(experiment.channel.rejected)")
                    LabeledContent("Diterima saat background", value: "\(experiment.backgroundReceived)")
                    Text("Dikirim menghitung paket yang diserahkan ke TCP, bukan tanda terima dari Navigator.")
                    LabeledContent("Routing dibatalkan", value: "\(experiment.routing.cancellations)")
                    if let expiry = experiment.expiresAt { Text("Sesi berakhir \(expiry.formatted(date: .omitted, time: .standard))") }
                }
                Section("Batas eksperimen") {
                    Text("Tahap 3: B sintetis berjarak sekitar 250 m dari GPS awal. Lintasannya tidak menjamin mengikuti jalan.")
                    Text("Tahap 4: sesi berhenti saat app background. Tahap 5: sesi GPS dimulai di foreground dengan indikator lokasi iOS, maksimal 30 menit.")
                    Text("Background bukan jaminan proses hidup terus. Jaringan dapat terputus; Navigator mencari koneksi kembali selama proses aktif. Force quit/relaunch memerlukan sesi baru. Rute MapKit baru membutuhkan internet dan hanya dihitung saat Navigator foreground.")
                    Text("Hentikan mengakhiri GPS dan koneksi. Tidak ada penyimpanan riwayat lokasi atau kode pairing di disk. Laporan tetap memuat waktu dan diagnostik.")
                    ShareLink("Bagikan laporan", item: experiment.report)
                }
                Section("Log sesi") { ForEach(Array(experiment.log.enumerated()), id: \.offset) { _, event in Text(event).font(.caption) } }
            }.navigationTitle("Diagnostik GPS & koneksi")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Selesai") { details = false } } }
        }
    }
    private func configureArguments() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--dds-live-role"), args.indices.contains(i + 1), let role = DeviceRole(rawValue: args[i + 1]) { experiment.role = role }
        if let i = args.firstIndex(of: "--dds-pair-code"), args.indices.contains(i + 1) { experiment.enteredCode = args[i + 1] }
        if args.contains("--dds-autorun") { experiment.start() }
        if args.contains("--dds-live-diagnostics") { details = true }
    }
}
