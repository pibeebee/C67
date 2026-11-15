import SwiftUI
import C67Domain

struct ItineraryDepartureCard: View {
    let proposal: PlanProposal
    var weatherAdvice: String?
    var isDesignPreview = false
    var editDeparture: (() -> Void)?
    var editEndpoints: ((ItineraryEditRoute) -> Void)?
    @Environment(\.locale) private var locale

    private var departureContext: String {
        if isDesignPreview { return "Set to beat the morning rush." }
        if proposal.firstItinerary == true { return proposal.explanation }
        if proposal.input.enginePreferences?.flexibleDeparture == true { return "Chosen within your available departure window." }
        return "Based on your selected departure time."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let departure = proposal.estimatedExperienceDeparture {
                HStack {
                    Text("SUGGESTED DEPARTURE").font(.caption.italic())
                    Spacer(minLength: 8)
                    if editDeparture != nil || editEndpoints != nil {
                        Menu {
                            if let editDeparture { Button("Departure date and time", action: editDeparture) }
                            if let editEndpoints {
                                Button("Starting point") { editEndpoints(.startingPoint) }
                                Button("End point") { editEndpoints(.endPoint) }
                            }
                        } label: {
                            Text("Edit").font(.footnote.weight(.medium))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .foregroundStyle(Color.white)
                                .background(.white.opacity(0.24), in: .capsule)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityIdentifier("itineraryDepartureEdit")
                    }
                }
                Text(ItineraryFormatting.date(departure, zone: proposal.input.timeZone, locale: locale))
                    .font(.subheadline.weight(.semibold))
                Text(ItineraryFormatting.time(departure, zone: proposal.input.timeZone, locale: locale))
                    .font(.largeTitle.bold())
                if let weather = experienceWeather(at: departure) {
                    Label(weather, systemImage: "cloud.sun").font(.footnote).padding(.top, 6)
                }
                Text(proposal.hasExperienceTravelFallback ? "Driving estimates include defaults" : "Driving times are estimates")
                    .font(.caption).padding(.top, 4)
            } else {
                ViewThatFits(in: .horizontal) {
                    Label("SUGGESTED DEPARTURE", systemImage: "clock")
                        .fixedSize()
                    Text("Suggested departure")
                }
                .font(.subheadline)
                Text(ItineraryFormatting.date(proposal.departureAt ?? proposal.input.startsAt, zone: proposal.input.timeZone, locale: locale))
                    .font(.largeTitle.bold())
                Text(ItineraryFormatting.time(proposal.departureAt ?? proposal.input.startsAt, zone: proposal.input.timeZone, locale: locale))
                    .font(.title.bold())
                Text(departureContext).font(.subheadline)
                if let weatherAdvice {
                    Label(weatherAdvice, systemImage: "sun.max")
                        .font(.subheadline)
                        .padding(.top, 8)
                } else if proposal.input.enginePreferences?.automaticFirstPlan == true {
                    Label("Estimated finish \(ItineraryFormatting.time(proposal.finishesAt, zone: proposal.input.timeZone, locale: locale))",
                          systemImage: "flag.checkered")
                        .font(.subheadline)
                        .padding(.top, 8)
                } else {
                    Label("Finish by \(ItineraryFormatting.time(proposal.input.finishBy, zone: proposal.input.timeZone, locale: locale))",
                          systemImage: "flag.checkered")
                        .font(.subheadline)
                        .padding(.top, 8)
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            LinearGradient(colors: [Color("ItineraryBlue"), Color("ItineraryBlueEnd")],
                           startPoint: .top, endPoint: .bottom)
        }
        .clipShape(.rect(cornerRadius: 26))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("itineraryDeparture")
    }

    private func experienceWeather(at departure: Date) -> String? {
        guard let first = proposal.stops.first,
              let hour = proposal.experiencePlan?.weatherSources.first(where: { $0.placeID == first.id })?
                  .hourlySamples.first(where: { $0.start <= departure && departure < $0.end }) else { return nil }
        return String(localized: "Rain chance near first stop · \(hour.precipitationChance.formatted(.percent.precision(.fractionLength(0))))")
    }

}
