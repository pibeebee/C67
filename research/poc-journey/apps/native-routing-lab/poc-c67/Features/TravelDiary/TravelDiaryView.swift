import MapKit
import SwiftUI
import UIKit

struct TravelDiaryView: View {
    @State private var store: DiaryStore
    @State private var presence = DiaryPresence()
    @State private var camera: MapCameraPosition = .automatic
    @State private var showsMemory = false
    @State private var showsSetup = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            let temporary = args.contains("--diary-demo") || args.contains("--diary-ui-testing")
            _store = State(initialValue: temporary ? DiaryStore(url: nil) : DiaryStore.live())
        #else
            _store = State(initialValue: DiaryStore.live())
        #endif
    }

    var body: some View {
        NavigationStack {
            Map(position: $camera) {
                MapCircle(center: store.pin.coordinate, radius: store.pin.radius)
                    .foregroundStyle(DiaryStyle.accent.opacity(0.10))
                    .stroke(DiaryStyle.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                Annotation(store.pin.title, coordinate: store.pin.coordinate, anchor: .bottom) {
                    Button { showsMemory = true } label: {
                        DiaryPhotoStamp(original: store.pin.photo, footprint: store.footprints.first?.photo)
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("diary-pin")
                }
                if let sample = presence.latest, presence.running {
                    Annotation("Posisimu", coordinate: sample.coordinate) {
                        Circle().fill(.blue).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 3)).shadow(radius: 3)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .mapControls { MapCompass(); MapScaleView() }
            .safeAreaInset(edge: .top, spacing: 0) { mapHeading }
            .safeAreaInset(edge: .bottom) {
                Button { showsMemory = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "envelope.open").font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.pin.title).font(.headline)
                            Text("Kenangan dari \(store.pin.creator)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.up").font(.subheadline.weight(.semibold))
                    }
                    .padding(18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                }
                .buttonStyle(.plain).padding().accessibilityIdentifier("diary-open-memory")
            }
            .navigationTitle("Jejak").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Atur pin uji", systemImage: "slider.horizontal.3") { showsSetup = true }
                        .accessibilityIdentifier("diary-setup")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Pusatkan peta", systemImage: "scope") { focusPin() }.labelStyle(.iconOnly)
                }
            }
            .sheet(isPresented: $showsMemory) {
                DiaryMemorySheet(store: store, presence: presence)
                    .presentationDetents([.height(340), .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .height(340)))
            }
            .sheet(isPresented: $showsSetup) { DiaryPinSetup(store: store, presence: presence) }
            .onChange(of: store.pin.id) { _, _ in focusPin() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, presence.activated { presence.start(pin: store.pin) }
                else if phase != .active { presence.stop() }
            }
            .onDisappear { presence.stop() }
            .task {
                focusPin()
                if presence.demo != nil { presence.start(pin: store.pin) }
            }
        }
        .tint(DiaryStyle.accent)
    }

    private var mapHeading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Satu tempat,\ncerita yang berbeda.").font(.system(.title, design: .serif).weight(.medium))
            Text("Peta kenangan \(store.pin.creator)").font(.subheadline).foregroundStyle(.secondary)
            if presence.simulated {
                Label("SIMULASI LOKASI · UJI PoC", systemImage: "testtube.2").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
            }
            Text("PoC lokal · belum dibagikan ke perangkat lain").font(.caption2).foregroundStyle(.secondary)
            if let error = store.loadError { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20).background(.regularMaterial)
    }

    private func focusPin() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            camera = .region(MKCoordinateRegion(center: store.pin.coordinate, latitudinalMeters: 900, longitudinalMeters: 900))
        }
    }
}

struct DiaryMemorySheet: View {
    let store: DiaryStore
    let presence: DiaryPresence
    @State private var showsComposer = false
    @State private var showsSetup = false
    @State private var showsPostcard = false
    @State private var previousInside = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let state = presence.state(for: store.pin, now: context.date)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        presencePanel(state)
                        if let footprint = store.footprints.first {
                            DiaryPostcard(pin: store.pin, footprint: footprint)
                            Button("Lihat kartu kenangan", systemImage: "rectangle.on.rectangle") { showsPostcard = true }
                        } else {
                            DiaryMomentCard(photo: store.pin.photo, heading: "Dulu di sini", name: store.pin.creator, date: store.pin.visitedAt)
                                .frame(maxWidth: 450).frame(maxWidth: .infinity)
                        }
                        Text(store.pin.story).font(.body).lineSpacing(4)
                        Label("Foto versimu bebas: selfie, pemandangan, atau hasil editan.", systemImage: "camera")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("Unggahan PoC disimpan pada iPhone ini. Lokasi diperiksa kembali saat kamu menekan unggah.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(20)
                }
                .onChange(of: state.canAddPhoto) { _, inside in
                    if inside && !previousInside && sceneIsActive { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
                    previousInside = inside
                }
            }
            .navigationTitle(store.pin.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Atur pin uji", systemImage: "slider.horizontal.3") { showsSetup = true }
                }
            }
            .sheet(isPresented: $showsComposer) { DiaryFootprintComposer(store: store, presence: presence) }
            .sheet(isPresented: $showsSetup) { DiaryPinSetup(store: store, presence: presence) }
            .sheet(isPresented: $showsPostcard) {
                NavigationStack {
                    if let footprint = store.footprints.first { ScrollView { DiaryPostcard(pin: store.pin, footprint: footprint).padding(20) } }
                    Text("Tersimpan di perangkat ini").font(.caption).foregroundStyle(.secondary)
                    Button("Selesai") { showsPostcard = false }.padding()
                }
            }
            .task {
                while !Task.isCancelled {
                    presence.refreshDemo(pin: store.pin)
                    do { try await Task.sleep(for: .seconds(1)) } catch { break }
                }
            }
        }
    }

    private var sceneIsActive: Bool { UIApplication.shared.applicationState == .active }

    private func presencePanel(_ state: DiaryPresenceState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(state.title, systemImage: state.canAddPhoto ? "location.fill" : "location")
                .font(.headline).accessibilityIdentifier("diary-presence-state")
            Text(state.explanation).font(.subheadline).foregroundStyle(.secondary)
            if !presence.running || presence.blocked {
                Button(presence.blocked ? "Buka Pengaturan Lokasi" : "Aktifkan lokasi") {
                    if presence.blocked { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                    else { presence.start(pin: store.pin) }
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("diary-enable-location")
            } else {
                Button {
                    showsComposer = true
                } label: {
                    Label(state.canAddPhoto ? "Tinggalkan jejak fotomu" : "Datang untuk menambahkan jejak", systemImage: state.canAddPhoto ? "camera.fill" : "lock")
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!state.canAddPhoto || store.loadError != nil)
                .accessibilityIdentifier("diary-add-footprint")
            }
            if presence.simulated {
                Label("Simulasi · tidak membuktikan kunjungan nyata", systemImage: "testtube.2")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(state.canAddPhoto ? DiaryStyle.accent.opacity(0.10) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: state.canAddPhoto)
    }
}

#Preview { TravelDiaryView() }
