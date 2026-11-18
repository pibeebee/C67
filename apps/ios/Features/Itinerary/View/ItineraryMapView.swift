import SwiftUI
import MapKit
import C67Domain

struct ItineraryMapView: View {
    private static let stopColors: [Color] = [.blue, .orange, .purple, .teal, .pink, .brown]

    private struct RouteTaskID: Equatable {
        let path: [PlanningPoint]
        let retry: Int
    }
    let proposal: PlanProposal
    @State private var routes: [Int: MKRoute] = [:]
    @State private var loadedPath: [PlanningPoint] = []
    @State private var routeUnavailable = false
    @State private var isLoadingRoutes = false
    private var path: [PlanningPoint] { [proposal.input.origin] + proposal.stops.map(\.location) }
    @State private var showsFullMap = false
    @State private var retryGeneration = 0

    var body: some View {
        VStack(spacing: 0) {
            routeMap
                .frame(height: 200)
                .overlay(alignment: .topTrailing) {
                    Button { showsFullMap = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .frame(width: 44, height: 44)
                            .background(.regularMaterial, in: .circle)
                    }
                    .accessibilityLabel("Expand map")
                    .accessibilityIdentifier("itineraryExpandMap")
                    .padding(8)
                }
            if routeUnavailable {
                routeFailure
            }
            ForEach(proposal.evidence.filter { $0.kind == "weather" && $0.attributionLogoURL != nil }) { evidence in
                if let url = evidence.url, let logo = evidence.attributionLogoURL, url.scheme == "https", logo.host == "weatherkit.apple.com" {
                    Link(destination: url) {
                        AsyncImage(url: logo) { image in image.resizable().scaledToFit() } placeholder: { Text("Apple Weather") }
                            .frame(width: 120, height: 28)
                            .padding(6).background(.white)
                    }
                    .accessibilityLabel("Apple Weather and data sources")
                }
            }

            DisclosureGroup("Trip details") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Route estimates").font(.headline)
                    if !proposal.usesExperienceFlow {
                        Text(proposal.explanation)
                        ForEach(proposal.warnings, id: \.self) { Text($0) }
                    } else {
                        Text("Itinerary method").font(.headline)
                        switch proposal.effectiveOrderingMethod {
                        case .luna: Text("Luna")
                        case .hybridLegacy: Text("Hybrid: candidates (retired)")
                        case .hybridV4, .hybridV41, .hybridV42, .hybridV42FoundationModels:
                            if proposal.effectiveOrderingMethod == .hybridV42FoundationModels {
                                Text("Hybrid v4.2 · Foundation Models (experimental)")
                            } else if proposal.effectiveOrderingMethod == .hybridV42 {
                                Text("Hybrid v4.2 · Luna (experimental)")
                            } else if proposal.effectiveOrderingMethod == .hybridV41 {
                                Text("Hybrid v4.1: flexible schedules (experimental)")
                            } else {
                                Text("Hybrid v4: schedules (experimental)")
                            }
                            Text(proposal.explanation)
                            if proposal.effectiveOrderingMethod.usesFlexibleSchedule, proposal.experiencePlan == nil {
                                Text("Visit durations were supplied by you.")
                            }
                            ForEach(proposal.warnings, id: \.self) { Text($0) }
                            ForEach(Array(Set(proposal.stops.flatMap(\.warnings))).sorted(), id: \.self) { Text($0) }
                        case .hybridWeather:
                            Text("Hybrid: weather context (experimental)")
                            Text("Activity exposure and candidate arrival times were unavailable, so heat and rain exposure were not compared.")
                        }
                        Text(proposal.synthetic ? "Driving times and distances are synthetic examples." : "Driving times and road distances are estimated by Apple Maps. Travel conditions can change.")
                        if proposal.hasExperienceTravelFallback {
                            Text("Legs without a driving estimate use a \(PlanProposal.defaultExperienceTravelSeconds / 60)-minute default. Their road distance is unavailable.")
                        }
                        Text("Opening hours").font(.headline)
                        Text("Regular hours do not verify opening or access on the selected date.")
                    }
                    if !proposal.evidence.isEmpty { Text("Sources").font(.headline) }
                    ForEach(proposal.evidence) { evidence in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(evidence.label).fontWeight(.semibold)
                            Text(evidence.summary)
                            Text("Checked \(evidence.checkedAt.formatted())")
                                .foregroundStyle(.secondary)
                            if let url = evidence.url, url.scheme == "https" {
                                Link("Open source", destination: url)
                            }
                            if let logo = evidence.attributionLogoURL,
                               logo.scheme == "https", logo.host == "weatherkit.apple.com" {
                                AsyncImage(url: logo) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: { Text("Apple Weather") }
                                    .frame(width: 120, height: 28)
                                    .padding(6)
                                    .background(.white)
                                    .accessibilityLabel("Apple Weather")
                            }
                        }
                    }
                }
                .font(.footnote)
                .padding(.vertical, 8)
            }
            .font(.footnote)
            .foregroundStyle(.primary)
            .padding(12)
        }
        .background(Color("ItinerarySurface"))
        .clipShape(.rect(cornerRadius: 14))
        .task(id: RouteTaskID(path: path, retry: retryGeneration)) { await loadRoutes() }
        .fullScreenCover(isPresented: $showsFullMap) {
            NavigationStack {
                routeMap
                    .ignoresSafeArea(edges: .bottom)
                    .safeAreaInset(edge: .bottom) {
                        if routeUnavailable { routeFailure.background(.regularMaterial) }
                    }
                    .navigationTitle("Itinerary map")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsFullMap = false }
                                .accessibilityIdentifier("itineraryCloseMap")
                        }
                    }
            }
        }
    }

    private var routeFailure: some View {
        RecoveryNotice(title: "Driving routes incomplete",
                       message: isLoadingRoutes ? "Checking the missing routes…" : "Some routes couldn’t be drawn. You can still see all the stops.",
                       primary: isLoadingRoutes ? nil : .init(title: "Try loading routes again") { retryGeneration += 1 })
    }

    private var routeMap: some View {
        Map(interactionModes: [.pan, .zoom]) {
            ForEach(routes.keys.sorted(), id: \.self) { index in
                if let route = routes[index], loadedPath == path {
                    MapPolyline(route.polyline)
                        .stroke(stopColor(at: index - 1), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
            ForEach(Array(proposal.stops.enumerated()), id: \.element.id) { index, stop in
                Annotation(stop.name, coordinate: .init(latitude: stop.location.latitude, longitude: stop.location.longitude)) {
                    Text(index + 1, format: .number)
                        .font(.footnote.weight(.bold).monospacedDigit())
                        .foregroundStyle(.black)
                        .padding(6)
                        .frame(minWidth: 30, minHeight: 30)
                        .background(.white, in: .capsule)
                        .overlay(Capsule().strokeBorder(stopColor(at: index), lineWidth: 3))
                        .accessibilityLabel("Stop \(index + 1): \(stop.name)")
                }
            }
        }
        .accessibilityLabel("Itinerary places on the map")
    }

    private func stopColor(at index: Int) -> Color {
        Self.stopColors[index % Self.stopColors.count]
    }

    private func loadRoutes() async {
        let requestedPath = path
        if requestedPath != loadedPath {
            routes = [:]
            routeUnavailable = false
            loadedPath = requestedPath
        }
        guard !proposal.synthetic else { return }
        isLoadingRoutes = true
        defer { if !Task.isCancelled { isLoadingRoutes = false } }
        for index in requestedPath.indices.dropFirst() where routes[index] == nil {
            guard !Task.isCancelled else { return }
            let origin = requestedPath[index - 1], destination = requestedPath[index]
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: origin.latitude, longitude: origin.longitude)))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: destination.latitude, longitude: destination.longitude)))
            request.transportType = .automobile
            let directions = MKDirections(request: request)
            do {
                let result = try await withTaskCancellationHandler { try await directions.calculate() } onCancel: { directions.cancel() }
                guard !Task.isCancelled else { return }
                if let route = result.routes.first { routes[index] = route } else { routeUnavailable = true }
            } catch { if !Task.isCancelled { routeUnavailable = true } }
        }
        guard !Task.isCancelled else { return }
        routeUnavailable = routes.count < requestedPath.count - 1
    }
}
