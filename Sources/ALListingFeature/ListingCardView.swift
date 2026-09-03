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

/// The free surface, and the last one before the wall.
///
/// The gate fires on a tap anywhere on this card, one step past the pin. That
/// placement is the product decision: an ask with nothing specific behind it is
/// the version renters dismiss, so the card gives them a building to want first.
///
/// Two layouts, one set of data. At the peek detent it is a compact row; dragged
/// taller it becomes the three-photo card. Driven by the detent the sheet
/// reports rather than by a second copy of the content.
public struct ListingCardView: View {
    private let listing: Listing
    private let isExpanded: Bool
    private let isSignedIn: Bool
    private let onTap: () -> Void

    public init(
        listing: Listing,
        isExpanded: Bool,
        isSignedIn: Bool,
        onTap: @escaping () -> Void
    ) {
        self.listing = listing
        self.isExpanded = isExpanded
        self.isSignedIn = isSignedIn
        self.onTap = onTap
    }

    private var seed: Int { listing.name.stableHash }

    public var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                if isExpanded { gallery }

                info
                    .padding(.horizontal, ALMetrics.gutter)
                    .padding(.top, isExpanded ? 12 : 2)

                Spacer(minLength: 8)

                // Only pre-signup: once signed in there is nothing withheld,
                // so the row would be claiming a lock that does not exist.
                if !isSignedIn {
                    LockedRow()
                        .padding(.horizontal, ALMetrics.gutter)
                        .padding(.bottom, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(ALColor.surface)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isSignedIn ? "Opens the building" : "Opens signup to unlock unit details")
    }

    private var accessibilityLabel: String {
        "\(listing.name), \(listing.neighborhood). \(listing.rentRange.formatted). \(listing.bedroomSummary). \(listing.unitCountLabel)."
    }

    /// Three photos, swipeable. The count is a settled decision: enough to want
    /// the building, not enough to act on it.
    private var gallery: some View {
        TabView {
            ForEach(ListingPhoto.ordered(seed: seed), id: \.self) { photo in
                ListingPhotoView(photo: photo, seed: seed, showsCaption: true)
                    .clipShape(RoundedRectangle(cornerRadius: ALMetrics.cardRadius, style: .continuous))
                    .padding(.horizontal, 14)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: 250)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var info: some View {
        if isExpanded {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    titleBlock
                    Spacer(minLength: 12)
                    rangeText
                }
                metaRow.padding(.top, 5)
            }
        } else {
            HStack(spacing: 12) {
                ListingPhotoView(photo: .lead(for: seed), seed: seed)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: ALMetrics.inputRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 0) {
                    titleBlock
                    metaRow.padding(.top, 5)
                }

                Spacer(minLength: 8)
                rangeText
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(listing.name)
                .font(ALTypography.display(isExpanded ? 19 : 17))
                .foregroundStyle(ALColor.ink)
                .lineLimit(1)
            Text(listing.neighborhood.uppercased())
                .font(ALTypography.mono(10.5))
                .tracking(0.9)
                .foregroundStyle(ALColor.inkTertiary)
                .lineLimit(1)
        }
    }

    /// The card shows the whole range. The pin only showed the floor.
    private var rangeText: some View {
        Text(listing.rentRange.formatted)
            .font(ALTypography.mono(isExpanded ? 15 : 14))
            .foregroundStyle(ALColor.ink)
            .lineLimit(1)
            .layoutPriority(1)
    }

    /// No bathroom count. `Listing` carries no bathroom field, so the previous
    /// "1 to 2 ba" was inferred from the bedroom mix and agreed with the gated
    /// unit table only by coincidence of two independent hardcodes. Against a
    /// real feed the free card would contradict the paid screen, so the claim
    /// is dropped rather than guessed.
    private var metaRow: some View {
        HStack(spacing: 9) {
            Text(listing.bedroomSummary)
            dot
            Text(listing.unitCountLabel)
                .font(ALTypography.mono(12))
        }
        .font(.system(size: 13.5))
        .foregroundStyle(ALColor.inkSecondary)
        .lineLimit(1)
    }

    private var dot: some View {
        Circle().fill(ALColor.inkTertiary).frame(width: 3, height: 3)
    }
}
#endif
