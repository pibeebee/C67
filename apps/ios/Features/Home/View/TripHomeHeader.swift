import SwiftUI

struct TripHomeHeader: View {
    let locationTitle: String
    let chooseLocation: () -> Void
    let addTrip: () -> Void
    var addSpecificPlace: () -> Void = {}
    var isBusy = false
    var isLocating = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Text("Trip")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                TripLocationButton(title: locationTitle, isLocating: isLocating, action: chooseLocation)
                    .fixedSize()
                    .disabled(isBusy)
                Spacer(minLength: 0)
                TripAddButton(action: addTrip, addSpecificPlace: addSpecificPlace)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Trip")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    TripAddButton(action: addTrip, addSpecificPlace: addSpecificPlace)
                }
                TripLocationButton(title: locationTitle, isLocating: isLocating, action: chooseLocation)
                    .disabled(isBusy)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

#if DEBUG
    #Preview("HOME LOCATION PERMIS · Locating") {
        TripHomeHeader(locationTitle: "Choose a starting point", chooseLocation: {}, addTrip: {}, isLocating: true)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(AppColor.canvas)
    }

    #Preview("HOME · Starting point") {
        TripHomeHeader(locationTitle: "Current device position", chooseLocation: {}, addTrip: {})
            .frame(maxHeight: .infinity, alignment: .top)
            .background(AppColor.canvas)
    }
#endif
