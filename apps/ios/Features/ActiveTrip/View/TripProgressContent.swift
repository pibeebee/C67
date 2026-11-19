import SwiftUI
import MapKit
import C67Domain

/// TRIP STARTED and TRIP DONE (arrival at a stop), driven by accepted trip events.
struct TripProgressContent: View {
    let trip: PersonalPlanningTrip
    var details: [UUID: ItineraryStopDetails] = [:]
    var isDesignPreview = false
    var isBusy = false
    var error: String?
    var recovery: RecoveryNotice.Action?
    var previewDistance: String?
    var route: MKRoute?
    var locationError: String?
    var locationPermissionDenied = false
    let openDirections: () -> Void
    var openSettings: () -> Void = {}
    var openMaps: () -> Void = {}
    let arrive: () -> Void
    var arriveAtEndpoint: () -> Void = {}
    let completeVisit: () -> Void
    let returnToTrip: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @State private var mapPosition: MapCameraPosition = .automatic

    private var stop: ScheduledPlanningStop? { trip.nextStop }
    private var arrived: Bool { stop != nil && trip.currentStopID == stop?.id }
    private var upcoming: ScheduledPlanningStop? {
        guard let stop, let index = trip.plan.stops.firstIndex(where: { $0.id == stop.id }), index + 1 < trip.plan.stops.count else { return nil }
        return trip.plan.stops[index + 1]
    }
    private var number: Int { trip.completedStopIDs.count + 1 }

    var body: some View {
        if trip.status == .completed {
            TripCompletedContent(trip: trip, done: returnToTrip)
        } else if trip.pendingEndpoint != nil {
            VStack(spacing: 16) {
                Text(trip.plan.input.enginePreferences?.endPointName ?? "Return to starting point").font(.headline)
                if let route { Text("Estimated travel: \(Int(ceil(route.expectedTravelTime / 60))) min") }
                if let locationError { Text(locationError).font(.footnote) }
                if locationPermissionDenied { Button("Open Settings", action: openSettings) }
                if let error { RecoveryNotice(title: "Trip update needs attention", message: error, primary: recovery) }
                Button("Open directions in Maps", action: openMaps)
                Button("I’ve arrived at the endpoint", action: arriveAtEndpoint).disabled(isBusy)
            }.padding()
        } else {
            activeContent
        }
    }

