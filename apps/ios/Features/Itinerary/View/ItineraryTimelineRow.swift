import SwiftUI
import C67Domain

struct ItineraryTimelineRow: View {
    let markerSize: CGFloat
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
    let cardHeightChanged: (CGFloat) -> Void

    private var railColor: Color { isLifted ? AppColor.accent : .secondary }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 8) {
                Text(number, format: .number)
                    .font(.caption)
                    .foregroundStyle(railColor)
                    .frame(width: markerSize, height: markerSize)
                    .overlay(Circle().stroke(railColor, lineWidth: 0.7))
                    .padding(.top, 22)
                    .accessibilityLabel("Stop \(number)")
                if !isLast {
                    Spacer(minLength: 0)
                    connector(height: 20, lineWidth: 1)
                        .padding(.vertical, 4)
                        .opacity(isLifted ? 0 : 1)
                }
            }
            .overlay(alignment: .top) {
                if isLifted {
                    connector(height: 36, lineWidth: 1.5)
                        .padding(.top, 22 + markerSize + 5)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                ItineraryStopCard(stop: stop, zone: zone, details: details, isEditable: isEditable, weatherEvidence: weatherEvidence, edit: edit,
                                  showsEstimatedTimes: orderingOnly, symbol: symbol,
                                  reorderChanged: reorderChanged, reorderEnded: reorderEnded, reorderCancelled: reorderCancelled,
                                  moveUp: moveUp, moveDown: moveDown)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeightChanged($0) }
                    .shadow(color: .black.opacity(isLifted ? 0.25 : 0), radius: 10, y: 5)
                if let nextStop {
                    Label {
                        if orderingOnly {
                            Text(ItineraryFormatting.drivingEstimate(nextStop, showsApproximation: false) + (nextDistance.map { " · " + $0 } ?? ""))
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

    private func connector(height: CGFloat, lineWidth: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 1, y: 0))
            path.addLine(to: CGPoint(x: 1, y: height))
        }
        .stroke(railColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [2, 4]))
        .frame(width: 2, height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
