import SwiftUI

/// Square place photo with rounded corners, or a map-pin placeholder when no photo is available.
struct PlaceThumbnail: View {
    let imageName: String?
    var size: CGFloat = 48
    var systemImage: String = "mappin.and.ellipse"
    /// Tile behind the symbol placeholder; pass a surface colour when the thumbnail sits on a grey card.
    var placeholderBackground: Color = AppColor.tertiaryFill

    var body: some View {
        Group {
            if let imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(AppColor.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(placeholderBackground)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }
}
