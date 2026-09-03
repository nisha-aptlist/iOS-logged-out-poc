// This module is iOS-only by its imports: UIKit, MapKit annotation views,
// UIImage, and iOS-only SwiftUI. The package declares macOS so that the pure
// modules (ALCore, ALAuth, ALLocation) have an honest availability floor —
// without it, Xcode building for "My Mac" fails in ALCore on `Duration` and
// `Task`. Guarding this file means the module compiles to nothing on macOS
// rather than failing to resolve UIKit, so EVERY scheme builds on EVERY
// destination and nobody has to know which one to pick.
#if os(iOS)
import SwiftUI

/// Semantic color tokens.
///
/// Every value is defined for both appearances at the point of definition, so
/// there is no code path that resolves a color in one mode and not the other.
/// `Color(uiColor:)` with a dynamic provider is used instead of an asset catalog
/// so the palette is reviewable as source and diffable in a pull request.
public enum ALColor {
    // Surfaces
    public static let ground = dynamic(light: 0xE4E7E4, dark: 0x14181A)
    public static let surface = dynamic(light: 0xFCFCFA, dark: 0x1D2225)
    public static let surfaceRaised = dynamic(light: 0xF2F2ED, dark: 0x262C2F)
    public static let surfaceSunk = dynamic(light: 0xE9E9E2, dark: 0x171C1E)

    // Ink
    public static let ink = dynamic(light: 0x1C2220, dark: 0xE8EBE8)
    public static let inkSecondary = dynamic(light: 0x5A625F, dark: 0xA0A8A5)
    public static let inkTertiary = dynamic(light: 0x8B938F, dark: 0x767E7B)
    public static let hairline = dynamic(light: 0x1C2220, dark: 0xE8EBE8, alpha: 0.12)

    /// International Orange, deepened. One accent, used for pins and the primary
    /// action only. System blue is deliberately *not* in this palette: the
    /// location puck and the permission alert are Apple's surfaces.
    public static let accent = dynamic(light: 0xC1452A, dark: 0xE4643C)
    public static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x16191A)
    public static let accentTint = dynamic(light: 0xC1452A, dark: 0xE4643C, alpha: 0.12)

    public static let lock = dynamic(light: 0x7C8480, dark: 0x8B938F)

    /// Semantic, and deliberately not the accent: error text in International
    /// Orange reads as a call to action rather than a problem.
    public static let danger = dynamic(light: 0xB3261E, dark: 0xF2B8B5)

    private static func dynamic(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha
            )
        })
    }
}

/// Spacing and radius scales. One radius rule, documented and followed:
/// interactive controls are fully rounded, containers use 16, inputs 12.
public enum ALMetrics {
    public static let gutter: CGFloat = 20
    public static let sheetRadius: CGFloat = 24
    public static let cardRadius: CGFloat = 16
    public static let inputRadius: CGFloat = 12
    public static let thumbRadius: CGFloat = 10

    /// Sheet detents. The listing card opens at a quarter of the screen so the
    /// map stays the dominant surface.
    public static let cardPeekFraction: CGFloat = 0.25
    public static let cardFullFraction: CGFloat = 0.58
    /// Sized so `freeRowCount` rows AND a clear blurred row sit above the gate.
    ///
    /// Measured three times, not guessed. 0.33 fit two readable rows, making
    /// the header untrue. 0.42 fit three but buried the blurred rows under the
    /// button — and those rows are the entire argument for signing up, so
    /// occluding them defeats the gate. 0.48 with tighter rows shows three
    /// readable, one clear blurred, and one hinted.
    public static let listingsFraction: CGFloat = 0.48
    /// Pulled-up height for layer 1. A signed-in renter has thirty unlocked
    /// rows to read and the fixed-detent sheet gave them no way to grow it.
    public static let listExpandedFraction: CGFloat = 0.92
}

public enum ALTypography {
    /// Prices, counts, and unit tables. Monospaced digits so columns line up and
    /// a changing count does not reflow the row.
    public static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    public static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
}
#endif
