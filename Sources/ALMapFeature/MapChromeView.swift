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

/// The floating controls over the map: place, filters, account, locate.
///
/// No map/list toggle and no list button. The listings sheet is always present
/// at its detent, so a toggle would be a second way to reach a surface that
/// never leaves.
struct MapChromeView: View {
    let placeLabel: String
    let filter: ListingFilter
    let isSignedIn: Bool
    let initials: String
    let reducedPrecision: Bool

    let onSearchTapped: () -> Void
    let onAccountTapped: () -> Void
    let onBedrooms: (ListingFilter.Bedrooms) -> Void
    let onRentTapped: () -> Void
    let onLocateTapped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                searchPill
                accountControl
            }

            // Scrolls: five pills do not fit across a 393pt screen, and the
            // rent pill was being clipped off the right edge.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(ListingFilter.Bedrooms.allCases, id: \.self) { option in
                        FilterPill(title: option.label, isOn: filter.bedrooms == option) {
                            onBedrooms(option)
                        }
                    }
                    FilterPill(title: filter.rentPillLabel, isOn: filter.maxRent != nil) {
                        onRentTapped()
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()

            HStack {
                Spacer()
                locateControl
            }
        }
        .padding(.horizontal, 16)
    }

    private var searchPill: some View {
        Button(action: onSearchTapped) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ALColor.inkTertiary)
                Text(placeLabel)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ALColor.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(ALColor.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(ALColor.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search a neighborhood. Currently \(placeLabel)")
    }

    @ViewBuilder
    private var accountControl: some View {
        if isSignedIn {
            Text(initials)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ALColor.ink)
                .frame(width: 44, height: 44)
                .background(ALColor.surface, in: Circle())
                .overlay(Circle().strokeBorder(ALColor.hairline, lineWidth: 1))
                .accessibilityLabel("Signed in as \(initials)")
        } else {
            Button(action: onAccountTapped) {
                Text("Sign up")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(ALColor.onAccent)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(ALColor.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var locateControl: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button(action: onLocateTapped) {
                Image(systemName: "location")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ALColor.accent)
                    .frame(width: 40, height: 40)
                    .background(ALColor.surface, in: Circle())
                    .overlay(Circle().strokeBorder(ALColor.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Use my location")

            if reducedPrecision {
                // Says so rather than quietly showing distances that are wrong
                // by a mile or two.
                Text("Approximate location")
                    .font(ALTypography.mono(9.5))
                    .foregroundStyle(ALColor.inkSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    // Opaque, not `.regularMaterial`. A translucent capsule
                    // over an accent-coloured price pin bled orange through
                    // itself and clipped a sliver of the pin above its edge,
                    // which reads as a rendering artifact. Same failure as the
                    // pink strip under the recovery sheet. It also now carries
                    // the hairline every other floating control has.
                    .background(ALColor.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(ALColor.hairline, lineWidth: 1))
                    .shadow(color: .black.opacity(0.10), radius: 4, y: 1)
            }
        }
    }
}
#endif
