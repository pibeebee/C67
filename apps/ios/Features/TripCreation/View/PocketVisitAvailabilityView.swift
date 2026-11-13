import SwiftUI
import C67Domain

struct PocketVisitAvailabilityView: View {
    @Bindable var presenter: TripCreationPresenter
    let proceed: () -> Void
    var body: some View {
        Form {
            Section {
                Text("Review visit availability")
                    .font(.headline)
                Text("Unknown opening hours or access are not treated as verified. If you checked them yourself, confirm an available window for this trip date. This stays a personal confirmation and does not update public venue facts.")
                    .font(.footnote)
            }
            ForEach(presenter.selected) { item in
                PocketVisitAvailabilityRow(place: item.place, startsAt: presenter.planning.startsAt, finishBy: presenter.planning.finishBy,
                                           confirm: { presenter.confirmVisit(item.id, opens: $0, closes: $1, publicAccess: $2) },
                                           invalidate: { presenter.clearVisitConfirmation(item.id) },
                                           setTiming: { presenter.setVisitTiming(item.id, date: $0, timing: $1) })
            }
            PocketTripOptionsView(presenter: presenter)
            Section {
                Button("Build itinerary", action: proceed)
                    .disabled(presenter.missingVisitAvailability || presenter.selected.isEmpty)
                    .accessibilityIdentifier("pocketBuildItinerary")
            }
        }
        .environment(\.timeZone, TimeZone(identifier: "Asia/Jakarta")!)
        .navigationTitle("Visit availability")
    }
}

private struct PocketVisitAvailabilityRow: View {
    let place: PlanningPlace
    let startsAt: Date
    let finishBy: Date
    let confirm: (Date, Date, Bool) -> Void
    let invalidate: () -> Void
    let setTiming: (Date, PlanningVisitTiming?) -> Void
    @State private var opens: Date
    @State private var closes: Date
    @State private var checked = false
    @State private var timing: PlanningVisitTiming?
    @State private var visitDate: Date
    init(place: PlanningPlace, startsAt: Date, finishBy: Date, confirm: @escaping (Date, Date, Bool) -> Void, invalidate: @escaping () -> Void,
         setTiming: @escaping (Date, PlanningVisitTiming?) -> Void) {
        self.place = place; self.startsAt = startsAt; self.finishBy = finishBy; self.confirm = confirm; self.invalidate = invalidate; self.setTiming = setTiming
        _opens = State(initialValue: place.visitConfirmation?.opensAt ?? startsAt)
        _closes = State(initialValue: place.visitConfirmation?.closesAt ?? finishBy)
        _visitDate = State(initialValue: place.preferredAfter ?? startsAt)
        _timing = State(initialValue: place.visitTiming ?? (place.preferredAfter == nil ? nil : .preferred))
    }
    var body: some View {
        Section(place.name) {
            if place.availabilityVerified { Label("Sourced availability will be rechecked by the engine", systemImage: "checkmark.shield") }
            else if place.visitConfirmation != nil { Label("Confirmed by you for this trip", systemImage: "person.crop.circle.badge.checkmark") }
            else { Text("Opening hours and public access need confirmation.").foregroundStyle(.secondary) }
            DatePicker("Available from", selection: $opens, displayedComponents: .hourAndMinute)
            DatePicker("Available until", selection: $closes, displayedComponents: .hourAndMinute)
            Toggle("I checked public access and this visit window", isOn: $checked)
                .accessibilityIdentifier("pocketAccess-\(place.id)")
            Button("Confirm availability") { confirm(opens, closes, checked) }
                .disabled(!checked || closes <= opens)
                .accessibilityIdentifier("pocketConfirm-\(place.id)")
            Picker("Visit timing", selection: $timing) {
                Text("Any suitable time").tag(PlanningVisitTiming?.none)
                Text("Preferred time").tag(Optional(PlanningVisitTiming.preferred))
                Text("Required exact time").tag(Optional(PlanningVisitTiming.required))
                Text("Not before").tag(Optional(PlanningVisitTiming.notBefore))
            }
            if timing != nil { DatePicker("Visit time", selection: $visitDate, displayedComponents: .hourAndMinute) }
        }
        .onChange(of: opens) { _, _ in invalidate() }
        .onChange(of: closes) { _, _ in invalidate() }
        .onChange(of: checked) { _, _ in invalidate() }
        .onChange(of: timing) { _, value in setTiming(visitDate, value) }
        .onChange(of: visitDate) { _, value in setTiming(value, timing) }
    }
}
