// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// Public Sans (SIL Open Font License, see Resources/Fonts/PublicSans-OFL.txt):
/// the body face used by Service NSW. Scales with Dynamic Type.
extension Font {
    private static func publicSans(_ w: Font.Weight) -> String {
        switch w {
        case .black: "PublicSans-Black"
        case .heavy: "PublicSans-ExtraBold"
        case .bold: "PublicSans-Bold"
        case .semibold: "PublicSans-SemiBold"
        case .medium: "PublicSans-Medium"
        default: "PublicSans-Regular"
        }
    }

    private static func baseSize(_ s: Font.TextStyle) -> CGFloat {
        switch s {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }

    /// Text style in Public Sans. Headline defaults to semibold, as in the system font.
    static func gov(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        let w = weight ?? (style == .headline ? .semibold : .regular)
        return .custom(publicSans(w), size: baseSize(style), relativeTo: style)
    }

    /// Fixed-size Public Sans for printed card text (scales gently with Dynamic Type).
    static func gov(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(publicSans(weight), size: size, relativeTo: .caption)
    }
}
