import SwiftUI
import C67Domain

struct PocketVisitAvailabilityView: View {
    @Bindable var presenter: TripCreationPresenter
    let proceed: () -> Void
    @State private var visitDate: Date
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: presenter.planning.timeZone) ?? .current
        return value
    }
    init(presenter: TripCreationPresenter, proceed: @escaping () -> Void) {
        self.presenter = presenter
        self.proceed = proceed
        _visitDate = State(initialValue: presenter.planning.startsAt)
    }
    var body: some View {
        let calendar = calendar
        Form {
            Section {
                Text("Review visit availability")
                    .font(.headline)
                DatePicker("Visit date", selection: $visitDate, in: PartialRangeFrom(calendar.startOfDay(for: .now)), displayedComponents: .date)
                    .environment(\.calendar, calendar)
                Text("If you checked that you can visit, confirm the available hours for this trip date. Your confirmation applies to this trip only.")
                    .font(.footnote)
            }
            ForEach(presenter.availabilityPlaces) { item in
                let day = calendar.startOfDay(for: visitDate)
                let confirmation = item.place.visitConfirmation.flatMap {
                    calendar.isDate($0.opensAt, inSameDayAs: day) ? $0 : nil
                }
                PocketVisitAvailabilityRow(name: item.place.name, confirmation: confirmation,
                                           opens: confirmation?.opensAt ?? day.addingTimeInterval(9 * 3600),
                                           closes: confirmation?.closesAt ?? day.addingTimeInterval(17 * 3600),
                                           confirm: { presenter.confirmVisit(item.id, opens: $0, closes: $1, publicAccess: true) },
                                           invalidate: { presenter.clearVisitConfirmation(item.id) })
                    .id(day)
            }
            Section {
                Button("Build itinerary", action: proceed)
                    .disabled(!presenter.usesV41 && !presenter.availabilityPlaces.contains { row in
                        row.place.visitConfirmation
                            .map { calendar.isDate($0.opensAt, inSameDayAs: visitDate) } == true
                    })
                    .accessibilityIdentifier("pocketBuildItinerary")
            }
        }
        .environment(\.timeZone, calendar.timeZone)
        .onChange(of: visitDate) { _, date in if presenter.usesV41 { presenter.changeTripDate(date) } }
        .navigationTitle("Visit availability")
    }
}

private struct PocketVisitAvailabilityRow: View {
    let name: String
    let confirmation: PlanningVisitConfirmation?
    @State var opens: Date
    @State var closes: Date
    let confirm: (Date, Date) -> Void
    let invalidate: () -> Void
    @State private var checked = false

    var body: some View {
        Section(name) {
            if confirmation != nil {
                Label("Confirmed by you for this trip", systemImage: "person.crop.circle.badge.checkmark")
            } else {
                Text("Confirm the opening hours and access for your visit.").foregroundStyle(.secondary)
            }
            DatePicker("Available from", selection: $opens, displayedComponents: .hourAndMinute)
            DatePicker("Available until", selection: $closes, displayedComponents: .hourAndMinute)
            Toggle("I checked access, any reservation, and these hours", isOn: $checked)
                .accessibilityIdentifier("pocketAccess")
            Button("Confirm availability") { confirm(opens, closes) }
                .disabled(!checked || closes <= opens)
                .accessibilityIdentifier("pocketConfirm")
        }
        .onChange(of: opens) { _, _ in invalidate() }
        .onChange(of: closes) { _, _ in invalidate() }
        .onChange(of: checked) { _, value in if !value { invalidate() } }
    }
}