    private var activeContent: some View {
        GeometryReader { geometry in
            Map(position: $mapPosition) {
                UserAnnotation()
                if let route { MapPolyline(route.polyline).stroke(.blue, lineWidth: 5) }
                ForEach(trip.plan.stops.filter { $0.id == stop?.id }) { item in
                    Annotation("", coordinate: .init(latitude: item.location.latitude, longitude: item.location.longitude)) {
                        VStack(spacing: 12) {
                            if arrived {
                                Text(item.name).font(.caption.bold()).lineLimit(1)
                                    .padding(.horizontal, 24).padding(.vertical, 8)
                                    .background(.background, in: .capsule)
                            }
                            Image(systemName: arrived ? "checkmark.circle.fill" : "mappin.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(arrived ? .green : AppColor.brand)
                                .padding(6).background(.background, in: .circle)
                        }
                        .accessibilityLabel(item.name)
                    }
                }
            }
            .onChange(of: route) { _, _ in focusRoute() }
            .accessibilityLabel("Trip stops on the map")
            .overlay(alignment: .trailing) {
                if route != nil {
                    Button(action: focusRoute) {
                        Image(systemName: "location.viewfinder")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Show route")
                    .padding(.trailing, 16)
                }
            }
            .safeAreaInset(edge: .top) {
                if trip.status != .completed, let stop {
                    HStack(spacing: 16) {
                        Image(systemName: arrived ? "checkmark.circle.fill" : "map").font(.largeTitle)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(arrived ? "You’ve arrived" : "On your way")
                                .font(.headline)
                            Text(stop.name)
                                .font(.title3.bold())
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .frame(minHeight: 90)
                    .frame(maxWidth: 640, alignment: .leading)
                    .foregroundStyle(.white)
                    .background(AppColor.brand, in: .rect(cornerRadius: 32))
                    .padding(.horizontal, 16)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: arrived ? 16 : 8) {
                        if let error {
                            RecoveryNotice(title: "Trip update needs attention", message: error, primary: recovery)
                        }
                        if trip.status == .completed {
                            Label("Trip completed", systemImage: "checkmark.circle.fill").font(.title.bold())
                            Text("All \(trip.plan.stops.count) visits are complete.")
                            action("Back to trip", action: returnToTrip)
                        } else if let stop {
                            if arrived {
                                Text("Stop \(number) of \(trip.plan.stops.count)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                HStack(spacing: 12) {
                                    PlaceThumbnail(imageName: details[stop.id]?.photoAsset, size: 48)
                                    Text(stop.name).font(.headline)
                                }
                                if trip.plan.usesExperienceFlow {
                                    if trip.input.places.first(where: { $0.id == stop.id })?.durationOverridden == true {
                                        Text("Your visit length · \(stop.visitSeconds / 60) min")
                                    } else if let duration = trip.plan.experiencePlan?.stop(stop.id)?.duration {
                                        Text("Suggested visit · \(duration.minMinutes)–\(duration.maxMinutes) min")
                                    } else { Text("Default visit · \(PlanProposal.defaultExperienceVisitSeconds / 60) min") }
                                } else {
                                    Text("Planned visit · \(ItineraryFormatting.time(stop.visitStartsAt ?? stop.arrivalAt, zone: trip.input.timeZone, locale: locale))–\(ItineraryFormatting.time(stop.departureAt, zone: trip.input.timeZone, locale: locale))")
                                }
                                Divider()
                                if let upcoming {
                                    Text("UP NEXT").font(.caption)
                                    HStack(spacing: 12) {
                                        PlaceThumbnail(imageName: details[upcoming.id]?.photoAsset, size: 48)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(upcoming.name).font(.headline)
                                            Text(!trip.plan.usesExperienceFlow ? "\(upcoming.travelSeconds / 60) min · planned travel" : ItineraryFormatting.drivingEstimate(upcoming))
                                                .font(.subheadline)
                                        }
                                    }
                                }
                                action(upcoming == nil ? "Finish last visit" : "Continue to next stop", action: completeVisit)
                                    .accessibilityIdentifier("completeTripVisit")
                                backButton
                            } else {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(previewDistance ?? route.map { Self.distance($0.distance) } ?? "—")
                                            .font(.largeTitle.bold())
                                        Text("To next stop").font(.subheadline)
                                    }
                                    Spacer()
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 8) {
                                            Image(systemName: trip.input.mode == .walking ? "figure.walk" : "car.fill").font(.title3)
                                            Text(isDesignPreview ? "6 min" : route.map { "\(Int(ceil($0.expectedTravelTime / 60))) min" } ?? "—")
                                                .font(.largeTitle.bold())
                                        }
                                        Text(trip.input.mode == .walking ? "Walk · estimate" : "Drive · estimate").font(.subheadline)
                                    }
                                }
                                HStack(spacing: 12) {
                                    PlaceThumbnail(imageName: details[stop.id]?.photoAsset, size: 48)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(stop.name).font(.headline)
                                        Text("Stop \(number) of \(trip.plan.stops.count)").font(.caption)
                                    }
                                }
                                Divider()
                                if let locationError, !isDesignPreview {
                                    Text(locationError).font(.footnote)
                                    if locationPermissionDenied { action("Open Settings", action: openSettings) }
                                    else { action("Try again", action: openDirections) }
                                } else if route == nil && !isDesignPreview {
                                    ProgressView("Finding directions…").tint(AppColor.brand)
                                }
                                Text("Arrival may be detected automatically.")
                                    .font(.footnote).foregroundStyle(.secondary)
                                directionsButton
                                ViewThatFits(in: .horizontal) {
                                    HStack { arrivalButton; backButton }
                                    VStack { arrivalButton; backButton }
                                }
                            }
                        }
                        if isDesignPreview { Text("Design preview · sample directions and estimates").font(.caption).foregroundStyle(.secondary) }
                        else if trip.synthetic { Text("Synthetic trip · estimates are demonstration data").font(.caption) }
                        if isBusy { ProgressView("Updating trip…").tint(AppColor.brand) }
                    }
                    .padding(21)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .frame(height: min(geometry.size.height * (dynamicTypeSize.isAccessibilitySize ? 0.68 : arrived ? 0.49 : 0.39), 560))
                .clipped()
                .accessibilityIdentifier("tripProgressPanel")
                .foregroundStyle(.primary)
                .modifier(TripProgressGlassPanel())
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .background(AppColor.canvas)
        .navigationTitle(arrived ? "Arrival" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }

