import SwiftUI

/// Native Liquid Glass with a system material fallback for iOS 18.
struct TripGlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.interactive(), in: .capsule)
            } else {
                content.background(.regularMaterial, in: .capsule)
            }
        #else
            content.background(.regularMaterial, in: .capsule)
        #endif
    }
}
