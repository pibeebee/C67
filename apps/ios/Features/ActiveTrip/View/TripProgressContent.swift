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
    var previewInstruction: String?
    var previewDistance: String?
    var route: MKRoute?
    var locationError: String?
    let openDirections: () -> Void
    var openMaps: () -> Void = {}
    let arrive: () -> Void
    let completeVisit: () -> Void
    let returnToTrip: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

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
        } else {
            activeContent
        }
    }

    private var activeContent: some View {
        GeometryReader { geometry in
            Map {
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
            .accessibilityLabel("Trip stops on the map")
            .safeAreaInset(edge: .top) {
                if !arrived && trip.status != .completed, let stop {
                    HStack(spacing: 16) {
                        Image(systemName: isDesignPreview ? "arrow.turn.up.right" : "map").font(.largeTitle)
                        VStack(alignment: .leading, spacing: 4) {
                            if let previewInstruction { Text(previewInstruction).font(.largeTitle.bold()) }
                            Text(isDesignPreview ? "Turn right onto Jalan Cikini Raya" : "Directions to \(stop.name)")
                                .font(.title3)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 24)
                    .frame(minHeight: 154)
                    .frame(maxWidth: 640, alignment: .leading)
                    .foregroundStyle(.white)
                    .background(AppColor.brand, in: .rect(cornerRadius: 32))
                    .padding(.horizontal, 16)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: arrived ? 16 : 8) {
                        if trip.status == .completed {
                            Label("Trip completed", systemImage: "checkmark.circle.fill").font(.title.bold())
                            Text("All \(trip.plan.stops.count) visits are complete.")
                            action("Back to trip", action: returnToTrip)
                        } else if let stop {
                            if arrived {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title).foregroundStyle(.green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("You’ve arrived").font(.title.bold())
                                        Text("Stop \(number) of \(trip.plan.stops.count)")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                Text(stop.name).font(.system(size: 20, weight: .semibold))
                                if trip.plan.experiencePlan != nil {
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
                                            Text(trip.plan.experiencePlan == nil ? "\(upcoming.travelSeconds / 60) min · planned travel" : ItineraryFormatting.drivingEstimate(upcoming))
                                                .font(.subheadline)
                                        }
                                    }
                                }
                                action(upcoming == nil ? "Finish last visit" : (isDesignPreview ? "Walk to next stop" : "Continue to next stop"), action: completeVisit)
                                    .accessibilityIdentifier("completeTripVisit")
                            } else {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(previewDistance ?? route.map { Self.distance($0.distance) } ?? "—")
                                            .font(.system(size: 34, weight: .bold))
                                        Text("Remaining").font(.subheadline)
                                    }
                                    Spacer()
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "car.fill").font(.title3)
                                            Text(isDesignPreview ? "6 min" : route.map { "\(Int(ceil($0.expectedTravelTime / 60))) min" } ?? "—")
                                                .font(.system(size: 34, weight: .bold))
                                        }
                                        Text("Driving · estimate").font(.subheadline)
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
                                    action("Try again", action: openDirections)
                                } else if route == nil && !isDesignPreview {
                                    ProgressView("Finding directions…").tint(AppColor.brand)
                                }
                                HStack {
                                    action(isDesignPreview ? "End trip" : "Back to trip", tint: .red, action: returnToTrip)
                                    action(isDesignPreview ? "Pause trip" : "Open in Maps", tint: .blue, action: isDesignPreview ? openDirections : openMaps)
                                }
                            }
                        }
                        if isDesignPreview { Text("Design preview · sample directions and estimates").font(.caption).foregroundStyle(.secondary) }
                        else if trip.synthetic { Text("Synthetic trip · estimates are demonstration data").font(.caption) }
                        if let error { Label(error, systemImage: "exclamationmark.circle").font(.footnote) }
                        if isBusy { ProgressView("Updating trip…").tint(AppColor.brand) }
                    }
                    .padding(arrived ? 30 : 21)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .frame(height: min(geometry.size.height * (dynamicTypeSize.isAccessibilitySize ? 0.62 : arrived ? 0.49 : 0.30), 520))
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
        .toolbar(arrived ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
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
                    ForEach(trip.plan.stops.filter { trip.completedStopIDs.contains($0.id) }) { stop in
                        HStack {
                            Image(systemName: "mappin.circle.fill").font(.title2).foregroundStyle(AppColor.brand)
                            Text(stop.name).font(.headline)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        .padding(16)
                    }
                }
                .background(AppColor.surface, in: .rect(cornerRadius: 20))
                Button(action: done) { Text("Done").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).padding(.top, 20)
            }
            .padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(AppColor.canvas)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("tripCompletedSummary")
    }
}
