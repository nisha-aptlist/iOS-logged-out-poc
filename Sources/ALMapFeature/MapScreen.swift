// This module is iOS-only by its imports: UIKit, MapKit annotation views,
// UIImage, and iOS-only SwiftUI. The package declares macOS so that the pure
// modules (ALCore, ALAuth, ALLocation) have an honest availability floor —
// without it, Xcode building for "My Mac" fails in ALCore on `Duration` and
// `Task`. Guarding this file means the module compiles to nothing on macOS
// rather than failing to resolve UIKit, so EVERY scheme builds on EVERY
// destination and nobody has to know which one to pick.
#if os(iOS)
import ALCore
import ALDesignSystem
import ALLocation
import SwiftUI

/// The map screen.
///
/// Two layers, and the distinction is load-bearing.
///
/// **Layer 1, persistent.** The listings list and the selected building's card
/// share one `BottomSheetContainer`, which is a sibling in the ZStack, NOT a
/// `.sheet`. It never dismisses, and a permanently-presented sheet holds the
/// window's only presentation slot — which is precisely how the signup wall
/// came to be silently unreachable from all four of its entry points while
/// every unit test passed.
///
/// **Layer 2, transient and strictly one at a time.** The wall, the detail, the
/// explainer, the recovery sheet, the search picker. One `.sheet(item:)` on the
/// ZStack, so they present over the MAP rather than stacked on layer 1.
///
/// The card's content is injected rather than imported: `ALMapFeature` must not
/// depend on `ALListingFeature`, or the module graph gains a cycle and neither
/// feature can be built alone.
public struct MapScreen<CardContent: View, AppModalContent: View>: View {
    @Bindable private var store: MapStore
    private let permissions: LocationPermissionStore
    private let isSignedIn: Bool
    /// False while the launch moment is up. A `.sheet` presents at the window
    /// level, above any `zIndex` in our own hierarchy, so the listings sheet
    /// would otherwise draw on top of the launch screen.
    private let isActive: Bool
    private let initials: String
    private let onAccountTapped: () -> Void
    private let onGateTapped: (Listing?) -> Void
    /// `Bool` is whether the sheet is at its taller detent. Passed down rather
    /// than measured: the presentation owns the detent, and `UIScreen.main` is
    /// deprecated and wrong in multi-window.
    private let cardContent: (Listing, Bool) -> CardContent
    /// True when the app layer wants a modal up. It takes priority over the
    /// map's own sheets: a signup wall outranks a neighborhood picker.
    ///
    /// A `Bool` rather than the modal value: this type only ever needs to know
    /// whether one is wanted, and carrying the value forced a generic parameter
    /// and an `Equatable` constraint that bought nothing.
    private let appModalIsPresent: Bool
    private let appModalContent: () -> AppModalContent
    private let onAppModalDismiss: () -> Void

    /// The transient modals, which are strictly mutually exclusive.
    ///
    /// Previously `showsSearch`, `explainerBinding` and `recoveryBinding` were
    /// three independent sources of truth for a single presentation slot, and
    /// they could be true simultaneously. One optional makes that
    /// unrepresentable rather than merely unlikely.
    ///
    /// The persistent listings/card surface is deliberately NOT a member: it
    /// never dismisses, so folding it in would make "no modal" unrepresentable
    /// and force "listings AND explainer" to be one state.
    enum Modal: String, Identifiable {
        /// Owned by the app layer (the signup wall, the unlocked detail).
        /// Rendered through `appModalContent`, because `ALMapFeature` must not
        /// import `ALListingFeature`.
        case app
        case search, explainer, recovery
        var id: String { rawValue }
    }

    @State private var detentFraction: CGFloat = ALMetrics.listingsFraction
    @State private var modal: Modal?

    public init(
        store: MapStore,
        permissions: LocationPermissionStore,
        isSignedIn: Bool,
        isActive: Bool,
        initials: String,
        onAccountTapped: @escaping () -> Void,
        onGateTapped: @escaping (Listing?) -> Void,
        appModalIsPresent: Bool,
        onAppModalDismiss: @escaping () -> Void,
        @ViewBuilder appModalContent: @escaping () -> AppModalContent,
        @ViewBuilder cardContent: @escaping (Listing, Bool) -> CardContent
    ) {
        self.store = store
        self.permissions = permissions
        self.isSignedIn = isSignedIn
        self.isActive = isActive
        self.initials = initials
        self.onAccountTapped = onAccountTapped
        self.onGateTapped = onGateTapped
        self.appModalIsPresent = appModalIsPresent
        self.onAppModalDismiss = onAppModalDismiss
        self.appModalContent = appModalContent
        self.cardContent = cardContent
    }

