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
    let openDirections: () -> Void
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
        GeometryReader { geometry in
            Map {
                ForEach(trip.plan.stops) { item in
                    Annotation(item.name, coordinate: .init(latitude: item.location.latitude, longitude: item.location.longitude)) {
                        Image(systemName: item.id == stop?.id && arrived ? "checkmark.circle.fill" : "mappin.circle.fill")
                            .font(item.id == stop?.id ? .largeTitle : .title2)
                            .foregroundStyle(item.id == stop?.id && arrived ? .green : AppColor.brand)
                            .padding(6).background(.background, in: .circle)
                    }
                }
            }
            .accessibilityLabel("Trip stops on the map")
            .safeAreaInset(edge: .top) {
                if !arrived && trip.status != .completed, let stop {
                    HStack(spacing: 16) {
                        Image(systemName: "arrow.turn.up.right").font(.largeTitle)
                        VStack(alignment: .leading, spacing: 4) {
                            if let previewInstruction { Text(previewInstruction).font(.largeTitle.bold()) }
                            Text(isDesignPreview ? "Turn right onto Jalan Cikini Raya" : "Next stop: \(stop.name)")
                                .font(.title3)
                            if !isDesignPreview { Text("Open Maps for turn-by-turn directions").font(.footnote) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(24)
                    .frame(maxWidth: 640, alignment: .leading)
                    .foregroundStyle(.white)
                    .background(brandGradient, in: .rect(cornerRadius: 32))
                    .padding(.horizontal, 16)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if trip.status == .completed {
                            Label("Trip completed", systemImage: "checkmark.circle.fill").font(.title.bold())
                            Text("All \(trip.plan.stops.count) visits are complete.")
                            action("Back to trip", action: returnToTrip)
                        } else if let stop {
                            if arrived {
                                Label("You’ve arrived", systemImage: "checkmark.circle.fill").font(.title.bold())
                                Text("Stop \(number) of \(trip.plan.stops.count)").font(.subheadline)
                                Text(stop.name).font(.title3.bold())
                                Text("Planned visit · \(ItineraryFormatting.time(stop.visitStartsAt ?? stop.arrivalAt, zone: trip.input.timeZone, locale: locale))–\(ItineraryFormatting.time(stop.departureAt, zone: trip.input.timeZone, locale: locale))")
                                Divider().overlay(.white.opacity(0.5))
                                if let upcoming {
                                    Text("UP NEXT").font(.caption)
                                    HStack(spacing: 12) {
                                        PlaceThumbnail(imageName: details[upcoming.id]?.photoAsset, size: 48)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(upcoming.name).font(.headline)
                                            Text("\(upcoming.travelSeconds / 60) min · planned travel").font(.subheadline)
                                        }
                                    }
                                }
                                action(upcoming == nil ? "Finish last visit" : "Walk to next stop", action: completeVisit)
                                    .accessibilityIdentifier("completeTripVisit")
                            } else {
                                HStack(alignment: .firstTextBaseline) {
                                    if let previewDistance { Text(previewDistance).font(.largeTitle.bold()) }
                                    else { Text(stop.name).font(.title2.bold()) }
                                    Spacer()
                                    Text(isDesignPreview ? "6 min" : "\(stop.travelSeconds / 60) min").font(.title.bold())
                                }
                                if isDesignPreview {
                                    HStack { Text("Remaining"); Spacer(); Text("Walking") }.font(.subheadline)
                                    HStack(spacing: 12) {
                                        PlaceThumbnail(imageName: details[stop.id]?.photoAsset, size: 48)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(stop.name).font(.headline)
                                            Text("Stop \(number) of \(trip.plan.stops.count)").font(.caption)
                                        }
                                    }
                                    Divider().overlay(.white.opacity(0.5))
                                    HStack {
                                        action("Pause", action: openDirections)
                                        action("End walk", action: returnToTrip)
                                    }
                                } else {
                                    Text("Stop \(number) of \(trip.plan.stops.count) · planned travel estimate").font(.subheadline)
                                    action("Open in Maps", action: openDirections)
                                    action("I’m here", action: arrive).accessibilityIdentifier("confirmTripArrival")
                                    Text("Confirm arrival yourself when you reach the place.").font(.footnote)
                                }
                            }
                        }
                        if isDesignPreview { Text("Design preview · sample directions and estimates").font(.caption) }
                        else if trip.synthetic { Text("Synthetic trip · estimates are demonstration data").font(.caption) }
                        if let error { Label(error, systemImage: "exclamationmark.circle").font(.footnote) }
                        if isBusy { ProgressView("Updating trip…").tint(.white) }
                    }
                    .padding(24)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .frame(height: min(geometry.size.height * (dynamicTypeSize.isAccessibilitySize ? 0.62 : arrived ? 0.55 : 0.43), 520))
                .clipped()
                .accessibilityIdentifier("tripProgressPanel")
                .foregroundStyle(.white)
                .background(brandGradient, in: .rect(cornerRadius: 32))
            }
        }
        .background(AppColor.canvas)
        .navigationTitle(trip.status == .completed ? "Completed" : arrived ? "Arrival" : "On your way")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private var brandGradient: LinearGradient {
        LinearGradient(colors: [AppColor.brand, AppColor.brandGradientEnd], startPoint: .bottomLeading, endPoint: .topTrailing)
    }

    private func action(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity, minHeight: 44) }
            .buttonStyle(.borderedProminent)
            .tint(.white).foregroundStyle(AppColor.brand)
            .buttonBorderShape(.capsule)
            .disabled(isBusy)
    }
}
