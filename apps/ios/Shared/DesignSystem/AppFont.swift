import SwiftUI

/// Text roles from the Balaraja Sketch type scale (SF Pro).
///
/// Each role maps to a native text style, so it scales with Dynamic Type.
/// Reference sizes are for the default content size.
enum AppFont {
    /// 34 pt regular.
    static let largeTitle = Font.largeTitle
    /// 34 pt bold.
    static let largeTitleBold = Font.largeTitle.bold()
    /// 28 pt regular.
    static let title1 = Font.title
    /// 28 pt bold — Sketch `02 Title1/2 Bold`.
    static let title1Bold = Font.title.bold()
    /// 22 pt regular.
    static let title2 = Font.title2
    /// 20 pt regular.
    static let title3 = Font.title3
    /// 17 pt semibold — Sketch `05 Headline/1 Default`.
    static let headline = Font.headline
    /// 17 pt regular.
    static let body = Font.body
    /// 16 pt regular.
    static let callout = Font.callout
    /// 15 pt regular.
    static let subheadline = Font.subheadline
    /// 13 pt regular.
    static let footnote = Font.footnote
    /// 12 pt regular.
    static let caption1 = Font.caption
    /// 11 pt regular.
    static let caption2 = Font.caption2

    /// Splash tagline under the wordmark.
    static let brandTagline = Font.system(size: 17, weight: .semibold, design: .rounded)
}
