import SwiftUI
import C67Domain

struct TripHomeRow: View {
    let trip: PersonalPlanningTrip
    var previewImages: [String] = []

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if previewImages.isEmpty {
                    Image(systemName: "map")
                        .font(.largeTitle).foregroundStyle(AppColor.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppColor.tertiaryFill)
                } else {
                    VStack(spacing: 2) {
                        HStack(spacing: 2) {
                            ForEach(Array(previewImages.prefix(2).enumerated()), id: \.offset) { _, name in
                                Image(name).resizable().scaledToFill().frame(width: 47, height: 47).clipped()
                            }
                        }
                        if let last = previewImages.last {
                            Image(last).resizable().scaledToFill().frame(width: 96, height: 47).clipped()
                        }
                    }
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(.rect(cornerRadius: 10))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(trip.title).font(.headline)
                Text(trip.input.startsAt, format: .dateTime.day().month(.abbreviated).year().hour().minute().timeZone(.omitted))
                    .font(.caption).foregroundStyle(.secondary)
                Text(trip.status == .completed ? "All visits completed" : "\(max(0, trip.plan.stops.count - trip.completedStopIDs.count)) stops to go")
                    .font(.caption).foregroundStyle(.secondary)
                if trip.synthetic {
                    Text("Synthetic · memory only").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .environment(\.timeZone, TimeZone(identifier: trip.input.timeZone) ?? .current)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").foregroundStyle(AppColor.accent).accessibilityHidden(true)
        }
        .foregroundStyle(.primary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surface, in: .rect(cornerRadius: 16))
    }
}
