import EventKit
import EventKitUI
import SwiftUI
import CoreLocation

struct CalendarDraft: Identifiable {
    let id = UUID()
    let activity: TourActivity
    let journey: String
    let runID: UUID
}

// EventKitUI saves only when the person confirms in Apple's editor. No broad calendar read permission.
struct CalendarEventSheet: UIViewControllerRepresentable {
    let draft: CalendarDraft
    let completed: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(draft: draft, completed: completed) }
    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let editor = EKEventEditViewController()
        editor.eventStore = context.coordinator.store
        editor.event = Self.makeEvent(draft, store: context.coordinator.store)
        editor.editViewDelegate = context.coordinator
        return editor
    }
    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}
    static func makeEvent(_ draft: CalendarDraft, store: EKEventStore) -> EKEvent {
        let event = EKEvent(eventStore: store)
        let activity = draft.activity
        event.title = activity.title; event.startDate = activity.start; event.endDate = activity.end
        event.timeZone = TimeZone(identifier: activity.timeZoneID)
        event.notes = "\(draft.journey)\n\(activity.notes)\n\nSalinan dari C67. Perubahan rundown berikutnya tidak otomatis memperbarui Calendar."
        if let place = activity.place {
            event.location = place.name
            let location = EKStructuredLocation(title: place.name)
            location.geoLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
            event.structuredLocation = location
        }
        return event
    }
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let store = EKEventStore()
        let draft: CalendarDraft
        let completed: (Bool) -> Void
        init(draft: CalendarDraft, completed: @escaping (Bool) -> Void) { self.draft = draft; self.completed = completed }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            completed(action == .saved)
        }
    }
}
