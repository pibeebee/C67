import SwiftUI
import C67Domain

struct ItineraryTimelineRow: View {
    @ScaledMetric(relativeTo: .caption) private var markerSize = 24
    let stop: ScheduledPlanningStop
    let number: Int
    let isLast: Bool
    let nextStop: ScheduledPlanningStop?
    let nextDistance: String?
    let mode: PlanningMode
    let zone: String
    let details: ItineraryStopDetails?
    var isEditable = true
    let weatherEvidence: [PlanningEvidence]
    let edit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 8) {
                Text(number, format: .number)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: markerSize, height: markerSize)
                    .overlay(Circle().stroke(.secondary, lineWidth: 0.7))
                    .padding(.top, 22)
                    .accessibilityLabel("Stop \(number)")
                if !isLast {
                    Spacer(minLength: 0)
                    Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: 0, y: 20))
                    }
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .frame(width: 1, height: 20)
                    .padding(.vertical, 4)
                    .accessibilityHidden(true)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                ItineraryStopCard(stop: stop, zone: zone, details: details, isEditable: isEditable, weatherEvidence: weatherEvidence, edit: edit)
                if let nextStop {
                    Label {
                        Text("\(nextStop.travelSeconds / 60) min\(nextDistance.map { " · " + $0 } ?? "")")
                    } icon: {
                        Image(systemName: mode == .automobile ? "car" : "figure.walk")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
