import SwiftUI
import C67Domain

struct ItineraryDepartureCard: View {
    let proposal: PlanProposal
    var weatherAdvice: String?
    var isDesignPreview = false
    var editDeparture: (() -> Void)?
    var editEndpoints: ((ItineraryEditRoute) -> Void)?
    @Environment(\.locale) private var locale
    @State private var weatherRetry = 0
    @State private var departureForecast = DepartureWeatherLoader()

    private var departureContext: String {
        if isDesignPreview { return "Set to beat the morning rush." }
        if proposal.firstItinerary == true { return proposal.explanation }
        if proposal.input.enginePreferences?.flexibleDeparture == true { return "Chosen within your available departure window." }
        return "Based on your selected departure time."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            departureCard
            if let forecast = departureForecast.forecast, proposal.estimatedExperienceDeparture != nil,
               !proposal.synthetic, !isDesignPreview {
                Link(destination: forecast.sourceURL) {
                    if let mark = forecast.markURL {
                        AsyncImage(url: mark) { image in
                            image.resizable().scaledToFit()
                        } placeholder: { Text(forecast.source).foregroundStyle(.black) }
                            .frame(width: 90, height: 22)
                            .padding(4)
                            .background(.white, in: .rect(cornerRadius: 4))
                    } else {
                        Text(forecast.source).underline()
                    }
                }
                .font(.footnote)
                .frame(minHeight: 44)
                .accessibilityLabel("\(forecast.source) data sources")
            }
        }
        .task(id: forecastIdentity) {
            guard !isDesignPreview, !proposal.synthetic, let departure = proposal.estimatedExperienceDeparture else { departureForecast.clear(); return }
            await departureForecast.load(origin: proposal.input.origin, departure: departure)
        }
    }

    private var departureCard: some View {
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
                if let originalDate = proposal.rescheduledFromDate {
                    let date = ItineraryFormatting.date(originalDate, zone: proposal.input.timeZone, locale: locale)
                    Text("The trip didn’t fit on \(date). Travelant found a schedule for this date instead.")
                        .font(.footnote)
                }
                departureWeather
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

    private var forecastIdentity: String {
        "\(proposal.input.origin.latitude),\(proposal.input.origin.longitude),\(proposal.estimatedExperienceDeparture?.timeIntervalSince1970 ?? 0),\(proposal.synthetic),\(isDesignPreview),\(weatherRetry)"
    }

    @ViewBuilder private var departureWeather: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isDesignPreview, let weatherAdvice {
                Label(weatherAdvice, systemImage: "sun.max")
            } else if let forecast = departureForecast.forecast {
                Label("\(forecast.temperature.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0))))) · \(forecast.condition)", systemImage: forecast.symbol)
            } else if departureForecast.isLoading {
                Text("Checking departure weather…")
            } else {
                Text("Weather unavailable for this time")
                if !proposal.synthetic, !isDesignPreview, departureForecast.failure == .temporarilyUnavailable {
                    Button("Try weather again") { weatherRetry += 1 }
                }
            }
        }
        .font(.footnote).padding(.top, 6)
        .accessibilityIdentifier("itineraryDepartureWeather")
    }
}
