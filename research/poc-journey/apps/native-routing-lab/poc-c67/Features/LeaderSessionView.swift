import SwiftUI

struct LeaderSessionView: View {
    let app: POCController
    @State private var sheet: LeaderSheet?
    @State private var map: ScannerPresentation?
    @State private var search = ""
    @State private var filter: ParticipantFilter = .all
    @Environment(\.dynamicTypeSize) private var typeSize
    private var session: AttendanceSession { app.store.state.sessions.last! }
    private var filtered: [Participant] { filter.results(in: session.participants, search: search) }
    var body: some View {
        NavigationStack {
            List {
                ErrorNotice(app: app)
                Section {
                    Button { sheet = .qr } label: {
                        HStack { Label("Undang peserta lewat QR", systemImage: "qrcode").font(.headline); Spacer(); Image(systemName: "arrow.up.right") }
                    }.accessibilityIdentifier("open-leader-qr")
                }
                Section {
                    NavigationLink { ItineraryView(app: app, audience: .leader) } label: { Label("Rundown perjalanan", systemImage: "calendar") }.accessibilityIdentifier("open-itinerary")
                }
                summarySection
                rosterSection
                locationSection
                simulationSection
                Section { Button { sheet = .history } label: { Label("Riwayat pemeriksaan", systemImage: "clock.arrow.circlepath") } }
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).background(TourStyle.canvas)
            .contentMargins(.top, 0, for: .scrollContent)
            .listSectionSpacing(16)
            .navigationTitle("Rombongan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { sheet = .demo } label: { Label("Demo", systemImage: "play.rectangle") }.accessibilityIdentifier("open-demo")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sheet = .setup } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Atur meeting point").accessibilityIdentifier("open-setup")
                }
            }
            .safeAreaInset(edge: .bottom) { reviewBar }
            .refreshable { await app.fetch() }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .manual: ManualPairingView(app: app, initialRole: .leader)
                case .qr: LeaderQRView(app: app)
                case .setup: LeaderSetupView(app: app)
                case .demo: DemoScenariosView(app: app)
                case .review: ReviewSessionView(app: app)
                case .leaderSharing: LeaderSharingView(app: app)
                case .history: RunHistoryView(app: app)
                }
            }
            .fullScreenCover(item: $map) { _ in GroupMapScreen(app: app, audience: .leader) }
            .onChange(of: app.store.state.runID) { _, _ in search = ""; filter = .all }
            .onChange(of: session.id) { _, _ in search = ""; filter = .all }
            .onChange(of: app.incoming) { _, incoming in if incoming != nil { sheet = .manual } }
            .onAppear { if app.incoming != nil { sheet = .manual } }
        }
    }
    @ViewBuilder private var summarySection: some View {
        Section {
            HStack {
                ModeBadge(mode: app.store.state.mode)
                Spacer()
                Text("\(session.participants.count) peserta" + (app.store.state.qrMembers == nil ? " uji" : "")).font(.caption).foregroundStyle(.secondary)
            }
            SessionSummaryCard(session: session, mode: app.store.state.mode)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 1 : 3), spacing: 16) {
                CountTile(value: session.counts.unresolved, title: "Belum diperiksa", symbol: "circle.dashed", color: .orange)
                CountTile(value: session.counts.openCases, title: "Tindak lanjut", symbol: "flag", color: .orange)
                CountTile(value: session.counts.excluded, title: "Tidak ikut sesi", symbol: "minus.circle", color: .secondary)
            }.padding(.vertical, 8)
        }.listRowSeparator(.hidden).listRowBackground(Color.clear)
    }
    @ViewBuilder private var rosterSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Cari nama atau nomor peserta", text: $search).autocorrectionDisabled().accessibilityIdentifier("participant-search")
            }
            Menu {
                Picker("Tampilkan peserta", selection: $filter) { ForEach(ParticipantFilter.allCases) { Text($0.rawValue).tag($0) } }
            } label: {
                HStack { Label(filter.rawValue, systemImage: "line.3.horizontal.decrease"); Spacer(); Text("\(filtered.count) peserta").foregroundStyle(.secondary); Image(systemName: "chevron.down").font(.caption) }
            }.accessibilityIdentifier("participant-filter")
            ForEach(filtered) { p in
                NavigationLink {
                    ParticipantDetailView(app: app, sessionID: session.id, participantID: p.id)
                } label: {
                    ParticipantRow(person: p, hasLocation: app.sample(for: p.id) != nil)
                }.accessibilityIdentifier("participant-\(p.id)")
            }
            if filtered.isEmpty {
                ContentUnavailableView("Tidak ada peserta", systemImage: "person.crop.circle.badge.questionmark", description: Text("Ubah pencarian atau filter untuk melihat peserta lain."))
            }
        } header: {
            HStack { Text("Daftar peserta"); Spacer(); Text("\(session.participants.count) total") }
        } footer: { Text("Filter hanya mengubah daftar. Angka ringkasan selalu mencakup seluruh sesi.") }
    }
    @ViewBuilder private var locationSection: some View {
        Section("Meeting point & lokasi") {
            Button { map = ScannerPresentation() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "map.fill").font(.title2).foregroundStyle(TourStyle.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Peta rombongan").font(.headline).foregroundStyle(.primary)
                        Text("Semua posisi tersedia · geser & zoom").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 5)
            }.accessibilityIdentifier("open-location")
            Button { sheet = .leaderSharing } label: { Label("Bagikan lokasi saya ke peserta", systemImage: "location.circle") }.accessibilityIdentifier("open-leader-sharing")
            // Compact freshness is visible without opening a map; raw coordinates remain in the detail screen.
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Label(LocationRules.freshness(app.received, now: timeline.date), systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("location-freshness")
            }
        }
    }
    @ViewBuilder private var simulationSection: some View {
        if app.store.state.mode == .simulation {
            Section {
                Button("Sampel dekat (simulasi)") { app.simulate("dekat") }.accessibilityIdentifier("simulate-near")
                Button("Sampel jauh (simulasi)") { app.simulate("jauh") }
                Button("Sampel kedaluwarsa (simulasi)") { app.simulate("stale") }.accessibilityIdentifier("simulate-stale")
                Button("Sampel reduced accuracy (simulasi)") { app.simulate("reduced") }
            } header: { Text("Kontrol lokasi · simulasi") } footer: { Text("Data sintetis untuk presentasi. Tidak menguji GPS atau koneksi antar-iPhone.") }
        }
    }
    private var reviewBar: some View {
        VStack(spacing: 8) {
            if session.closedAt == nil {
                Button { sheet = .review } label: {
                    HStack { Text("Review pemeriksaan"); Spacer(); Image(systemName: "arrow.right") }.font(.headline).padding(.vertical, 6).frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 16)).controlSize(.large).accessibilityIdentifier("review-session")
            } else {
                Text(session.closureNote == nil ? "Pemeriksaan ditutup setelah review" : "Ditutup dengan catatan").font(.caption).foregroundStyle(.secondary)
                Button("Mulai sesi berikutnya", systemImage: "arrow.right.circle") { app.attempt { try app.store.commit { try $0.nextSession() } } }
                    .font(.headline).buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity).accessibilityIdentifier("next-session")
            }
        }.padding(.horizontal, 20).padding(.vertical, 12).background(.regularMaterial)
    }
}

struct RunHistoryView: View {
    let app: POCController
    var body: some View {
        NavigationStack {
            List(app.store.state.sessions) { item in
                NavigationLink { SessionHistoryView(session: item) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(item.name, systemImage: item.closedAt == nil ? "circle.dashed" : "checkmark.circle")
                        Text(item.closedAt == nil ? "Sesi aktif" : item.closureNote == nil ? "Ditutup setelah review" : "Ditutup dengan catatan").font(.caption).foregroundStyle(.secondary)
                        Text(item.closedSummary ?? item.counts.summary).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            }.navigationTitle("Riwayat").toolbar { SheetCloseButton() }
        }
    }
}

struct SessionHistoryView: View {
    let session: AttendanceSession
    var body: some View {
        List {
            Section { Text(session.closedSummary ?? session.counts.summary); Text(session.closureNote ?? "Tanpa catatan penutupan") }
            ForEach(session.events.reversed()) { event in
                VStack(alignment: .leading, spacing: 8) { Text(event.text); Text(event.at.formatted()).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 4)
            }
        }.navigationTitle(session.name)
    }
}
