import SwiftUI

struct LeaderSetupView: View {
    let app: POCController
    @Environment(\.dismiss) private var dismiss
    @State private var place: TourPlace?
    @State private var radius = 100.0
    @State private var picker: ScannerPresentation?
    @State private var originalRun: UUID?
    private var editable: Bool { app.store.state.joinedQR == nil }
    var body: some View {
        NavigationStack {
            Form {
                ErrorNotice(app: app)
                Section("Meeting point (opsional)") {
                    if let place { Label(place.name, systemImage: "flag.fill").accessibilityIdentifier("meeting-point-name") }
                    else { Text("Belum ditentukan").foregroundStyle(.secondary).accessibilityIdentifier("meeting-point-empty") }
                    Button(place == nil ? "Pilih meeting point di peta" : "Ubah meeting point di peta", systemImage: "map") { picker = ScannerPresentation() }
                        .disabled(!editable).accessibilityIdentifier("pick-meeting-point")
                    Stepper("Radius indikator \(Int(radius)) meter", value: $radius, in: 10 ... 5000, step: 10).disabled(!editable)
                    Button("Simpan meeting point") { saveMeeting() }.disabled(place == nil || !editable).accessibilityIdentifier("save-meeting-point")
                    if app.store.state.meetingPoint != nil {
                        Button("Hapus meeting point", role: .destructive) {
                            app.attempt {
                                guard originalRun == app.store.state.runID else { throw POCError.message("Perjalanan berubah. Buka ulang pengaturan.") }
                                try app.store.commit { try $0.setMeetingPoint(nil, name: nil) }; dismiss()
                            }
                        }.disabled(!editable).accessibilityIdentifier("clear-meeting-point")
                    }
                    Text("Pilih tempat atau titik pada peta. Perubahan dikirim ke peserta saat online; periksa status rundown untuk hasil sinkronisasi. Radius adalah indikator, bukan bukti hadir.").font(.caption).foregroundStyle(.secondary)
                    if !editable { Text("Perangkat ini bergabung sebagai peserta. Meeting point dikelola oleh TL.").foregroundStyle(.secondary) }
                }
            }.navigationTitle("Meeting point").navigationBarTitleDisplayMode(.inline).toolbar { SheetCloseButton() }
                .onAppear {
                    if originalRun == nil {
                        originalRun = app.store.state.runID
                        if let point = app.store.state.meetingPoint { place = TourPlace(name: app.store.state.effectivePlan.meetingName ?? "Meeting point", latitude: point.latitude, longitude: point.longitude) }
                        radius = app.store.state.meetingRadius
                    }
                }
                .sheet(item: $picker) { _ in MapLocationPicker(initial: place, runID: app.store.state.runID, allowGPS: app.store.state.mode == .real) { place = $0 } }
        }
    }
    private func saveMeeting() {
        app.attempt {
            guard originalRun == app.store.state.runID, let place, place.valid else { throw POCError.message("Pilih titik valid untuk perjalanan ini.") }
            let point = MeetingPointSnapshot(latitude: place.latitude, longitude: place.longitude, radius: radius)
            try app.store.commit { try $0.setMeetingPoint(point, name: place.name) }
            dismiss()
        }
    }
}

struct DemoScenariosView: View {
    let app: POCController
    @Environment(\.dismiss) private var dismiss
    @State private var selected: DemoScenario?
    var body: some View {
        NavigationStack {
            List {
                ErrorNotice(app: app)
                Section {
                    ModeBadge(mode: .simulation)
                    Text("Ceritakan alur, satu skenario setiap kali.").font(.title2.bold())
                    Text("Data sintetis tanpa GPS atau CloudKit. Memuat skenario mengganti run dan riwayat pemeriksaan lokal setelah konfirmasi.").foregroundStyle(.secondary)
                }
                Section("Pilih titik awal demo") {
                    ForEach(DemoScenario.allCases) { scenario in
                        Button { selected = scenario } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: scenario.symbol).font(.title2).frame(width: 30).foregroundStyle(TourStyle.accent)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(scenario.title).font(.headline).foregroundStyle(.primary)
                                    Text(scenario.subtitle).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 10)
                        }.accessibilityIdentifier("demo-\(scenario.rawValue)").disabled(!app.canReplaceRun)
                    }
                }
                if !app.canReplaceRun {
                    Section { Label("Demo belum dapat dimuat. Hentikan GPS dan cleanup/putuskan share atau undangan aktif terlebih dahulu.", systemImage: "lock.shield").foregroundStyle(.orange) }
                }
                Section("Alur presentasi singkat") {
                    Text("1. Tunjukkan siapa yang diharapkan dan siapa yang sudah diperiksa.")
                    Text("2. Buka Ayu P01: lokasi adalah petunjuk; tindak lanjut dan pemeriksaan tetap eksplisit.")
                    Text("3. Review hasil, lalu mulai sesi berikutnya dengan pemeriksaan baru.")
                }
            }.navigationTitle("Skenario demo").navigationBarTitleDisplayMode(.inline).toolbar { SheetCloseButton() }
                .alert("Ganti run lokal dengan skenario demo?", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }), presenting: selected) { scenario in
                    Button("Muat skenario demo", role: .destructive) {
                        app.attempt { try app.loadDemo(scenario); dismiss() }
                        selected = nil
                    }
                    Button("Batal", role: .cancel) { selected = nil }
                } message: { scenario in Text("\(scenario.title). Seluruh pemeriksaan, rundown dan riwayat run lokal saat ini diganti dengan data SIMULASI.") }
        }
    }
}
