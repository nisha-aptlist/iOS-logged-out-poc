// This module is iOS-only by its imports: UIKit, MapKit annotation views,
// UIImage, and iOS-only SwiftUI. The package declares macOS so that the pure
// modules (ALCore, ALAuth, ALLocation) have an honest availability floor —
// without it, Xcode building for "My Mac" fails in ALCore on `Duration` and
// `Task`. Guarding this file means the module compiles to nothing on macOS
// rather than failing to resolve UIKit, so EVERY scheme builds on EVERY
// destination and nobody has to know which one to pick.
#if os(iOS)
import ALAuth
import ALCore
import ALDesignSystem
import ALLaunchFeature
import ALListingFeature
import ALLocation
import ALMapFeature
import SwiftUI

/// Composition root for the UI. Wires features together and owns nothing else.
///
/// Note where the modals are presented from. `RootView` used to present the
/// signup wall with its own `.sheet` and the detail with `.fullScreenCover`.
/// Both were silently dropped: they resolve to the same presentation host as
/// the listings sheet, which is always up and holds the only slot. Measured —
/// the wall never appeared from either entry point, which made the gate
/// unreachable in the running app.
///
/// So the app layer states its intent (`AppModal`) and `MapScreen` presents it
/// through the one slot it owns. `RootView` still builds the views, so the
/// module boundary is intact: `ALMapFeature` never sees `ALListingFeature`.
public struct RootView: View {
    @State private var coordinator: AppCoordinator
    /// True in the demo build: the launch moment loops so it can be studied.
    /// False for a real install, where it plays once and advances itself.
    private let loopsLaunch: Bool

    /// The app layer's transient modals, in priority order.
    enum AppModal: Equatable {
        case wall
        case detail(UUID)
    }

    public init(coordinator: AppCoordinator, loopsLaunch: Bool = false) {
        self.coordinator = coordinator
        self.loopsLaunch = loopsLaunch
    }

    private var appModal: AppModal? {
        // Detail outranks the wall: after a successful signup both are briefly
        // set, and the reward is what the renter should land on.
        if let detail = coordinator.detail { return .detail(detail.id) }
        if coordinator.gate != nil { return .wall }
        return nil
    }

    public var body: some View {
        ZStack {
            mapScreen

            if coordinator.phase == .launch {
                LaunchMomentView(loops: loopsLaunch) {
                    withAnimation(.easeOut(duration: 0.45)) {
                        coordinator.launchFinished()
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        // The map is built underneath the launch screen rather than after it, so
        // the first frame after the tap already has pins on it.
        .animation(.easeOut(duration: 0.45), value: coordinator.phase)
    }

    private var mapScreen: some View {
        MapScreen(
            store: coordinator.map,
            permissions: coordinator.permissions,
            isSignedIn: coordinator.session.isSignedIn,
            isActive: coordinator.phase == .map,
            initials: coordinator.session.initials,
            onAccountTapped: { coordinator.gateTapped() },
            onGateTapped: { coordinator.gateTapped(for: $0) },
            appModalIsPresent: appModal != nil,
            onAppModalDismiss: {
                // A swipe-to-dismiss has to reach the coordinator, or its state
                // still says a modal is up and the next tap does nothing.
                if coordinator.detail != nil {
                    coordinator.closeDetail()
                } else {
                    coordinator.dismissGate()
                }
            },
            appModalContent: { appModalView },
            cardContent: { listing, isExpanded in
                ListingCardView(
                    listing: listing,
                    isExpanded: isExpanded,
                    isSignedIn: coordinator.session.isSignedIn,
                    onTap: { coordinator.cardTapped(listing) }
                )
            }
        )
    }

    @ViewBuilder
    private var appModalView: some View {
        if let detail = coordinator.detail {
            ListingDetailView(store: detail) { coordinator.closeDetail() }
                .presentationDetents([.large])
                // Was a `fullScreenCover`. Routing it through the shared slot
                // made it a large sheet, which is fine and more iOS-native for
                // a drill-down, but swipe-to-dismiss on the reward screen was a
                // consequence rather than a choice. The "Map" button is the way
                // out, as it was before.
                .interactiveDismissDisabled()
        } else {
            SignupWallView(
                listing: coordinator.gatedListing,
                session: coordinator.session,
                onSignUp: { coordinator.signUp(using: $0) },
                onDismiss: { coordinator.dismissGate() }
            )
            // Sized to the content rather than a fixed height: the promise
            // became three bullets, and 540pt left a dead band under the
            // buttons. `.large` stays available for the email field.
            .presentationDetents([.medium, .large])
        }
    }
}
#endif