    private var directionsButton: some View {
        action("Navigate with Apple Maps", action: openMaps)
    }

    private var arrivalButton: some View {
        Button("I’m here", action: arrive)
            .buttonStyle(.bordered).buttonBorderShape(.capsule)
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(isBusy)
            .accessibilityIdentifier("confirmTripArrival")
    }

    private var backButton: some View {
        Button("Back to trip", action: returnToTrip)
            .buttonStyle(.bordered).buttonBorderShape(.capsule)
            .frame(maxWidth: .infinity, minHeight: 44).disabled(isBusy)
    }

    private func focusRoute() {
        guard let route else { return }
        let rect = route.polyline.boundingMapRect
        guard !rect.isNull, !rect.isEmpty else { return }
        mapPosition = .rect(rect.insetBy(dx: -max(rect.size.width * 0.25, 500), dy: -max(rect.size.height * 0.25, 500)))
    }

    private static func distance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 { return "\(Int((meters / 10).rounded() * 10)) m" }
        return Measurement(value: meters / 1000, unit: UnitLength.kilometers).formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(1))))
    }

    private var brandGradient: LinearGradient {
        LinearGradient(colors: [AppColor.brand, AppColor.brandGradientEnd], startPoint: .bottomLeading, endPoint: .topTrailing)
    }

    private func action(_ title: String, tint: Color = AppColor.brand, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity, minHeight: 44) }
            .buttonStyle(.borderedProminent)
            .tint(tint).foregroundStyle(.white)
            .buttonBorderShape(.capsule)
            .disabled(isBusy)
    }
}

private struct TripProgressGlassPanel: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular, in: .rect(cornerRadius: 32))
            } else {
                fallback(content)
            }
        #else
            fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(.regularMaterial, in: .rect(cornerRadius: 32))
            .overlay { RoundedRectangle(cornerRadius: 32).strokeBorder(.white.opacity(0.7)) }
    }
}

private struct TripCompletedContent: View {
    let trip: PersonalPlanningTrip
    let done: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
                Text("Trip complete").font(.largeTitle.bold())
                Text("All \(trip.completedStopIDs.count) stops visited").foregroundStyle(.secondary)
                Text(trip.title).font(.title3.bold()).padding(.top, 12)
                Text(ItineraryFormatting.date(trip.input.startsAt, zone: trip.input.timeZone, locale: locale))
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Visited stops").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 20)
                VStack(spacing: 0) {
                    let visited = trip.plan.stops.filter { trip.completedStopIDs.contains($0.id) }
                    ForEach(Array(visited.enumerated()), id: \.element.id) { index, stop in
                        HStack(spacing: 12) {
                            PlaceThumbnail(imageName: nil, size: 48)
                            Text(stop.name).font(.headline)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                .accessibilityLabel("Visited")
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        if index < visited.count - 1 { Divider().padding(.leading, 76) }
                    }
                }
                .background(AppColor.surface, in: .rect(cornerRadius: 20))
            }
            .padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(AppColor.canvas)
        .safeAreaInset(edge: .bottom) {
            Button(action: done) { Text("Done").frame(maxWidth: .infinity, minHeight: 44) }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .frame(maxWidth: 640).padding(.horizontal, 24).padding(.vertical, 12)
                .background(AppColor.canvas)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("tripCompletedSummary")
    }
}
