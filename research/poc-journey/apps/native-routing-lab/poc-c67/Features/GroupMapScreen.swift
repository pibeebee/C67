import MapKit
import SwiftUI

struct GroupMapScreen: View {
    let app: POCController
    let audience: MapAudience
    var initialActivityID: UUID? = nil
    @Environment(\.scenePhase) private var phase
    // This sensor belongs to the map only. It has no CloudKit callbacks or background session.
    @State private var localSensor = LocationService()
    private var localContext: String {
        "\(app.store.state.runID)|\(app.store.state.mode)|\(phase == .background)|\(app.sensor.running)|\(app.leaderSharing.sensor.running)"
    }
    private var ownStatus: String {
        if app.leaderSharing.sensor.running { return app.leaderSharing.sensor.status }
        if app.sensor.running { return app.sensor.status }
        return localSensor.status
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            GroupMapCanvas(app: app, audience: audience, initialActivityID: initialActivityID, now: timeline.date,
                           localSample: localSensor.running ? localSensor.latest : nil,
                           localStatus: ownStatus)
        }
        .onAppear { updateLocalSensor() }
        .onChange(of: localContext) { _, _ in localSensor.stop(); updateLocalSensor() }
        .onDisappear { localSensor.stop() }
    }
    private func updateLocalSensor() {
        guard phase != .background, app.store.state.mode == .real,
              !app.sensor.running, !app.leaderSharing.sensor.running else { localSensor.stop(); return }
        guard !localSensor.running else { return }
        localSensor.start(runID: app.store.state.runID, epoch: UUID(), expiresAt: .now.addingTimeInterval(7200), background: false)
    }
}

