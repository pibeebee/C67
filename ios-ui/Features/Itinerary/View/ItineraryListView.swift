import SwiftUI
import UniformTypeIdentifiers
import C67Domain

struct ItineraryListView: View {
    @ScaledMetric(relativeTo: .caption) private var timelineIndent = 34
    let proposal: PlanProposal
    var details: [UUID: ItineraryStopDetails] = [:]
    var departureWeather: String?
    var isDesignPreview = false
    var isSaving = false
    var error: String?
    var canSave = true
    var heading: String?
    var actionTitle = "Save Itinerary"
    var allowsEditing = true
    var navigationTitle = "Itinerary"
    var retry: (() -> Void)?
    let edit: (UUID?) -> Void
    let save: () -> Void
    var move: (@MainActor @Sendable (UUID, UUID) -> Void)? = nil
    @State private var draggedStop: UUID?
    @State private var reorderDiagnostic = "idle"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(heading ?? (proposal.feasible ? "All set! Here’s your itinerary" : "Your choices need adjustment"))
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 4)

                ItineraryDepartureCard(proposal: proposal, weatherAdvice: departureWeather, isDesignPreview: isDesignPreview)

                Text("Your step-by-step itinerary")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.leading, timelineIndent)
                    .padding(.top, 4)

                if proposal.stops.isEmpty {
                    ContentUnavailableView("No places in this itinerary", systemImage: "map",
                                           description: Text("Add a place and plan your trip again."))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(proposal.stops.enumerated()), id: \.element.id) { index, stop in
                            let next = index + 1 < proposal.stops.count ? proposal.stops[index + 1] : nil
                            ItineraryTimelineRow(stop: stop, number: index + 1, isLast: next == nil,
                                                 nextStop: next, nextDistance: next.flatMap { details[$0.id]?.distance },
                                                 mode: proposal.input.mode, zone: proposal.input.timeZone,
                                                 details: details[stop.id], isEditable: allowsEditing, weatherEvidence: proposal.evidence.filter { $0.kind == "weather" },
                                                 edit: { edit(stop.id) },
                                                 beginReorder: move == nil ? nil : { reorderDiagnostic = "drag"; draggedStop = stop.id; return NSItemProvider(object: stop.id.uuidString as NSString) },
                                                 moveUp: index > 0 ? { move?(stop.id, proposal.stops[index - 1].id) } : nil,
                                                 moveDown: index + 1 < proposal.stops.count ? { move?(stop.id, proposal.stops[index + 1].id) } : nil)
                                .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
                                    acceptDrop(providers, onto: stop.id)
                                }
                        }
                    }
                }

                if allowsEditing {
                    Button("Add another place", action: addPlace)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(isSaving || proposal.input.places.count >= 6)
                        .accessibilityIdentifier("itineraryAddPlace")
                }

                ItineraryMapView(proposal: proposal)

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
                Button(action: save) {
                    HStack {
                        if isSaving { ProgressView().tint(.white) }
                        Text(isSaving ? "Please wait…" : actionTitle)
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("ItineraryBlue"))
                .buttonBorderShape(.capsule)
                .disabled(isSaving || !canSave || !proposal.feasible || proposal.stops.isEmpty)
                .padding(.top, 20)
                .accessibilityIdentifier("Save this trip")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottomLeading) {
            Text("Reorder diagnostic \(reorderDiagnostic)").accessibilityIdentifier("reorderDiagnostic")
        }
        .background(Color("TripCanvas"))
        .tint(Color("ItineraryAction"))
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("itineraryList")
    }

    private func acceptDrop(_ providers: [NSItemProvider], onto destination: UUID) -> Bool {
        reorderDiagnostic = "drop"
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

    private func addPlace() { edit(nil) }
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
