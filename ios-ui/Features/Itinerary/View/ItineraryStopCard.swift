import SwiftUI
import C67Domain

struct ItineraryStopCard: View {
    let stop: ScheduledPlanningStop
    let zone: String
    var details: ItineraryStopDetails?
    var isEditable = true
    let weatherEvidence: [PlanningEvidence]
    let edit: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Group {
                    if let asset = details?.photoAsset {
                        Image(asset).resizable().scaledToFill()
                    } else {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.title2)
                            .foregroundStyle(.tint)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.tint.opacity(0.1))
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(.rect(cornerRadius: 8))
                .accessibilityHidden(true)

                if isEditable {
                    Button(action: edit) {
                        visitSummary
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isEditable ? "Edit visit time for \(stop.name)" : "Visit time for \(stop.name)")
                    .accessibilityValue("\(ItineraryFormatting.time(stop.arrivalAt, zone: zone, locale: locale))–\(ItineraryFormatting.time(stop.departureAt, zone: zone, locale: locale))")
                    .accessibilityIdentifier("itineraryEdit-\(stop.id)")
                } else {
                    visitSummary.accessibilityElement(children: .combine)
                }
                if isEditable {
                    Button("Edit \(stop.name)", systemImage: "slider.horizontal.3", action: edit)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            .padding(.leading, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    if let advice = details?.weatherAdvice {
                        Text(advice)
                    } else {
                        Text("No stop-specific forecast was supplied with this plan.")
                    }
                    ForEach(stop.warnings, id: \.self) { Text($0) }
                    ForEach(weatherEvidence) { evidence in
                        Text(evidence.summary)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
            } label: {
                Label {
                    Text(details?.weatherAdvice ?? String(localized: "Weather context"))
                } icon: {
                    Image(systemName: details?.weatherSymbol ?? "cloud.sun")
                        .foregroundStyle(Color("ItineraryAction"))
                }
                .font(.footnote)
                .foregroundStyle(Color.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
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
            Label {
                Text("\(ItineraryFormatting.time(stop.arrivalAt, zone: zone, locale: locale))–\(ItineraryFormatting.time(stop.departureAt, zone: zone, locale: locale))")
            } icon: {
                Image(systemName: isEditable ? "pencil" : "clock")
            }
            .font(.footnote)
            .foregroundStyle(Color("ItineraryAction"))
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(.rect)
    }

}
