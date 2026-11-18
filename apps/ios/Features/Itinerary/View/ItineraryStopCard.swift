import SwiftUI
import C67Domain

struct ItineraryStopCard: View {
    let stop: ScheduledPlanningStop
    let zone: String
    var details: ItineraryStopDetails?
    var isEditable = true
    let weatherEvidence: [PlanningEvidence]
    let edit: () -> Void
    var showsEstimatedTimes = false
    var symbol: String?
    var reorderChanged: ((DragGesture.Value) -> Void)?
    var reorderEnded: ((DragGesture.Value) -> Void)?
    var reorderCancelled: (() -> Void)?
    var moveUp: (() -> Void)? = nil
    var moveDown: (() -> Void)? = nil
    @Environment(\.locale) private var locale
    @GestureState private var isDragging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Group {
                    if let asset = details?.photoAsset {
                        Image(asset).resizable().scaledToFill()
                    } else {
                        Image(systemName: symbol ?? "mappin.and.ellipse")
                            .font(.title2)
                            .foregroundStyle(.tint)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.tint.opacity(0.1))
                    }
                }
                .frame(width: showsEstimatedTimes ? 72 : 48, height: showsEstimatedTimes ? 72 : 48)
                .clipShape(.rect(cornerRadius: 8))
                .accessibilityHidden(true)

                if isEditable {
                    Button(action: edit) {
                        visitSummary
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showsEstimatedTimes ? "Edit visit length for \(stop.name)" : "Edit visit time for \(stop.name)")
                    .accessibilityValue(visitRange)
                    .accessibilityIdentifier("itineraryEdit-\(stop.id)")
                } else {
                    visitSummary.accessibilityElement(children: .combine)
                }
                if let reorderChanged {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .updating($isDragging) { _, isActive, _ in isActive = true }
                            .onChanged(reorderChanged)
                            .onEnded { reorderEnded?($0) })
                        .onChange(of: isDragging) { _, active in
                            if !active {
                                // Gesture state also resets when the system interrupts a drag.
                                Task { @MainActor in reorderCancelled?() }
                            }
                        }
                        .accessibilityLabel("Reorder \(stop.name)")
                        .accessibilityIdentifier("itineraryReorder-\(stop.id)")
                        .accessibilityHint("Drag up or down to change the visit order.")
                        .accessibilityActions {
                            if let moveUp { Button("Move up", action: moveUp) }
                            if let moveDown { Button("Move down", action: moveDown) }
                        }
                }
            }
            .padding(.leading, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            if !showsEstimatedTimes {
                Divider()
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(details?.weatherAdvice ?? String(localized: "No stop-specific forecast was supplied with this plan."))
                        ForEach(stop.warnings, id: \.self) { Text($0) }
                        ForEach(weatherEvidence) { evidence in Text(evidence.summary) }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                } label: {
                    Label(details?.weatherAdvice ?? String(localized: "Weather context"), systemImage: details?.weatherSymbol ?? "cloud.sun")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                }
                .padding(12)
            }
        }
        .background(Color("ItinerarySurface"), in: .rect(cornerRadius: 14))
    }

    private var visitSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(stop.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
            Text(details?.category ?? String(localized: "Selected place"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Label(visitRange, systemImage: isEditable ? "pencil" : "clock")
                .font(.footnote)
                .foregroundStyle(Color("ItineraryAction"))
                .accessibilityIdentifier(showsEstimatedTimes ? "estimatedVisitWindow" : "visitWindow")
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(.rect)
    }

    private var visitRange: String {
        let start = ItineraryFormatting.time(stop.visitStartsAt ?? stop.arrivalAt, zone: zone, locale: locale)
        let end = ItineraryFormatting.time(stop.departureAt, zone: zone, locale: locale)
        return showsEstimatedTimes ? "≈ \(start)–\(end)" : "\(start)–\(end)"
    }
}
