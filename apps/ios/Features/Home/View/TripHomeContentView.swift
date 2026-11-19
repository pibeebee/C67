import SwiftUI
import C67Domain

struct TripHomeContentView: View {
    let presenter: PlanningPresenter
    var isHistory = false
    let mode: String
    let showAccount: () -> Void
    var planTrip: () -> Void = {}
    var resumeDraft: (PlanningJob) -> Void = { _ in }

    private var trips: [PersonalPlanningTrip] {
        presenter.trips.filter { ($0.status == .completed) == isHistory }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if presenter.isBusy && presenter.trips.isEmpty && (isHistory || presenter.firstItineraryJob == nil) {
                    ProgressView("Loading trips…")
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                } else if let error = presenter.tripListError, presenter.trips.isEmpty, presenter.firstItineraryJob == nil {
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
                } else if trips.isEmpty && presenter.tripListError == nil && (isHistory || presenter.firstItineraryJob == nil) {
                    if isHistory {
                        ContentUnavailableView("No trips yet", systemImage: "clock.arrow.circlepath",
                                               description: Text("Your completed trips will appear here."))
                            .frame(minHeight: geometry.size.height)
                    } else {
                        TripEmptyView(planTrip: planTrip)
                            .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    }
                } else {
                    LazyVStack(spacing: 12) {
                        if let error = presenter.tripListError {
                            RecoveryNotice(title: "Couldn’t refresh trips", message: error,
                                           primary: presenter.privateAccessBlocked
                                               ? .init(title: "Sign in", perform: showAccount)
                                               : .init(title: "Try again", perform: reload))
                        }
                        if !isHistory, let draft = presenter.firstItineraryJob {
                            Text("Drafts").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                            Button { resumeDraft(draft) } label: { TripDraftRow(job: draft, statusUnconfirmed: presenter.creationIssue?.recovery == .checkStatus) }
                                .buttonStyle(.plain)
                                .disabled(presenter.isBusy)
                                .accessibilityIdentifier("resumeItineraryDraft")
                        }
                        ForEach(tripDays, id: \.self) { day in
                            Text(dayTitle(day))
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                            ForEach(trips.filter { Calendar.current.startOfDay(for: $0.plan.departureAt ?? $0.plan.input.startsAt) == day }) { trip in
                                NavigationLink(value: trip.id) { TripHomeRow(trip: trip) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(16)
                }
                #if DEBUG
                if isHistory {
                    Text(mode.hasPrefix("Mock") ? "Synthetic demonstration · trips last until the app closes." : mode)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                #endif
            }
            .refreshable { await presenter.load(waitForFirstItinerary: false) }
        }
    }

    private var tripDays: [Date] {
        Array(Set(trips.map { Calendar.current.startOfDay(for: $0.plan.departureAt ?? $0.plan.input.startsAt) }))
            .sorted { isHistory ? $0 > $1 : $0 < $1 }
    }

    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return String(localized: "Today") }
        if Calendar.current.isDateInTomorrow(day) { return String(localized: "Tomorrow") }
        return day.formatted(date: .abbreviated, time: .omitted)
    }

    private func reload() {
        Task { await presenter.load(resumesJobs: false) }
    }
}

struct TripDraftRow: View {
    let job: PlanningJob
    var statusUnconfirmed = false

    private var status: LocalizedStringKey {
        switch job.status {
        case .queued, .running: statusUnconfirmed ? "Check request status" : "Continue planning"
        case .succeeded: "Ready to review"
        case .failed: "Needs attention"
        case .unknown: "Continue itinerary draft"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "map")
                .font(.largeTitle).foregroundStyle(AppColor.accent)
                .frame(width: 96, height: 96).background(AppColor.tertiaryFill, in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(job.input.title).font(.headline)
                Text(status).font(.subheadline).foregroundStyle(.secondary)
                Text("\(job.input.places.count) places").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").foregroundStyle(AppColor.accent).accessibilityHidden(true)
        }
        .foregroundStyle(.primary).padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surface, in: .rect(cornerRadius: 16))
    }
}
