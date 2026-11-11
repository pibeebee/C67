import SwiftUI
import C67Domain

struct TripHomeContentView: View {
    let presenter: PlanningPresenter
    var isHistory = false
    let mode: String
    let showAccount: () -> Void

    private var trips: [PersonalPlanningTrip] {
        presenter.trips.filter { ($0.status == .completed) == isHistory }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if presenter.isBusy && presenter.trips.isEmpty {
                    ProgressView("Loading trips…")
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                } else if let error = presenter.error {
                    ContentUnavailableView {
                        Label("Trips couldn’t be loaded", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                    } description: {
                        Text(error)
                    } actions: {
                        if presenter.privateAccessBlocked {
                            Button("Sign in", action: showAccount)
                        } else {
                            Button("Try again", action: reload)
                        }
                    }
                    .frame(minHeight: geometry.size.height)
                } else if trips.isEmpty {
                    if isHistory {
                        ContentUnavailableView("No trips yet", systemImage: "clock.arrow.circlepath",
                                               description: Text("Your completed trips will appear here."))
                            .frame(minHeight: geometry.size.height)
                    } else {
                        TripEmptyView()
                            .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    }
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(tripDays, id: \.self) { day in
                            Text(dayTitle(day))
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                            ForEach(trips.filter { Calendar.current.startOfDay(for: $0.input.startsAt) == day }) { trip in
                                NavigationLink(value: trip.id) { TripHomeRow(trip: trip) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(16)
                }
                if isHistory {
                    Text(mode.hasPrefix("Mock") ? "Synthetic demonstration · trips last until the app closes." : mode)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .refreshable { await presenter.load() }
        }
    }

    private var tripDays: [Date] {
        Array(Set(trips.map { Calendar.current.startOfDay(for: $0.input.startsAt) }))
            .sorted { isHistory ? $0 > $1 : $0 < $1 }
    }

    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return String(localized: "Today") }
        if Calendar.current.isDateInTomorrow(day) { return String(localized: "Tomorrow") }
        return day.formatted(date: .abbreviated, time: .omitted)
    }

    private func reload() {
        Task { await presenter.load() }
    }
}
