import SwiftUI
import MapKit
import Foundation

struct RoutingExperimentView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var configured = false
    let lab: RouteLab
    @State private var camera: MapCameraPosition = .region(TestArea.jakarta.region)
    @State private var showsDetails = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            Group {
                if !configured {
                    ProgressView("Membuka eksperimen routing…")
                } else if lab.stage.isLive {
                    VStack(spacing: 0) {
                        stagePicker.pickerStyle(.menu).padding(.horizontal)
                        LiveExperimentView(stage: lab.stage, routing: lab).id(lab.stage)
                    }
                } else {
                    ViewThatFits(in: .vertical) {
                        VStack(spacing: 0) {
                            controls
                            map
                            resultPanel
                        }
                        ScrollView {
                            VStack(spacing: 0) {
                                controls
                                map.frame(height: 280)
                                resultPanel
                            }
                        }
                    }
                }
            }
            .navigationTitle("Dynamic Destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Selesai") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if !lab.stage.isLive { Button("Detail eksperimen", systemImage: "slider.horizontal.3") { showsDetails = true } }
                }
            }
            .sheet(isPresented: $showsDetails) { details }
        }
        .task {
            if !configured {
                configured = true; lab.select(stage: .staticRoute)
                configureLaunchArguments()
            }
            while !Task.isCancelled {
                if !lab.stage.isLive { lab.tick(at: .now) }
                do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
            }
            lab.pause()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { lab.pause() }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                stagePicker.pickerStyle(.menu)
                VStack(alignment: .leading, spacing: 8) {
                    areaMenu
                    simulationLabel
                }
            } else {
                stagePicker.pickerStyle(.menu)
                HStack { areaMenu; Spacer(); simulationLabel }
            }
            Text(lab.stage.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.background)
    }

    private var stagePicker: some View {
        Picker("Tahap eksperimen", selection: Binding(get: { lab.stage }, set: { lab.select(stage: $0) })) {
            ForEach(ExperimentStage.allCases) { Text($0.title).tag($0) }
        }.accessibilityIdentifier("dds-stage-picker")
    }

    private var areaMenu: some View {
        Menu {
            ForEach(TestArea.allCases) { area in
                Button(area.title) { lab.select(area: area); camera = .region(area.region) }
            }
        } label: {
            Label(lab.area.title, systemImage: "map").font(.subheadline.weight(.medium))
        }
    }

    private var simulationLabel: some View {
        Text("POSISI SIMULASI").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func routeDistance(_ route: CalculatedRoute) -> some View {
        Text("\(route.distance, format: .number.precision(.fractionLength(0))) m")
    }

    private func routeETA(_ route: CalculatedRoute) -> some View {
        Text("ETA \(max(1, Int(ceil(route.expectedTravelTime / 60)))) mnt")
    }

    private func routeAge(_ snapshot: RouteSnapshot) -> some View {
        Text("\(Int(max(0, lab.now.timeIntervalSince(snapshot.requestedAt)))) dtk lalu").foregroundStyle(.secondary)
    }

    @ViewBuilder private var primaryAction: some View {
        if lab.stage == .staticRoute {
            Button("Hitung rute", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath") { lab.calculateManually() }
                .buttonStyle(.borderedProminent)
                .disabled(lab.isCalculating || lab.remainingCooldown > 0)
        } else {
            Button(lab.running ? "Jeda" : "Mulai", systemImage: lab.running ? "pause.fill" : "play.fill") {
                if lab.running { lab.pause() } else { lab.start() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(lab.finished && !lab.running)
        }
    }

    private var resetAction: some View {
        Button("Reset", systemImage: "arrow.counterclockwise") { lab.reset(); camera = .region(lab.area.region) }
            .buttonStyle(.bordered)
    }

    @ViewBuilder private var speedControl: some View {
        if lab.stage != .staticRoute {
            Menu("\(Int(lab.playbackRate))×") {
                ForEach([1.0, 5.0, 10.0], id: \.self) { speed in
                    Button("\(Int(speed))×") { lab.playbackRate = speed }
                }
            }
            .accessibilityLabel("Kecepatan simulasi, \(Int(lab.playbackRate)) kali")
        }
    }

    private var map: some View {
        Map(position: $camera) {
            if lab.showsPaths, lab.stage != .staticRoute {
                MapPolyline(coordinates: lab.area.targetPath.coordinates)
                    .stroke(.orange.opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                if lab.stage == .bothMoving {
                    MapPolyline(coordinates: lab.area.navigatorPath.coordinates)
                        .stroke(.blue.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                }
            }
            if let route = lab.route {
                MapPolyline(route.polyline)
                    .stroke(lab.errorMessage == nil ? .indigo : .gray, lineWidth: 6)
            }
            Annotation("A · Navigator simulasi", coordinate: lab.origin, anchor: .center) {
                mapBadge("A", color: .blue)
            }
            Annotation("B · Target simulasi", coordinate: lab.target, anchor: .center) {
                mapBadge("B", color: .orange)
            }
            if let snapshot = lab.routeSnapshot, lab.targetOffset > 10 {
                Annotation("B saat rute dihitung", coordinate: snapshot.target) {
                    Image(systemName: "flag.circle.fill")
                        .font(.title3).foregroundStyle(.secondary)
                        .padding(3).background(.background, in: Circle())
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControls { MapCompass(); MapScaleView() }
        .overlay(alignment: .topLeading) {
            Text(lab.stage == .staticRoute ? "A dan B tetap" : "\(Int(lab.simulationSeconds)) dtk simulasi · \(Int(lab.playbackRate))×")
                .font(.caption.monospacedDigit())
                .padding(8).background(.regularMaterial, in: Capsule())
                .padding(10)
                .accessibilityIdentifier("simulationClock")
        }
        .overlay(alignment: .bottomTrailing) {
            Button("Lihat seluruh area", systemImage: "arrow.up.left.and.arrow.down.right") {
                camera = .region(lab.area.region)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderedProminent)
            .padding(12)
        }
        .frame(minHeight: 150)
        .accessibilityIdentifier("experimentMap")
    }

    private func mapBadge(_ text: String, color: Color) -> some View {
        Text(text).font(.headline.bold()).foregroundStyle(.white)
            .frame(width: 34, height: 34).background(color, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(radius: 2)
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if lab.isCalculating { ProgressView().controlSize(.small) }
                Text(lab.status).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("routingStatus")
                Spacer(minLength: 0)
            }
            if let route = lab.route, let snapshot = lab.routeSnapshot {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        routeDistance(route)
                        routeETA(route)
                        routeAge(snapshot)
                    }
                    .font(.caption.monospacedDigit())
                } else {
                    HStack {
                        routeDistance(route)
                        Text("·")
                        routeETA(route)
                        Spacer()
                        routeAge(snapshot)
                    }
                    .font(.caption.monospacedDigit())
                }
                Text("Menuju B saat request dibuat · B kini bergeser \(Int(lab.targetOffset)) m. ETA bukan waktu pasti bertemu.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let error = lab.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("routingError")
            }
            HStack {
                Text("Request \(lab.requests) · Berhasil \(lab.successes) · Gagal \(lab.failures)")
                Spacer(minLength: 0)
                if lab.remainingCooldown > 0 { Text("Jeda \(Int(ceil(lab.remainingCooldown))) dtk") }
            }
            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            .accessibilityIdentifier("requestCounters")
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { primaryAction; resetAction; speedControl }
            } else {
                HStack { primaryAction; resetAction; Spacer(minLength: 0); speedControl }
            }

        }
        .padding()
        .background(.background)
    }

    private var details: some View {
        @Bindable var lab = lab
        return NavigationStack {
            Form {
                Section("Eksperimen") {
                    Text("Semua koordinat berasal dari simulasi. Tidak ada akses GPS, akun iCloud, atau perangkat lain.")
                    Text("Rute ungu: hasil Apple MapKit. Garis putus-putus: lintasan simulasi buatan, bukan petunjuk jalan.")
                    Text("Rute baru membutuhkan internet. Hasil untuk satu pasangan titik tidak membuktikan cakupan seluruh negara.")
                    Toggle("Tampilkan lintasan simulasi", isOn: $lab.showsPaths)
                }
                Section("Kebijakan rerouting") {
                    Stepper("Interval minimum: \(Int(lab.policy.minimumInterval)) dtk nyata", value: $lab.policy.minimumInterval, in: 10 ... 60, step: 5)
                    Stepper("Pergeseran B: \(Int(lab.policy.targetMovement)) m", value: $lab.policy.targetMovement, in: 10 ... 150, step: 10)
                    Stepper("Pergeseran A: \(Int(lab.policy.originMovement)) m", value: $lab.policy.originMovement, in: 20 ... 200, step: 10)
                    Stepper("A makin jauh dari rute: \(Int(lab.policy.offRouteDistance)) m", value: $lab.policy.offRouteDistance, in: 20 ... 150, step: 10)
                    Text("Parameter eksperimen, bukan batas resmi MapKit. Kecepatan pemutaran mempercepat posisi; interval request tetap memakai waktu nyata.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Hasil terakhir") {
                    LabeledContent("Alasan request", value: lab.lastReason)
                    if let latency = lab.lastLatency { LabeledContent("Waktu respons", value: String(format: "%.1f dtk", latency)) }
                    LabeledContent("Dibatalkan", value: "\(lab.cancellations)")
                    if let snapshot = lab.routeSnapshot {
                        LabeledContent("Waktu request", value: snapshot.requestedAt.formatted(date: .omitted, time: .standard))
                        LabeledContent("Waktu simulasi saat request", value: "\(Int(snapshot.simulationSeconds)) dtk")
                    }
                    if let route = lab.route {
                        ForEach(Array(route.instructions.enumerated()), id: \.offset) { index, instruction in
                            Text("\(index + 1). \(instruction)")
                        }
                    }
                    ShareLink("Bagikan laporan eksperimen", item: lab.report)
                }
                Section("Log · maksimal 100 kejadian") {
                    if lab.events.isEmpty { Text("Belum ada kejadian").foregroundStyle(.secondary) }
                    ForEach(lab.events) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.message).font(.caption)
                            Text(event.date, style: .time).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Detail eksperimen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Selesai") { showsDetails = false } } }
        }
    }

    private func configureLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--dds-area"), args.indices.contains(index + 1), let area = TestArea(rawValue: args[index + 1]) {
            lab.select(area: area); camera = .region(area.region)
        }
        if let index = args.firstIndex(of: "--dds-stage"), args.indices.contains(index + 1), let number = Int(args[index + 1]), let stage = ExperimentStage(rawValue: number) {
            lab.select(stage: stage)
        }
        if args.contains("--dds-autorun"), !lab.stage.isLive { lab.start() }
    }
}

#Preview { RoutingExperimentView(lab: RouteLab()) }
