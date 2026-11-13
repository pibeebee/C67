import SwiftUI
import MapKit
import C67Domain

struct ItineraryMapView: View {
    let proposal: PlanProposal

    var body: some View {
        VStack(spacing: 0) {
            Map(interactionModes: [.pan, .zoom]) {
                ForEach(Array(proposal.stops.enumerated()), id: \.element.id) { index, stop in
                    Annotation(stop.name, coordinate: .init(latitude: stop.location.latitude, longitude: stop.location.longitude)) {
                        Text(index + 1, format: .number)
                            .font(.footnote.bold())
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color("ItineraryBlue"), in: .circle)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .accessibilityLabel("Stop \(index + 1): \(stop.name)")
                    }
                }
            }
            .frame(height: 200)
            .accessibilityLabel("Itinerary places on the map")
            ForEach(proposal.evidence.filter { $0.kind == "weather" && $0.attributionLogoURL != nil }) { evidence in
                if let url = evidence.url, let logo = evidence.attributionLogoURL, url.scheme == "https", logo.host == "weatherkit.apple.com" {
                    Link(destination: url) {
                        AsyncImage(url: logo) { image in image.resizable().scaledToFit() } placeholder: { Text("Apple Weather") }
                            .frame(width: 120, height: 28)
                            .padding(6).background(.white)
                    }
                    .accessibilityLabel("Apple Weather and data sources")
                }
            }

            DisclosureGroup("Behind the scenes of your plan") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(proposal.explanation)
                    ForEach(proposal.warnings, id: \.self) { Text($0) }
                    ForEach(proposal.evidence) { evidence in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(evidence.label).fontWeight(.semibold)
                            Text(evidence.summary)
                            Text("Checked \(evidence.checkedAt.formatted())")
                                .foregroundStyle(.secondary)
                            if let url = evidence.url, url.scheme == "https" {
                                Link("Open source", destination: url)
                            }
                            if let logo = evidence.attributionLogoURL,
                               logo.scheme == "https", logo.host == "weatherkit.apple.com" {
                                AsyncImage(url: logo) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: { Text("Apple Weather") }
                                    .frame(width: 120, height: 28)
                                    .padding(6)
                                    .background(.white)
                                    .accessibilityLabel("Apple Weather")
                            }
                        }
                    }
                }
                .font(.footnote)
                .padding(.vertical, 8)
            }
            .font(.footnote)
            .foregroundStyle(.primary)
            .padding(12)
        }
        .background(Color("ItinerarySurface"))
        .clipShape(.rect(cornerRadius: 14))
    }
}
