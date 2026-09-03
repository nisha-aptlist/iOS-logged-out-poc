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
import SwiftUI

/// The listings sheet: three buildings readable, the rest present but blurred.
///
/// The blurred rows are rendered rather than truncated on purpose. Showing that
/// there are twenty-seven more buildings is the argument for signing up;
/// cutting the list off at three just looks like thin inventory. Blur is applied
/// per row by index, so scrolling never promotes a locked row into a readable
/// one, and the gate stays honest at every scroll offset.
public struct ListingsSheetView: View {
    /// Unbounded once signed in: the gate has already been paid.
    /// The number itself is `FreeSurface.readableRowCount` in ALCore.
    public static var freeRowCount: Int { FreeSurface.readableRowCount }

    private let results: ListingResults
    private let isSignedIn: Bool
    private let onSelect: (Listing) -> Void
    /// Carries the building when the ask came from a specific row, so signup
    /// can land the renter on it. A nil listing means the bottom button, where
    /// no building was ever named.
    private let onGateTapped: (Listing?) -> Void

    public init(
        results: ListingResults,
        isSignedIn: Bool,
        onSelect: @escaping (Listing) -> Void,
        onGateTapped: @escaping (Listing?) -> Void
    ) {
        self.results = results
        self.isSignedIn = isSignedIn
        self.onSelect = onSelect
        self.onGateTapped = onGateTapped
    }

    /// Nothing is withheld from a signed-in renter.
    private var lockedFrom: Int { isSignedIn ? .max : Self.freeRowCount }

    /// The gate is an offer to unlock what is hidden. With three or fewer
    /// results nothing is hidden, so offering it is a lie the renter can see
    /// through: "Sign up to see all 1 buildings".
    private var showsGate: Bool {
        !isSignedIn && results.buildingCount > Self.freeRowCount
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            if results.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(ALColor.surface)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(results.countLabel)
                .font(ALTypography.mono(11.5))
                .foregroundStyle(ALColor.inkSecondary)
            Spacer()
            // Buildings, not units: three readable rows is inherently a
            // building count, and the word has to be said or the number lies.
            Text(showsGate
                 ? "\(min(Self.freeRowCount, results.buildingCount)) of \(results.buildingCount) buildings"
                 : "\(results.buildingCount) building\(results.buildingCount == 1 ? "" : "s")")
                .font(.system(size: 12))
                .foregroundStyle(ALColor.inkTertiary)
        }
        .padding(.horizontal, 18)
        .padding(.top, 13)
        .padding(.bottom, 9)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(results.listings.enumerated()), id: \.element.id) { index, listing in
                    let isLocked = index >= lockedFrom
                    ListingRow(listing: listing, isLocked: isLocked) {
                        // A locked row hands its building to the gate rather
                        // than discarding it, so the wall has a subject and
                        // signup lands on the building that was tapped.
                        isLocked ? onGateTapped(listing) : onSelect(listing)
                    }
                    if index != results.listings.count - 1 {
                        Divider().overlay(ALColor.hairline).padding(.leading, 18)
                    }
                }
            }
            // Clears the gate overlay so the final row is reachable.
            .padding(.bottom, showsGate ? 104 : 16)
        }
        .scrollIndicators(.hidden)
        // Only when something is actually withheld. Signed-in was handled;
        // "fewer results than the free row count" was not.
        .overlay(alignment: .bottom) { if showsGate { gate } }
    }

    private var gate: some View {
        VStack {
            Button {
                onGateTapped(nil)
            } label: {
                Text("Sign up to see all \(results.buildingCount) buildings")
            }
            .buttonStyle(ALPrimaryButtonStyle())
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .background {
            // Fades the blur into the button rather than ending on a hard line.
            LinearGradient(
                colors: [ALColor.surface.opacity(0), ALColor.surface],
                startPoint: .top,
                endPoint: .center
            )
            .allowsHitTesting(false)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("Nothing matches those filters")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ALColor.ink)
            Text("Try a higher max rent, or fewer bedrooms.")
                .font(.system(size: 13))
                .foregroundStyle(ALColor.inkTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }
}

/// A row, in two shapes, because accessibility forced the split.
///
/// Four attempts to hide a locked row's content from VoiceOver failed, each for
/// a different reason, and all four shared one cause: **a `Button` publishes
/// its label's children no matter what you do to them.**
///
///   1. `.accessibilityElement(children: .ignore)` on the Button — the derived
///      label still exposed the building name.
///   2. `.accessibilityHidden` on the Button plus `children: .contain` —
///      `.contain` re-established the subtree as navigable, undoing the hide.
///   3. `.accessibilityHidden` on the Button alone — the Button still published
///      itself, and its children came back with it.
///   4. `.accessibilityHidden` on the Button's *content* — same outcome.
///
/// So a locked row is not a Button. It is a plain view with a tap gesture and
/// exactly one accessibility element, which leaves nothing for VoiceOver to
/// walk into. The visual result is identical.
///
/// This matters because the blur is the gate: a renter using VoiceOver was
/// getting every withheld building read out in full, which is a spec violation
/// (SPEC: "blurred rows must not be readable by VoiceOver") and a worse
/// experience than the sighted one, not an equivalent one.
private struct ListingRow: View {
    let listing: Listing
    let isLocked: Bool
    let action: () -> Void

    var body: some View {
        if isLocked {
            // Renders NO real strings. Not a modifier, a construction.
            //
            // Five attempts to hide the real content from VoiceOver all failed
            // — `.accessibilityElement(children: .ignore)`, `.contain`,
            // `.accessibilityHidden` on the Button, on its content, and
            // dropping the Button entirely. The row's `Text` views stayed in
            // the accessibility tree every time.
            //
            // So a locked row does not contain the data. It is the same
            // geometry drawn as bars, which after a 5pt blur is
            // indistinguishable from blurred text, and the withheld name is
            // never in the view tree at all. That is the only version of this
            // that cannot regress: there is nothing to leak.
            lockedContent
                .blur(radius: 3)
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
                .accessibilityElement()
                .accessibilityLabel("Locked. Sign up to see this building.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(.default, action)
        } else {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(listing.name), \(listing.neighborhood), from \(listing.rentRange.low.formatted)"
                )
        }
    }

    /// The same geometry as a readable row, with bars where the words go.
    private var lockedContent: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(ALColor.surfaceSunk)
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 5) {
                bar(width: 118, height: 11)
                bar(width: 84, height: 9)
            }

            Spacer(minLength: 8)
            bar(width: 62, height: 11)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .frame(height: 60)
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(ALColor.inkTertiary.opacity(0.28))
            .frame(width: width, height: height)
    }

    private var content: some View {
        HStack(spacing: 12) {
            ListingPhotoView(photo: .lead(for: listing.name.stableHash), seed: listing.name.stableHash)
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(listing.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ALColor.ink)
                    .lineLimit(1)
                Text("\(listing.neighborhood) · \(listing.unitCountShort)")
                    .font(ALTypography.mono(11))
                    .foregroundStyle(ALColor.inkTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(listing.rentRange.fromFormatted)
                .font(ALTypography.mono(13))
                .foregroundStyle(ALColor.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}
#endif