    public var body: some View {
        ZStack(alignment: .top) {
            ListingMapView(
                listings: store.listings,
                selectedID: store.selectedListingID,
                userCoordinate: permissions.coordinate?.clLocationCoordinate,
                region: $store.region,
                regionIntent: store.regionIntent,
                onSelect: { store.select($0) },
                onDeselect: { store.clearSelection() }
            )
            .ignoresSafeArea()

            MapChromeView(
                placeLabel: store.filter.placeLabel,
                filter: store.filter,
                isSignedIn: isSignedIn,
                initials: initials,
                reducedPrecision: permissions.showsReducedPrecisionNotice,
                onSearchTapped: {
                    // Abandon any locate decision still resolving, or it will
                    // land on top of the sheet the renter just asked for.
                    permissions.cancelPendingLocate()
                    modal = .search
                },
                onAccountTapped: {
                    permissions.cancelPendingLocate()
                    onAccountTapped()
                },
                onBedrooms: { store.setBedrooms($0) },
                onRentTapped: { store.cycleRentCeiling() },
                onLocateTapped: { permissions.locateTapped() }
            )
            .padding(.top, 6)
            .opacity(isActive ? 1 : 0)

            if isActive {
                BottomSheetContainer(detents: containerDetents, selection: $detentFraction) {
                    sheetBody
                }
                // Layer 1 recedes while a modal is up.
                //
                // Not only for looks: the container deliberately extends under
                // the home indicator, and a presented sheet respects the safe
                // area, so a strip of layer 1 shows through beneath it. Without
                // this, the accent-coloured gate button bled through under the
                // explainer.
                .overlay {
                    if modal != nil {
                        // Opaque, not translucent.
                        //
                        // iOS 26 insets a non-`.large` sheet, so a strip of
                        // layer 1 shows below it — and a 22% black wash over
                        // International Orange still reads unmistakably pink,
                        // which looked like a rendering bug under the recovery
                        // sheet. Covering it in the ground colour removes the
                        // colour rather than muting it.
                        ALColor.ground
                            .ignoresSafeArea(edges: .bottom)
                            .allowsHitTesting(false)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: modal)
                .transition(.move(edge: .bottom))
            }

            // Zero-size, so it contributes no layout and blocks no gestures.
            // It exists to own the transient presentation slot at ZStack level,
            // which is what puts modals over the map instead of over layer 1.
            modalLayer
        }
        .task {
            permissions.start()
            await store.onAppear()
        }
        // Watches the intent count rather than the coordinate: a stationary
        // renter tapping locate twice yields an identical value, which would
        // never fire a value-based observer.
        .onChange(of: permissions.recenterRequests.count) { _, _ in
            guard let coordinate = permissions.recenterRequests.last else { return }
            store.flyToUser(coordinate)
        }
    }

    /// Heights available for layer 1, by what it is showing.
    ///
    /// A card opens at a quarter and can be dragged tall. The list starts at
    /// just under half and can be pulled up, which is what a signed-in renter
    /// needs to read thirty unlocked rows — the old fixed-detent sheet left
    /// them stuck at a third of the screen with no way to grow it.
    private var containerDetents: [CGFloat] {
        store.selectedListing == nil
            ? [ALMetrics.listingsFraction, ALMetrics.listExpandedFraction]
            : [ALMetrics.cardPeekFraction, ALMetrics.cardFullFraction, ALMetrics.listExpandedFraction]
    }

    @ViewBuilder
    private var sheetBody: some View {
        Group {
            if let listing = store.selectedListing {
                cardContent(listing, detentFraction >= ALMetrics.cardFullFraction - 0.01)
            } else {
                switch store.loadState {
                case .loaded(let results):
                    ListingsSheetView(
                        results: results,
                        isSignedIn: isSignedIn,
                        onSelect: { store.select($0) },
                        onGateTapped: onGateTapped
                    )
                case .loading, .idle:
                    ListingsLoadingView()
                case .failed(let message):
                    ListingsErrorView(message: message) { Task { await store.onAppear() } }
                }
            }
        }
    }

    /// Everything transient, in one slot, presented over the map.
    private var modalLayer: some View {
        Color.clear
            .allowsHitTesting(false)
        // Reset to the peek whenever the selection changes, so a card never
        // inherits the previous card's expanded height.
        .onChange(of: store.selectedListingID) { _, id in
            detentFraction = id == nil ? ALMetrics.listingsFraction : ALMetrics.cardPeekFraction
        }
        // The store owns the permission step, so a step change drives the slot
        // rather than being mirrored into a second piece of state.
        .onChange(of: permissions.step) { _, step in
            guard modal != .app else { return }   // the wall outranks these
            switch step {
            case .explaining: modal = .explainer
            case .recovering: modal = .recovery
            case .idle, .systemPrompt:
                if modal == .explainer || modal == .recovery { modal = nil }
            }
        }
        .onChange(of: appModalIsPresent) { _, isPresent in
            syncAppModal(isPresent)
        }
        .task(id: appModalIsPresent) {
            // Covers the app layer already wanting a modal on the first render,
            // before any change fires.
            syncAppModal(appModalIsPresent)
        }
        // A swipe-to-dismiss has to report back, or the state machine desyncs
        // and the next locate tap does nothing.
        .sheet(item: $modal, onDismiss: reportDismissal) { which in
            switch which {
            case .app:
                appModalContent()

            case .search:
                NeighborhoodSearchSheet(
                    neighborhoods: store.neighborhoods,
                    selected: store.filter.neighborhood
                ) { neighborhood in
                    store.selectNeighborhood(neighborhood)
                    modal = nil
                }
                .presentationDetents([.fraction(0.6), .large])

            case .explainer:
                LocationExplainerSheet(
                    onContinue: { permissions.explainerAccepted() },
                    onDismiss: { permissions.explainerDismissed() }
                )
                .presentationDetents([.height(430)])

            case .recovery:
                LocationRecoverySheet(
                    onOpenSettings: { permissions.openSettings() },
                    onDismiss: { permissions.recoveryDismissed() }
                )
                .presentationDetents([.height(400)])
            }
        }
    }

    /// Split out of the modifier chain: as a nested ternary inline, the type
    /// checker gave up on the whole `body` expression.
    private func syncAppModal(_ isPresent: Bool) {
        if isPresent {
            if modal != .app { modal = .app }
        } else if modal == .app {
            // Re-derive rather than clear. A step change that arrived while the
            // wall outranked it was DROPPED by the precedence guard, and
            // `.onChange` only fires on changes, so nothing would ever re-drive
            // the slot — leaving the locate control permanently dead.
            switch permissions.step {
            case .explaining: modal = .explainer
            case .recovering: modal = .recovery
            case .idle, .systemPrompt: modal = nil
            }
        }
    }

    private func reportDismissal() {
        if appModalIsPresent {
            onAppModalDismiss()
            return
        }
        switch permissions.step {
        case .explaining: permissions.explainerDismissed()
        case .recovering: permissions.recoveryDismissed()
        case .idle, .systemPrompt: break
        }
    }
}

// MARK: - Sheet states

struct ListingsLoadingView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Counting rentals")
                    .font(ALTypography.mono(11.5))
                    .foregroundStyle(ALColor.inkSecondary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)

