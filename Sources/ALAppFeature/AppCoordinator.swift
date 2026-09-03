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
import ALListingFeature
import ALLocation
import ALMapFeature
import Observation
import SwiftUI

/// Cross-feature state. The only object that knows the flow end to end.
///
/// Features stay unaware of each other; this decides what a gate tap means and
/// what happens after a signup succeeds. Keeping that in one place is what makes
/// the funnel legible, and it is the single file to read to understand the
/// product's shape.
@MainActor
@Observable
public final class AppCoordinator {
    public enum Phase: Equatable, Sendable {
        case launch
        case map
    }

    /// What the wall was opened to unlock, so the right thing happens after.
    public enum GateIntent: Equatable, Sendable {
        /// From a building. Signing up opens that building.
        case listing(UUID)
        /// From the list's gate or the header. Signing up just returns.
        case browse
    }

    /// `.launch` only on the first run of an install.
    ///
    /// `phase` used to default to `.launch` unconditionally, and nothing was
    /// persisted, so the launch moment replayed on every cold launch forever.
    /// "Plays once" meant once per launch, which is not what once means to a
    /// renter who opens the app daily.
    public private(set) var phase: Phase
    public var gate: GateIntent?
    public var detail: ListingDetailStore?

    public let session: SessionStore
    public let map: MapStore
    public let permissions: LocationPermissionStore
    private let repository: ListingsRepository
    private let analytics: AnalyticsClient

    /// Walls shown this session. The ordinal on `wall_shown` is the single
    /// field that answers the how-many-asks question, and it cannot be
    /// reconstructed after the fact.
    private var wallsShownThisSession = 0
    private var currentEntry: GateEntry?

    private let launchRecord: LaunchRecord

    public init(
        session: SessionStore,
        map: MapStore,
        permissions: LocationPermissionStore,
        repository: ListingsRepository,
        launchRecord: LaunchRecord = .standard,
        analytics: AnalyticsClient = ConsoleAnalyticsClient()
    ) {
        self.session = session
        self.map = map
        self.permissions = permissions
        self.repository = repository
        self.launchRecord = launchRecord
        self.analytics = analytics
        let seen = launchRecord.hasSeenLaunchMoment
        self.phase = seen ? .map : .launch
        if seen {
            analytics.launchMomentDismissed(.alreadySeen)
        } else {
            analytics.launchMomentShown()
        }
    }

    /// Builds the whole graph from the two things an app shell should have to
    /// know about: where listings come from and how auth and location behave.
    /// Keeps `ALMapFeature` out of the app target's dependency list, so the
    /// module boundary in `Package.swift` is real rather than aspirational.
    public static func live(
        repository: ListingsRepository,
        authClient: AuthClient,
        locationClient: LocationClient,
        launchRecord: LaunchRecord = .standard,
        analytics: AnalyticsClient = ConsoleAnalyticsClient()
    ) -> AppCoordinator {
        AppCoordinator(
            session: SessionStore(client: authClient),
            map: MapStore(repository: repository),
            permissions: LocationPermissionStore(client: locationClient),
            repository: repository,
            launchRecord: launchRecord,
            analytics: analytics
        )
    }

    // MARK: - Flow

    public func launchFinished(source: LaunchDismissal = .tap) {
        guard phase == .launch else { return }
        analytics.launchMomentDismissed(source)
        launchRecord.hasSeenLaunchMoment = true
        phase = .map
    }

    /// A tap on the listing card. The gate fires here, one step past the pin.
    public func cardTapped(_ listing: Listing) {
        if session.isSignedIn {
            openDetail(for: listing, source: "signed_in_card")
        } else {
            present(.card, listing: listing)
        }
    }

    /// The list's gate button, a blurred row, or the header control.
    ///
    /// A blurred row names its building, so signup can land there. The bottom
    /// button and the header pill name nothing, which is `.browse`.
    public func gateTapped(for listing: Listing? = nil) {
        guard !session.isSignedIn else { return }
        present(listing == nil ? .listButton : .blurredRow, listing: listing)
    }

    /// The one place a wall is raised, so the ordinal cannot drift.
    private func present(_ entry: GateEntry, listing: Listing?) {
        wallsShownThisSession += 1
        currentEntry = entry
        analytics.wallShown(entry: entry, listing: listing?.id, ordinal: wallsShownThisSession)
        gate = listing.map { .listing($0.id) } ?? .browse
    }

    public func dismissGate() {
        if let currentEntry {
            analytics.wallDismissed(entry: currentEntry, ordinal: wallsShownThisSession)
        }
        gate = nil
    }

    public func signUp(using method: AuthMethod) {
        Task {
            let intent = gate
            let entry = currentEntry
            analytics.signupAttempted(method: method.analyticsName)
            await session.signUp(using: method)
            guard session.isSignedIn else {
                // Failure leaves the wall up so the renter can retry.
                if let error = session.lastError {
                    analytics.signupFailed(reason: String(describing: error))
                }
                return
            }
            // The renter may have dismissed the wall while auth was in flight.
            // `intent` was captured before the await, so without this a
            // swipe-away still force-opened the detail 450ms later.
            guard gate != nil else { return }
            analytics.signupSucceeded(method: method.analyticsName, entry: entry)

            // Order matters, and this is the second time this bug has bitten.
            //
            // The detail is set BEFORE the wall is cleared, so the presentation
            // slot never empties. Clearing first — even with a `Task.yield()`
            // between — dismissed the sheet and then asked to present again
            // while the dismissal was still animating, and the second
            // presentation was dropped. Measured: the renter signed up and
            // landed back on the map.
            //
            // `RootView.appModal` gives detail priority over the wall, so with
            // both set the slot stays occupied and only its content swaps.
            if case .listing(let id) = intent, let listing = map.listings.first(where: { $0.id == id }) {
                openDetail(for: listing, source: "post_signup")
            }
            gate = nil
        }
    }

    public func openDetail(for listing: Listing, source: String = "signed_in_card") {
        guard let token = session.token else {
            present(.card, listing: listing)
            return
        }
        analytics.detailOpened(listing: listing.id, source: source)
        detail = ListingDetailStore(listing: listing, repository: repository, token: token)
    }

    public func closeDetail() { detail = nil }

    /// The building the wall should show at the top of itself.
    public var gatedListing: Listing? {
        guard case .listing(let id) = gate else { return nil }
        return map.listings.first { $0.id == id }
    }
}
#endif
