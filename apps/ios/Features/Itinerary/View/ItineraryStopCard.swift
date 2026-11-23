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
            HStack(alignment: .center, spacing: 12) {
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
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 10))
                .accessibilityHidden(true)

                placeSummary
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let reorderChanged {
                    Image(systemName: "chevron.up.chevron.down")
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
            .padding(.trailing, 4)
            .padding(.vertical, 10)

            Divider().padding(.horizontal, 12)
            if isEditable {
                Button(action: edit) { visitTimeRow }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showsEstimatedTimes ? "Edit visit length for \(stop.name)" : "Edit visit time for \(stop.name)")
                    .accessibilityValue(visitRange)
                    .accessibilityIdentifier("itineraryEdit-\(stop.id)")
            } else {
                visitTimeRow
            }

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
        .background(AppColor.surface, in: .rect(cornerRadius: 16))
    }

    private var placeSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stop.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
            Text(details?.category ?? String(localized: "Selected place"))
                .font(.footnote)
                .foregroundStyle(.primary.opacity(0.72))
        }
    }

    private var visitTimeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .accessibilityHidden(true)
            Text(visitRange)
                .monospacedDigit()
                .accessibilityIdentifier(showsEstimatedTimes ? "estimatedVisitWindow" : "visitWindow")
            Spacer(minLength: 8)
            if isEditable {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AppColor.accent)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 14)
        .contentShape(.rect)
    }

    private var visitRange: String {
        let start = ItineraryFormatting.time(stop.visitStartsAt ?? stop.arrivalAt, zone: zone, locale: locale)
        let end = ItineraryFormatting.time(stop.departureAt, zone: zone, locale: locale)
        return "\(start)–\(end)"
    }
}
