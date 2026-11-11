import SwiftUI
import C67Domain

struct ItineraryDepartureCard: View {
    let proposal: PlanProposal
    var weatherAdvice: String?
    var isDesignPreview = false
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                Label("SUGGESTED DEPARTURE", systemImage: "clock")
                    .fixedSize()
                Text("Suggested departure")
            }
            .font(.subheadline)
            Text(ItineraryFormatting.date(proposal.input.startsAt, zone: proposal.input.timeZone, locale: locale))
                .font(.largeTitle.bold())
            Text(ItineraryFormatting.time(proposal.input.startsAt, zone: proposal.input.timeZone, locale: locale))
                .font(.title.bold())
            Text(isDesignPreview ? "Set to beat the morning rush." : "Based on your selected departure time.")
                .font(.subheadline)
            if let weatherAdvice {
                Label(weatherAdvice, systemImage: "sun.max")
                    .font(.subheadline)
                    .padding(.top, 8)
            } else {
                Label("Finish by \(ItineraryFormatting.time(proposal.input.finishBy, zone: proposal.input.timeZone, locale: locale))",
                      systemImage: "flag.checkered")
                    .font(.subheadline)
                    .padding(.top, 8)
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
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("itineraryDeparture")
    }
}
