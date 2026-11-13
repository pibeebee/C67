import SwiftUI

/// Square place photo with rounded corners, or a map-pin placeholder when no photo is available.
struct PlaceThumbnail: View {
    let imageName: String?
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "mappin.and.ellipse")
                    .font(.title3)
                    .foregroundStyle(AppColor.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColor.tertiaryFill)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }
}
