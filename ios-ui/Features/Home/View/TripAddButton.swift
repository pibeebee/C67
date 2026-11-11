import SwiftUI

struct TripAddButton: View {
    let action: () -> Void
    var addSpecificPlace: () -> Void = {}

    var body: some View {
        #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                menu
                    .menuStyle(.button)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(glassControlSize)
                    .tint(AppColor.brand)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("homeAddTrip")
            } else {
                fallback
            }
        #else
            fallback
        #endif
    }

    private var fallback: some View {
        menu
            .menuStyle(.button)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .tint(AppColor.brand)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityIdentifier("homeAddTrip")
    }

    private var glassControlSize: ControlSize {
        if #available(iOS 27.0, *) { .regular } else { .small }
    }

    private var labelMinimumSize: CGFloat {
        #if compiler(>=6.2)
            if #available(iOS 27.0, *) { 30 }
            else if #available(iOS 26.0, *) { 24 }
            else { 30 }
        #else
            30
        #endif
    }

    private var labelMinimumHeight: CGFloat {
        #if compiler(>=6.2)
            if #available(iOS 27.0, *) { 30 }
            else if #available(iOS 26.0, *) { 34 }
            else { 30 }
        #else
            30
        #endif
    }

    private var menu: some View {
        Menu {
            Button("Get Recommendations", action: action)
            Button("Add Specific Place", action: addSpecificPlace)
        } label: {
            Label("Plan a trip", systemImage: "plus")
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                // Native button styles add their own padding around the label.
                .frame(minWidth: labelMinimumSize, minHeight: labelMinimumHeight)
        }
    }
}
