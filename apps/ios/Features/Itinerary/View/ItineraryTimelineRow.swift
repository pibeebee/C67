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
    var orderingOnly = false
    var symbol: String?
    let edit: () -> Void
    var reorderChanged: ((DragGesture.Value) -> Void)?
    var reorderEnded: ((DragGesture.Value) -> Void)?
    var reorderCancelled: (() -> Void)?
    var isLifted = false
    var isReordering = false
    var moveUp: (() -> Void)? = nil
    var moveDown: (() -> Void)? = nil

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
                ItineraryStopCard(stop: stop, zone: zone, details: details, isEditable: isEditable, weatherEvidence: weatherEvidence, edit: edit,
                                  showsEstimatedTimes: orderingOnly, symbol: symbol,
                                  reorderChanged: reorderChanged, reorderEnded: reorderEnded, reorderCancelled: reorderCancelled,
                                  moveUp: moveUp, moveDown: moveDown)
                    .shadow(color: .black.opacity(isLifted ? 0.25 : 0), radius: 10, y: 5)
                if let nextStop {
                    Label {
                        if orderingOnly {
                            Text(ItineraryFormatting.drivingEstimate(nextStop) + (nextDistance.map { " · " + $0 } ?? ""))
                        } else {
                            let minutes = String(localized: "\(nextStop.travelSeconds / 60) min")
                            Text(minutes + (nextDistance.map { " · " + $0 } ?? ""))
                        }
                    } icon: {
                        Image(systemName: mode == .automobile ? "car" : "figure.walk")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .opacity(isReordering ? 0 : 1)
                    .accessibilityHidden(isReordering)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
