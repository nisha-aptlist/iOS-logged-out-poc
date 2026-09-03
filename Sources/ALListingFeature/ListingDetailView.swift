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
import Observation
import SwiftUI

/// The reward. Everything the wall was selling.
@MainActor
@Observable
public final class ListingDetailStore: Identifiable {
    /// `nonisolated` so `fullScreenCover(item:)` can read it without hopping.
    /// Safe because `listing` is an immutable `Sendable` `let`.
    public nonisolated var id: UUID { listing.id }

    public enum State: Equatable, Sendable {
        case loading
        case loaded(GatedDetails)
        case failed(String)
    }

    public private(set) var state: State = .loading
    public let listing: Listing

    private let repository: ListingsRepository
    private let token: SessionToken

    public init(listing: Listing, repository: ListingsRepository, token: SessionToken) {
        self.listing = listing
        self.repository = repository
        self.token = token
    }

    public func load() async {
        state = .loading
        do {
            state = .loaded(try await repository.gatedDetails(for: listing.id, token: token))
        } catch ListingsError.unauthorized {
            state = .failed("We could not load unit details. Try again.")
        } catch {
            state = .failed("We could not load the building. Try again.")
        }
    }
}

public struct ListingDetailView: View {
    enum ContactAttempt: String, Identifiable {
        case tour, message
        var id: String { rawValue }

        var title: String {
            switch self {
            case .tour: "Tour requests are not wired up"
            case .message: "Messaging is not wired up"
            }
        }

        var body: String {
            "This prototype has no leasing backend, so nothing was sent. In the real app this reaches the leasing team for this building."
        }
    }

    @State private var store: ListingDetailStore
    @State private var contactAttempt: ContactAttempt?
    private let onClose: () -> Void

    public init(store: ListingDetailStore, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
    }

    private var seed: Int { store.listing.name.stableHash }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    gallery

                    VStack(alignment: .leading, spacing: 0) {
                        Text(store.listing.name)
                            .font(ALTypography.display(24))
                            .foregroundStyle(ALColor.ink)

                        addressLine
                            .padding(.top, 6)

                        unitsSection
                            .padding(.top, 26)

                        buildingSection
                            .padding(.top, 26)

                        actions
                            .padding(.top, 26)
                    }
                    .padding(.horizontal, ALMetrics.gutter)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .background(ALColor.surface)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onClose()
                    } label: {
                        Label("Map", systemImage: "chevron.left")
                            .labelStyle(.titleAndIcon)
                    }
                    .tint(ALColor.accent)
                }
            }
        }
        .task { await store.load() }
        .alert(item: $contactAttempt) { attempt in
            Alert(title: Text(attempt.title), message: Text(attempt.body), dismissButton: .default(Text("OK")))
        }
    }

    /// The facade leads, the interiors sit beneath it.
    private var gallery: some View {
        let photos = ListingPhoto.allCases
        return VStack(spacing: 3) {
            ListingPhotoView(photo: photos[0], seed: seed)
                .frame(height: 230)
            HStack(spacing: 3) {
                ForEach(photos.dropFirst(), id: \.self) { photo in
                    ListingPhotoView(photo: photo, seed: seed)
                        .frame(height: 150)
                }
            }
        }
    }

    @ViewBuilder
    private var addressLine: some View {
        switch store.state {
        case .loaded(let details):
            Text(details.streetAddress)
                .font(.system(size: 14.5))
                .foregroundStyle(ALColor.inkSecondary)
        case .loading:
            RoundedRectangle(cornerRadius: 4)
                .fill(ALColor.surfaceSunk)
                .frame(width: 220, height: 14)
        case .failed:
            EmptyView()
        }
    }

    private var unlockedBadge: some View {
        Text("UNLOCKED")
            .font(ALTypography.mono(10.5))
            .tracking(1.4)
            .foregroundStyle(ALColor.accent)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(ALColor.accentTint, in: Capsule())
    }

    @ViewBuilder
    private var unitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Available units")

            switch store.state {
            case .loaded(let details):
                VStack(spacing: 0) {
                    ForEach(details.units) { unit in
                        UnitRow(unit: unit)
                        if unit.id != details.units.last?.id {
                            Divider().overlay(ALColor.hairline)
                        }
                    }
                }
            case .loading:
                VStack(spacing: 10) {
                    ForEach(0 ..< 3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(ALColor.surfaceSunk)
                            .frame(height: 44)
                    }
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 10) {
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundStyle(ALColor.inkSecondary)
                    // Was terminal: an error with no retry control at all.
                    Button("Try again") { Task { await store.load() } }
                        .buttonStyle(ALSecondaryButtonStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var buildingSection: some View {
        if case .loaded(let details) = store.state {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Building")
                // A wrapping flow of chips, not a ten-row table with a hairline
                // under every line.
                FlowLayout(spacing: 6) {
                    ForEach(details.amenities, id: \.self) { amenity in
                        Text(amenity)
                            .font(.system(size: 13))
                            .foregroundStyle(ALColor.inkSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(ALColor.surfaceSunk, in: Capsule())
                    }
                }
            }
        }
    }

    /// Both actions acknowledge rather than doing nothing.
    ///
    /// They were `{}` — inert primary buttons on the screen the renter just
    /// created an account to reach, which is a worse dead end than the wall
    /// itself. There is no leasing backend, so they confirm honestly instead of
    /// pretending to send.
    private var actions: some View {
        HStack(spacing: 8) {
            Button("Request a tour") { contactAttempt = .tour }
                .buttonStyle(ALPrimaryButtonStyle())
            Button("Message") { contactAttempt = .message }
                .buttonStyle(ALSecondaryButtonStyle())
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(ALTypography.mono(10.5))
            .tracking(1.4)
            .foregroundStyle(ALColor.inkTertiary)
    }
}

private struct UnitRow: View {
    let unit: RentalUnit

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(unit.id)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ALColor.ink)
                Text("\(unit.squareFeet) sq ft")
                    .font(.system(size: 12.5))
                    .foregroundStyle(ALColor.inkTertiary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(unit.layoutLabel)
                    .font(.system(size: 14))
                    .foregroundStyle(ALColor.ink)
                Text(availability)
                    .font(.system(size: 12.5))
                    .foregroundStyle(ALColor.inkTertiary)
            }
            .frame(width: 110, alignment: .leading)

            Spacer(minLength: 12)

            Text(unit.rent.formatted)
                .font(ALTypography.mono(14))
                .foregroundStyle(ALColor.ink)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Unit \(unit.id), \(unit.layoutLabel), \(unit.squareFeet) square feet, \(unit.rent.formatted), \(availability)")
    }

    private var availability: String {
        guard let date = unit.availableOn else { return "Call for availability" }
        return "Available \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

/// Minimal flow layout for amenity chips. `Layout` rather than a nested
/// `HStack`/`ForEach` guess, so wrapping is measured rather than assumed. It
/// wraps correctly for whatever size the chips report; it does not make the
/// chips themselves scale, since their font is a fixed size.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                widestRow = max(widestRow, x - spacing)   // x carries a trailing gap
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        widestRow = max(widestRow, x - spacing)

        // Reports what the content needs, not the whole proposal. Returning the
        // proposal verbatim over-reported 400pt for 250pt of chips, which only
        // looked fine because this sits in a full-width VStack.
        return CGSize(width: min(maxWidth, max(0, widestRow)), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
#endif
