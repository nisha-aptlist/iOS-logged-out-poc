// This module is iOS-only by its imports: UIKit, MapKit annotation views,
// UIImage, and iOS-only SwiftUI. The package declares macOS so that the pure
// modules (ALCore, ALAuth, ALLocation) have an honest availability floor —
// without it, Xcode building for "My Mac" fails in ALCore on `Duration` and
// `Task`. Guarding this file means the module compiles to nothing on macOS
// rather than failing to resolve UIKit, so EVERY scheme builds on EVERY
// destination and nobody has to know which one to pick.
#if os(iOS)
import SwiftUI

/// The one primary action style. Full-pill per the radius rule, and 52pt tall so
/// it clears the 44pt minimum with room for a comfortable label.
public struct ALPrimaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(ALColor.onAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(ALColor.accent, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

public struct ALSecondaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(ALColor.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(ALColor.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(ALColor.hairline, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

/// The row that names what signing up unlocks.
///
/// Its job is to make the gate legible *before* the tap, so the wall is not a
/// surprise. Naming the withheld fields converts better than "See more".
public struct LockedRow: View {
    private let items: String
    public init(items: String = "Rents by unit, move-in dates, and the address") { self.items = items }

    public var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12))
                .foregroundStyle(ALColor.lock)
            Text(items)
                .font(.system(size: 13.5))
                .foregroundStyle(ALColor.inkSecondary)
                // Two lines, because at one line this truncated to "...and th…"
                // at the DEFAULT content size — ellipsizing exactly on the
                // thing the row exists to name.
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text("Unlock")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(ALColor.accent)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(ALColor.surfaceSunk, in: RoundedRectangle(cornerRadius: ALMetrics.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Locked: \(items). Sign up to unlock.")
    }
}

/// A pill in the filter row.
public struct FilterPill: View {
    private let title: String
    private let isOn: Bool
    private let action: () -> Void

    public init(title: String, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(isOn ? ALColor.surface : ALColor.inkSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(isOn ? ALColor.ink : ALColor.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? .clear : ALColor.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// A small circular icon plate, used at the head of the explainer sheets.
public struct IconPlate: View {
    private let systemName: String
    private let muted: Bool

    public init(systemName: String, muted: Bool = false) {
        self.systemName = systemName
        self.muted = muted
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(muted ? ALColor.lock : ALColor.accent)
            .frame(width: 44, height: 44)
            .background(muted ? ALColor.surfaceSunk : ALColor.accentTint, in: Circle())
            .accessibilityHidden(true)
    }
}
#endif