            // Skeleton rows shaped like the real ones, so the sheet does not
            // resize when content lands.
            VStack(spacing: 0) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(ALColor.surfaceSunk)
                            .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 4).fill(ALColor.surfaceSunk).frame(width: 130, height: 12)
                            RoundedRectangle(cornerRadius: 4).fill(ALColor.surfaceSunk).frame(width: 90, height: 10)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                }
            }
            Spacer()
        }
        .background(ALColor.surface)
        .accessibilityLabel("Loading rentals")
    }
}

struct ListingsErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.system(size: 14.5))
                .foregroundStyle(ALColor.inkSecondary)
            Button("Try again", action: retry)
                .buttonStyle(ALSecondaryButtonStyle())
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ALColor.surface)
    }
}

struct NeighborhoodSearchSheet: View {
    let neighborhoods: [String]
    let selected: String?
    let onPick: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Where are you looking?")
                .font(ALTypography.display(19))
                .foregroundStyle(ALColor.ink)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)

            List {
                Button { onPick(nil) } label: {
                    row(title: "All of San Francisco", isSelected: selected == nil)
                }
                ForEach(neighborhoods, id: \.self) { neighborhood in
                    Button { onPick(neighborhood) } label: {
                        row(title: neighborhood, isSelected: selected == neighborhood)
                    }
                }
            }
            .listStyle(.plain)
        }
        .background(ALColor.surface)
    }

    private func row(title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ALColor.ink)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ALColor.accent)
            }
        }
        .contentShape(Rectangle())
    }
}
#endif
