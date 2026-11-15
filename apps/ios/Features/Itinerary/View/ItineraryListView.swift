import SwiftUI
import UniformTypeIdentifiers
import C67Domain

struct ItineraryListView: View {
    @ScaledMetric(relativeTo: .caption) private var timelineIndent = 34
    let proposal: PlanProposal
    var excludedPlaces: [String] = []
    var editEndpoints: ((ItineraryEditRoute) -> Void)?
    var details: [UUID: ItineraryStopDetails] = [:]
    var departureWeather: String?
    var isDesignPreview = false
    var isSaving = false
    var error: String?
    var canSave = true
    var heading: String?
    var editTitle: (() -> Void)?
    var editDeparture: (() -> Void)?
    var startNow: (() -> Void)?
    var actionTitle = "Save Itinerary"
    var allowsEditing = true
    var navigationTitle = "Itinerary"
    var retry: (() -> Void)?
    var refreshRoute: (() -> Void)?
    let edit: (UUID?) -> Void
    let save: () -> Void
    var move: (@MainActor @Sendable (UUID, UUID) -> Void)? = nil
    @State private var draggedStop: UUID?

    var body: some View {
        let stops = proposal.stopsWithExperienceEstimates
        let isExperience = proposal.experiencePlan != nil
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isExperience {
                    HStack(spacing: 4) {
                        Text(heading ?? proposal.input.title)
                            .font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        if let editTitle {
                            Button(action: editTitle) {
                                Image(systemName: "pencil").font(.subheadline).frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit trip name")
                            .accessibilityIdentifier("itineraryEditTitle")
                        }
                    }
                    .padding(.horizontal, 4)
                } else {
                    Text(heading ?? (!excludedPlaces.isEmpty ? "Your itinerary is partly ready" : proposal.feasible ? "Here’s your itinerary" : "Your choices need adjustment"))
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 4)
                }

                ItineraryDepartureCard(proposal: proposal, weatherAdvice: departureWeather, isDesignPreview: isDesignPreview,
                                       editDeparture: editDeparture, editEndpoints: isExperience ? editEndpoints : nil)

                if let editEndpoints, !isExperience {
                    ViewThatFits(in: .horizontal) {
                        HStack { tripEdits(editEndpoints) }
                        VStack(alignment: .leading) { tripEdits(editEndpoints) }
                    }
                    .buttonStyle(.bordered)
                }
                if !excludedPlaces.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Places not in this plan").font(.headline)
                        ForEach(excludedPlaces.indices, id: \.self) { index in
                            Text(excludedPlaces[index]).font(.footnote)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("itineraryUnscheduled")
                }

                Text("Your step-by-step itinerary")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.leading, timelineIndent)
                    .padding(.top, 4)

                if let refreshRoute {
                    Button("Refresh driving estimates", systemImage: "arrow.clockwise", action: refreshRoute)
                        .font(.footnote)
                        .disabled(isSaving)
                }

