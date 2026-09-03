// This module is iOS-only by its imports: UIKit, MapKit annotation views,
// UIImage, and iOS-only SwiftUI. The package declares macOS so that the pure
// modules (ALCore, ALAuth, ALLocation) have an honest availability floor —
// without it, Xcode building for "My Mac" fails in ALCore on `Duration` and
// `Task`. Guarding this file means the module compiles to nothing on macOS
// rather than failing to resolve UIKit, so EVERY scheme builds on EVERY
// destination and nobody has to know which one to pick.
#if os(iOS)
import ALDesignSystem
import ALLocation
import SwiftUI

/// The pre-permission explainer: the one location screen we control.
///
/// It exists because the system prompt fires at most once per install. Shown
/// first, it converts a likely refusal into a deferral while the prompt is still
/// spendable. It names the payoff, and it tells the truth about the mechanism,
/// because a renter who understands "only once" answers more carefully.
public struct LocationExplainerSheet: View {
    private let onContinue: () -> Void
    private let onDismiss: () -> Void

    public init(onContinue: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.onContinue = onContinue
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IconPlate(systemName: "location.fill")
                .padding(.top, 12)
                .padding(.bottom, 14)

            Text("See what is near you")
                .font(ALTypography.display(26))
                .foregroundStyle(ALColor.ink)
                .padding(.bottom, 10)

            // Deliberately claims no distances: nothing in the product shows one, and
            // trading a permission for a feature that does not exist is the
            // fastest way to lose the second ask.
            Text("The map opens on your block, so you can see what is actually walkable from where you are. iOS will ask for permission next, and it only asks once, so it is worth answering now.")
                .font(.system(size: 14.5))
                .foregroundStyle(ALColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)

            Button("Continue", action: onContinue)
                .buttonStyle(ALPrimaryButtonStyle())

            Button("Not now", action: onDismiss)
                .buttonStyle(ALSecondaryButtonStyle())
                .padding(.top, 10)

            Text("Prototype. Nothing is requested from the system in the demo build.")
                .font(.system(size: 11.5))
                .foregroundStyle(ALColor.inkTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 26)
        .background(ALColor.surface)
    }
}

/// After a denial, the only route back.
public struct LocationRecoverySheet: View {
    private let onOpenSettings: () -> Void
    private let onDismiss: () -> Void

    public init(onOpenSettings: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IconPlate(systemName: "location.slash.fill", muted: true)
                .padding(.top, 12)
                .padding(.bottom, 14)

            Text("Location is off for Apartment List")
                .font(ALTypography.display(26))
                .foregroundStyle(ALColor.ink)
                .padding(.bottom, 10)

            // Naming the exact path matters. "Check your settings" is where
            // these screens fail.
            Text("iOS only asks once, so this has to be turned back on in Settings: Apartment List, then Location, then While Using the App.")
                .font(.system(size: 14.5))
                .foregroundStyle(ALColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)

            Button("Open Settings", action: onOpenSettings)
                .buttonStyle(ALPrimaryButtonStyle())

            Button("Keep browsing", action: onDismiss)
                .buttonStyle(ALSecondaryButtonStyle())
                .padding(.top, 10)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 26)
        .background(ALColor.surface)
    }
}
#endif
