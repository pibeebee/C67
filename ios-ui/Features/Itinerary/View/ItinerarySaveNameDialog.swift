import SwiftUI

struct ItinerarySaveNameDialog: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var name: String
    let originalName: String
    let save: () -> Void

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    func body(content: Content) -> some View {
        content.alert("Save Itinerary", isPresented: $isPresented) {
            TextField("Itinerary name", text: $name)
                .accessibilityIdentifier("saveItineraryName")
            Button("Save", action: save)
                .disabled(trimmedName.isEmpty || trimmedName.count > 120)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Name your itinerary to save it. If you change the name, a new proposal is prepared for you to review before saving.")
        }
    }
}