                if proposal.stops.isEmpty {
                    ContentUnavailableView("No places in this itinerary", systemImage: "map",
                                           description: Text("Add a place and plan your trip again."))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                            timelineRow(index: index, stop: stop, stops: stops)
                        }
                    }
                }

                if allowsEditing {
                    Button("Add another place", action: addPlace)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(isSaving || (proposal.experiencePlan == nil && proposal.input.places.count >= 6))
                        .accessibilityIdentifier("itineraryAddPlace")
                }

                ItineraryMapView(proposal: proposal)
                if let seconds = proposal.returnTravelSeconds {
                    let destination = proposal.input.enginePreferences?.endPointName ?? "starting point"
                    let action = proposal.input.enginePreferences?.endPointName == nil ? "Return to" : "End at"
                    Label("\(action) \(destination) · \(Int(ceil(Double(seconds) / 60))) min · arrive by \(ItineraryFormatting.time(proposal.finishesAt, zone: proposal.input.timeZone, locale: .current))", systemImage: "arrow.uturn.backward")
                        .font(.footnote)
                }

                if proposal.synthetic {
                    Text(isDesignPreview ? "Design preview · sample itinerary from Sketch" : "Synthetic demonstration · trips last until the app closes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    if let retry {
                        Button("Try again", action: retry)
                            .disabled(isSaving)
                    }
                }
                if let startNow {
                    Button("Start your trip today", action: startNow)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .buttonStyle(.borderedProminent)
                        .tint(Color("ItineraryBlue"))
                        .buttonBorderShape(.capsule)
                        .padding(.top, 20)
                        .disabled(isSaving || !canSave || !proposal.feasible || stops.isEmpty)
                        .accessibilityIdentifier("itineraryStartNow")
                }
                Button(action: save) {
                    HStack {
                        if isSaving { ProgressView().tint(.white) }
                        Text(isSaving ? "Please wait…" : actionTitle)
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(ItinerarySaveButtonStyle(secondary: startNow != nil))
                .tint(Color("ItineraryBlue"))
                .buttonBorderShape(.capsule)
                .disabled(isSaving || !canSave || !proposal.feasible || stops.isEmpty)
                .padding(.top, startNow == nil ? 20 : 0)
                .accessibilityIdentifier("Save this trip")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color("TripCanvas"))
        .tint(Color("ItineraryAction"))
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("itineraryList")
    }

    private func timelineRow(index: Int, stop: ScheduledPlanningStop, stops: [ScheduledPlanningStop]) -> some View {
        let next = index + 1 < stops.count ? stops[index + 1] : nil
        let isExperience = proposal.experiencePlan != nil
        let place = proposal.input.places.first { $0.id == stop.id }
        var stopDetails = details[stop.id] ?? ItineraryStopDetails()
        let poi = place.flatMap { RecommendedPlace(place: $0).poiPresentation }
        if stopDetails.category == nil { stopDetails.category = poi?.label }
        let distance = next.flatMap { next in
            if let meters = next.roadDistanceMeters { return formattedDistance(meters) }
            return isExperience ? nil : details[next.id]?.distance
        }
        let reorder: (() -> NSItemProvider)? = move == nil ? nil : {
            draggedStop = stop.id
            return NSItemProvider(object: stop.id.uuidString as NSString)
        }
        let up: (() -> Void)? = index > 0 ? { move?(stop.id, proposal.stops[index - 1].id) } : nil
        let down: (() -> Void)? = index + 1 < proposal.stops.count ? { move?(stop.id, proposal.stops[index + 1].id) } : nil
        return ItineraryTimelineRow(stop: stop, number: index + 1, isLast: next == nil,
                                    nextStop: next, nextDistance: distance,
                                    mode: proposal.input.mode, zone: proposal.input.timeZone,
                                    details: stopDetails, isEditable: allowsEditing,
                                    weatherEvidence: proposal.evidence.filter { $0.kind == "weather" },
                                    orderingOnly: isExperience, symbol: poi?.symbol, edit: { edit(stop.id) },
                                    beginReorder: reorder, moveUp: up, moveDown: down)
            .contentShape(Rectangle())
            .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
                acceptDrop(providers, onto: stop.id)
            }
    }

    @ViewBuilder private func tripEdits(_ edit: @escaping (ItineraryEditRoute) -> Void) -> some View {
        Button("Change start") { edit(.startingPoint) }
        Button("Change end") { edit(.endPoint) }
        if proposal.experiencePlan == nil { Button("Change time") { edit(.tripTime) } }
    }

    private func acceptDrop(_ providers: [NSItemProvider], onto destination: UUID) -> Bool {
        guard let source = draggedStop, source != destination,
              let provider = providers.first, let move else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { value, _ in
            guard value as? String == source.uuidString else { return }
            DispatchQueue.main.async {
                draggedStop = nil
                move(source, destination)
            }
        }
        return true
    }

    private func formattedDistance(_ meters: Double) -> String {
        if meters < 1_000 { return "\(Int(meters.rounded())) m" }
        return "\((meters / 1_000).formatted(.number.precision(.fractionLength(1)))) km"
    }

    private func addPlace() { edit(nil) }
}

private struct ItinerarySaveButtonStyle: PrimitiveButtonStyle {
    let secondary: Bool

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if secondary {
            Button(configuration).buttonStyle(.plain).foregroundStyle(Color("ItineraryAction"))
        } else {
            Button(configuration).buttonStyle(.borderedProminent)
        }
    }
}

#if DEBUG
    #Preview("ITINERARY LIST · Light") {
        ItineraryDesignPreview()
            .preferredColorScheme(.light)
    }

    #Preview("ITINERARY LIST · Dark") {
        ItineraryDesignPreview()
            .preferredColorScheme(.dark)
    }
#endif