private struct GroupMapCanvas: View {
    let app: POCController
    let audience: MapAudience
    let initialActivityID: UUID?
    let now: Date
    let localSample: LocationSample?
    let localStatus: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var camera: MapCameraPosition = .automatic
    @State private var selected: String?
    @State private var selectedActivity: UUID?
    @State private var detail: ActivityMapPresentation?
    @State private var list: ScannerPresentation?
    @State private var satellite = false
    @State private var cameraChanges = 0
    @State private var waitingForInitialLocation = false
    private var points: [GroupMapPoint] { app.mapPoints(for: audience, localSample: localSample, now: now) }
    private var routing: GroupRouteSession { app.groupRouting }
    private var own: GroupMapPoint? { points.first { $0.id == (audience == .leader ? "TL" : "YOU") } }
    private var activities: [TourActivity] { app.store.state.effectivePlan.sortedActivities }
    private var chosenActivity: TourActivity? { activities.first { $0.id == selectedActivity } }
    private var chosen: GroupMapPoint? { points.first { $0.id == selected } }
    private var missing: [Participant] {
        audience == .leader ? (app.store.state.sessions.last?.participants ?? []).filter { p in !points.contains { $0.id == p.id } } : []
    }
    var body: some View {
        NavigationStack {
            Map(position: $camera, interactionModes: .all) {
                if let route = routing.engine.route, routing.active {
                    MapPolyline(route.polyline).stroke(routing.inputsReady && routing.engine.errorMessage == nil ? .indigo : .gray, lineWidth: 6)
                    if let snapshot = routing.engine.routeSnapshot,
                       let target = currentRoutingInput?.target?.coordinate, meters(target, snapshot.target) > 10 {
                        Annotation("Tujuan saat rute dihitung", coordinate: snapshot.target) {
                            Image(systemName: "flag.circle.fill").foregroundStyle(.gray).padding(4).background(.background, in: Circle())
                        }
                    }
                }
                if let meeting {
                    if app.store.state.effectivePlan.activeActivityID == nil {
                        Marker(app.store.state.effectivePlan.meetingName ?? "Meeting point", systemImage: "flag.fill", coordinate: meeting).tint(.orange)
                    }
                    MapCircle(center: meeting, radius: app.store.state.meetingRadius).foregroundStyle(.orange.opacity(0.12))
                }
                ForEach(activities.filter { $0.place != nil }) { activity in
                    if let place = activity.place {
                        Annotation(activity.title, coordinate: place.coordinate) {
                            Button { selectActivity(activity) } label: {
                                Image(systemName: activity.id == app.store.state.effectivePlan.activeActivityID ? "flag.fill" : "calendar")
                                    .font(.headline).foregroundStyle(.white).frame(width: 42, height: 42)
                                    .background(.indigo, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white, lineWidth: selectedActivity == activity.id ? 4 : 2))
                            }.buttonStyle(.plain).accessibilityLabel("Kegiatan: \(activity.title)").accessibilityIdentifier("map-activity-\(activity.id)")
                        }
                    }
                }
                ForEach(points) { point in
                    Annotation(point.name, coordinate: CLLocationCoordinate2D(latitude: point.sample.latitude, longitude: point.sample.longitude)) {
                        Button { select(point) } label: {
                            VStack(spacing: 3) {
                                Image(systemName: point.kind == .leader ? "person.fill.badge.plus" : point.kind == .you ? "location.fill" : "person.fill")
                                    .font(.headline).foregroundStyle(.white).frame(width: 42, height: 42)
                                    .background(color(point), in: Circle()).overlay(Circle().stroke(.white, lineWidth: selected == point.id ? 4 : 2))
                                if now.timeIntervalSince(point.sample.measuredAt) > LocationRules.staleAfter { Text("Lama").font(.caption2.bold()).padding(3).background(.regularMaterial, in: Capsule()) }
                            }
                        }.buttonStyle(.plain).accessibilityLabel(point.name + (now.timeIntervalSince(point.sample.measuredAt) > LocationRules.staleAfter ? ", lokasi kedaluwarsa" : ", lokasi terakhir"))
                            .accessibilityIdentifier("map-pin-\(point.id)")
                    }
                }
                if let chosen {
                    MapCircle(center: CLLocationCoordinate2D(latitude: chosen.sample.latitude, longitude: chosen.sample.longitude), radius: chosen.sample.accuracy).foregroundStyle(color(chosen).opacity(0.12))
                }
            }
            .mapStyle(satellite ? .imagery : .standard(elevation: .realistic))
            .mapControls { MapCompass(); MapScaleView() }
            .onMapCameraChange(frequency: .onEnd) { _ in cameraChanges += 1 }
            .accessibilityIdentifier("interactive-group-map").accessibilityValue("Tampilan diperbarui \(cameraChanges)")
            .safeAreaInset(edge: .top, spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        Button("Lihat semua", systemImage: "arrow.up.left.and.arrow.down.right") { fitAll(); selected = nil; selectedActivity = nil }.accessibilityIdentifier("map-fit-all")
                        Button("Lokasi saya", systemImage: "location.fill") { if let own { select(own) } }
                            .disabled(own == nil).accessibilityIdentifier("map-my-location")
                        if let meeting {
                            Button("Meeting point", systemImage: "flag") { camera = .region(MKCoordinateRegion(center: meeting, latitudinalMeters: 800, longitudinalMeters: 800)); selected = nil; selectedActivity = nil }
                                .accessibilityIdentifier("map-meeting-point")
                        }
                    }.buttonStyle(.bordered).buttonBorderShape(.capsule).padding(.horizontal).padding(.vertical, 8)
                }.background(.regularMaterial)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if app.store.state.mode == .simulation { ModeBadge(mode: .simulation) }
                        Text(audience == .leader ? "\(points.filter { $0.kind == .participant }.count) lokasi peserta · \(missing.count) tanpa lokasi" : "Lokasi Anda & tour leader").font(.caption).accessibilityIdentifier("map-point-count")
                        Spacer()
                        Button("Daftar", systemImage: "list.bullet") { list = ScannerPresentation() }.accessibilityIdentifier("map-list")
                    }
                    if let activity = chosenActivity {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(activity.title).font(.headline).accessibilityIdentifier("map-selected-activity")
                            Text(activity.timeLabel).font(.caption)
                            Button("Detail kegiatan", systemImage: "calendar") { detail = ActivityMapPresentation(activity: activity) }.accessibilityIdentifier("map-activity-detail")
                        }
                    } else if let chosen {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(chosen.name).font(.headline).accessibilityIdentifier("map-selected-name")
                                LocationReadout(sample: chosen.sample)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 190)
                    } else {
                        Text(audience == .leader ? "Geser, cubit untuk zoom, atau ketuk pin peserta. Lokasi belum tersedia tidak diberi pin." : app.leaderLocation.status)
                            .font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("map-status")
                    }
                    if let destination = selectedRoutingDestination {
                        Button(destinationLabel, systemImage: "point.bottomleft.forward.to.point.topright.scurvepath") {
                            routing.start(app.routingInput(for: audience, destination: destination, localSample: localSample, now: now),
                                          now: now, foreground: phase == .active)
                        }.accessibilityIdentifier("map-start-routing")
                        if let reason = app.routingInput(for: audience, destination: destination, localSample: localSample, now: now).problem,
                           !routing.active {
                            Text(reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    GroupRouteStatusView(session: routing, now: now) { fitRoute() }
                    if let active = app.store.state.effectivePlan.activeActivity {
                        Text("Berkumpul: \(active.title) · \(active.timeLabel)").font(.caption).foregroundStyle(.indigo)
                    }
                    if audience == .participant {
                        Text(app.store.state.mode == .real && app.store.state.leaderBinding == nil ? "Tanpa koneksi TL · rundown/titik tersimpan mungkin lama" : app.planSync.status)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(2).accessibilityIdentifier("map-plan-sync-status")
                    }
                    if meeting == nil { Text("Meeting point belum ditentukan").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("map-no-meeting-point") }
                    if own == nil, app.store.state.mode == .real {
                        Text("Lokasi saya: \(localStatus)").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("map-own-location-status")
                    }
                    Text("Lokasi saya di peta tidak otomatis dibagikan.").font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Text("Lokasi adalah petunjuk, bukan bukti hadir.").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button("Refresh", systemImage: "arrow.clockwise") { Task { if audience == .leader { await app.planSync.publish(); await app.fetch() } else { await app.planSync.fetch(); await app.fetchLeaderLocation() } } }
                    }
                }.padding().background(.regularMaterial)
            }
            .navigationTitle(audience == .leader ? "Peta rombongan" : "Posisi tour leader")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(satellite ? "Peta standar" : "Satelit", systemImage: "map") { satellite.toggle() }
                        .labelStyle(.iconOnly).accessibilityIdentifier("map-style")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Selesai") { dismiss() } }
            }
            .task {
                routing.enter(scope: app.routingScope(for: audience))
                if let activity = activities.first(where: { $0.id == initialActivityID }) { selectActivity(activity) } else { fitAll() }
                waitingForInitialLocation = points.isEmpty && meeting == nil && activities.allSatisfy { $0.place == nil }
            }
            .onChange(of: now) { _, _ in refreshRouting() }
            .onChange(of: phase) { _, _ in refreshRouting() }
            .onDisappear { routing.stop() }
            .onChange(of: activities) { _, items in
                if let selectedActivity, !items.contains(where: { $0.id == selectedActivity && $0.place != nil }) { self.selectedActivity = nil }
            }
            .onChange(of: points.map(\.id)) { _, ids in
                if let selected, !ids.contains(selected) { self.selected = nil }
                if waitingForInitialLocation, !ids.isEmpty { fitAll(); waitingForInitialLocation = false }
            }
            .sheet(item: $detail) { item in
                NavigationStack { ActivityDetailView(app: app, activityID: item.id, audience: audience, showsMapButton: false).toolbar { SheetCloseButton() } }
            }
            .sheet(item: $list) { _ in
                NavigationStack {
                    List {
                        Section("Rundown") {
                            ForEach(activities) { activity in
                                Button { selectActivity(activity); list = nil } label: {
                                    VStack(alignment: .leading) { Label(activity.title, systemImage: "calendar"); Text(activity.place?.name ?? "Tanpa lokasi").font(.caption) }
                                }.disabled(activity.place == nil).accessibilityIdentifier("map-list-activity-\(activity.id)")
                            }
                            if activities.isEmpty { Text("Belum ada kegiatan") }
                        }
                        Section("Lokasi tersedia") {
                            ForEach(points) { point in
                                Button { select(point); list = nil } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Label(point.name, systemImage: point.kind == .leader ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                                        Text(LocationRules.freshness(point.sample)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }.accessibilityIdentifier("map-person-\(point.id)")
                            }
                            if points.isEmpty { Text("Belum ada posisi. Tunggu izin, koneksi dan sampel GPS.") }
                        }
                        if audience == .leader, !missing.isEmpty {
                            Section("Belum ada lokasi") {
                                ForEach(missing) { p in VStack(alignment: .leading) { Text("\(p.name) · \(p.displayID)"); Text(app.locations[p.id]?.status ?? "Belum terhubung / menunggu lokasi").font(.caption).foregroundStyle(.secondary) } }
                            }
                        }
                    }.navigationTitle("Lokasi rombongan").toolbar { SheetCloseButton() }
                }
            }
        }
    }
    private var selectedRoutingDestination: GroupRouteDestination? {
        if let activity = chosenActivity, activity.place != nil { return .activity(activity.id) }
        if let chosen, chosen.id != own?.id { return .person(chosen.id) }
        if chosen == nil, chosenActivity == nil, meeting != nil { return .meeting }
        return nil
    }
    private var destinationLabel: String {
        if chosenActivity != nil { return "Rute ke kegiatan ini" }
        if chosen != nil { return audience == .participant ? "Ikuti posisi tour leader" : "Ikuti posisi peserta ini" }
        return "Rute ke meeting point"
    }
    private var currentRoutingInput: GroupRouteInput? {
        routing.destination.map { app.routingInput(for: audience, destination: $0, localSample: localSample, now: now) }
    }
    private func refreshRouting() {
        if let input = currentRoutingInput { routing.refresh(input, now: now, foreground: phase == .active) }
    }
    private func fitRoute() {
        guard let route = routing.engine.route else { return }
        let rect = route.polyline.boundingMapRect
        camera = .rect(rect.insetBy(dx: -max(150, rect.width * 0.15), dy: -max(150, rect.height * 0.15)))
    }
    private var meeting: CLLocationCoordinate2D? {
        app.store.state.meetingPoint.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
    private func color(_ point: GroupMapPoint) -> Color { now.timeIntervalSince(point.sample.measuredAt) > LocationRules.staleAfter ? .orange : point.kind == .leader ? .purple : point.kind == .you ? .blue : TourStyle.accent }
    private func select(_ point: GroupMapPoint) {
        selectedActivity = nil; selected = point.id
        camera = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: point.sample.latitude, longitude: point.sample.longitude), latitudinalMeters: max(500, min(5000, point.sample.accuracy * 4)), longitudinalMeters: max(500, min(5000, point.sample.accuracy * 4))))
    }
    private func selectActivity(_ activity: TourActivity) {
        guard let place = activity.place else { return }
        selected = nil; selectedActivity = activity.id
        camera = .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000))
    }
    private func fitAll() {
        var rect = MKMapRect.null
        for coordinate in points.map({ CLLocationCoordinate2D(latitude: $0.sample.latitude, longitude: $0.sample.longitude) }) + activities.compactMap({ $0.place?.coordinate }) + [meeting].compactMap({ $0 }) {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x - 200, y: point.y - 200, width: 400, height: 400))
        }
        camera = rect.isNull ? .automatic : .rect(rect.insetBy(dx: -rect.width * 0.15, dy: -rect.height * 0.15))
    }
}
