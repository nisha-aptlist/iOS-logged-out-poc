// This module is iOS-only by its imports: UIKit, MapKit annotation views,
// UIImage, and iOS-only SwiftUI. The package declares macOS so that the pure
// modules (ALCore, ALAuth, ALLocation) have an honest availability floor —
// without it, Xcode building for "My Mac" fails in ALCore on `Duration` and
// `Task`. Guarding this file means the module compiles to nothing on macOS
// rather than failing to resolve UIKit, so EVERY scheme builds on EVERY
// destination and nobody has to know which one to pick.
#if os(iOS)
import ALCore
import MapKit
import Observation

/// Everything the map screen needs, and nothing about how it is drawn.
///
/// Intent methods in, observable state out. No view reaches into the repository,
/// which is what keeps the gating rule in one place and makes every one of these
/// transitions testable without a host application.
@MainActor
@Observable
public final class MapStore {

    /// Loading is a real state with a real UI, not an implicit gap. A rental map
    /// that renders zero pins while fetching is indistinguishable from a map
    /// with no inventory.
    public enum LoadState: Equatable, Sendable {
        case idle
        case loading
        case loaded(ListingResults)
        case failed(String)

        public var results: ListingResults? {
            if case .loaded(let results) = self { return results }
            return nil
        }
    }

    public private(set) var loadState: LoadState = .idle
    /// Surfaced as a banner. Kept separate from `loadState` so a failed refilter
    /// reports the error without discarding the pins already on the map.
    public private(set) var loadError: String?
    public private(set) var filter: ListingFilter = .none
    public private(set) var neighborhoods: [String] = []
    public var selectedListingID: UUID?

    /// The camera, as a region rather than a `MapCameraPosition`, because the
    /// map is `MKMapView` behind a bridge and that is the type it speaks.
    /// Owned here so a fly-to survives a sheet presentation, which it would not
    /// if it lived in `@State` on the view.
    public var region: MKCoordinateRegion = SanFrancisco.cityRegion

    /// Bumped on every deliberate camera move. The bridge applies a region when
    /// this changes rather than when the geometry differs, because MapKit
    /// aspect-fits a region and the value it reports back never equals the one
    /// that was requested.
    public private(set) var regionIntent = 0

    private let repository: ListingsRepository
    /// Boxed so `deinit` can cancel it: a nonisolated `deinit` cannot read a
    /// `@MainActor` stored property. See `TaskBox`.
    private let loads = TaskBox()
    private var rentCeilingIndex = 0

    public init(repository: ListingsRepository) {
        self.repository = repository
    }

    deinit { loads.cancel() }

    public var listings: [Listing] { loadState.results?.listings ?? [] }

    public var selectedListing: Listing? {
        guard let selectedListingID else { return nil }
        return listings.first { $0.id == selectedListingID }
    }

    public var countLabel: String {
        switch loadState {
        case .loaded(let results): results.countLabel
        case .loading, .idle: "Counting rentals"
        case .failed: "Could not load rentals"
        }
    }

    // MARK: - Intents

    public func onAppear() async {
        await reload()
        if neighborhoods.isEmpty {
            neighborhoods = (try? await repository.neighborhoods()) ?? []
        }
    }

    public func setBedrooms(_ bedrooms: ListingFilter.Bedrooms) {
        guard filter.bedrooms != bedrooms else { return }
        filter.bedrooms = bedrooms
        invalidateSelectionIfFiltered()
        Task { await reload() }
    }

    /// The rent pill cycles rather than opening a picker: two taps to a common
    /// ceiling beats a modal for a filter this coarse.
    public func cycleRentCeiling() {
        rentCeilingIndex = (rentCeilingIndex + 1) % ListingFilter.rentCeilings.count
        filter.maxRent = ListingFilter.rentCeilings[rentCeilingIndex]
        invalidateSelectionIfFiltered()
        Task { await reload() }
    }

    public func selectNeighborhood(_ neighborhood: String?) {
        filter.neighborhood = neighborhood
        invalidateSelectionIfFiltered()
        Task {
            await reload()
            focusOnCurrentResults()
        }
    }

    public func select(_ listing: Listing) {
        selectedListingID = listing.id
        fly(to: listing.coordinate, span: SanFrancisco.blockSpan)
    }

    public func clearSelection() { selectedListingID = nil }

    public func resetFilters() {
        rentCeilingIndex = 0
        filter = .none
        selectedListingID = nil
        region = SanFrancisco.cityRegion
        regionIntent += 1
        Task { await reload() }
    }

    public func fly(to coordinate: Coordinate, span: MKCoordinateSpan) {
        // Offset north so the selected building sits above the sheet rather
        // than behind it. The sheet occupies the lower quarter of the screen.
        let offsetCenter = CLLocationCoordinate2D(
            latitude: coordinate.latitude - span.latitudeDelta * 0.18,
            longitude: coordinate.longitude
        )
        region = MKCoordinateRegion(center: offsetCenter, span: span)
        regionIntent += 1
    }

    public func flyToUser(_ coordinate: Coordinate) {
        region = MKCoordinateRegion(
            center: coordinate.clLocationCoordinate,
            span: SanFrancisco.blockSpan
        )
        regionIntent += 1
    }

    // MARK: - Internals

    private func reload() async {
        let current = filter
        // Pins stay on screen through a refilter. Dropping to `.loading` would
        // clear the map for a beat, which reads as "no inventory here".
        if loadState.results == nil { loadState = .loading }

        let task = Task { [weak self, repository] in
            do {
                let results = try await repository.listings(matching: current)
                guard !Task.isCancelled else { return }
                self?.loadState = .loaded(results)
                self?.loadError = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                // Only clear the map if there was never anything on it.
                if self?.loadState.results == nil {
                    self?.loadState = .failed("Couldn't load rentals. Tap Try again.")
                } else {
                    self?.loadError = "Couldn't refresh rentals."
                }
            }
        }
        loads.replace(with: task)   // cancels the previous load
        await task.value
    }

    /// A selected building that a new filter excludes has to be dropped, or the
    /// card sheet stays open over a pin that is no longer on the map.
    private func invalidateSelectionIfFiltered() {
        guard let selectedListing else { return }
        if !filter.matches(selectedListing) { selectedListingID = nil }
    }

    private func focusOnCurrentResults() {
        let coordinates = listings.map(\.coordinate)
        guard let enclosing = SanFrancisco.region(enclosing: coordinates) else { return }
        region = enclosing
        regionIntent += 1
    }
}
#endif
