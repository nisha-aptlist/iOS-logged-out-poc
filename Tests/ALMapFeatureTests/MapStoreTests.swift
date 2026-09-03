// Guarded for the same reason `ALMapFeature` itself is: that module is
// iOS-only by its imports (MKAnnotationView, UILabel, UIColor), so on a macOS
// destination its types do not exist and every reference here fails with
// "Cannot find type 'MapStore' in scope".
//
// The source modules were guarded and the TEST target was not, which is a
// gap worth naming: guarding a module is only half the job if anything else
// in the package still references it unconditionally.
#if os(iOS)
import CoreLocation
import MapKit
import Testing
@testable import ALCore
@testable import ALMapFeature

@Suite("Map store")
@MainActor
struct MapStoreTests {

    private func loadedStore() async -> MapStore {
        let store = MapStore(repository: MockListingsRepository(latency: .zero))
        await store.onAppear()
        return store
    }

    @Test("Listings load and the count label reports units")
    func loads() async {
        let store = await loadedStore()
        #expect(!store.listings.isEmpty)
        #expect(store.countLabel.contains("rentals in San Francisco"))
    }

    @Test("A filter that excludes the selected building clears the selection")
    func selectionIsInvalidated() async {
        let store = await loadedStore()

        // A building with no studio inventory, then filter to studios only.
        let noStudio = store.listings.first { !$0.bedroomsAvailable.contains(.studio) }
        let listing = try! #require(noStudio)
        store.select(listing)
        #expect(store.selectedListingID == listing.id)

        store.setBedrooms(.studio)
        // Otherwise the card sheet stays open over a pin no longer on the map.
        #expect(store.selectedListingID == nil)
    }

    @Test("A filter that keeps the selected building keeps the selection")
    func selectionSurvivesCompatibleFilter() async {
        let store = await loadedStore()
        let listing = try! #require(store.listings.first { $0.bedroomsAvailable.contains(.one) })
        store.select(listing)
        store.setBedrooms(.one)
        #expect(store.selectedListingID == listing.id)
    }

    @Test("Selecting a building offsets the camera north of it")
    func cameraClearsTheSheet() async {
        let store = await loadedStore()
        let listing = try! #require(store.listings.first)
        store.select(listing)
        // The sheet occupies the lower quarter, so a centred pin would sit
        // behind it.
        #expect(store.region.center.latitude < listing.coordinate.latitude)
    }

    @Test("The rent pill cycles through every ceiling and back to none")
    func rentCycle() async {
        let store = await loadedStore()
        #expect(store.filter.maxRent == nil)
        for expected in ListingFilter.rentCeilings.dropFirst() {
            store.cycleRentCeiling()
            #expect(store.filter.maxRent == expected)
        }
        store.cycleRentCeiling()
        #expect(store.filter.maxRent == nil, "the cycle must return to no ceiling")
    }

    @Test("Reset clears filters, selection, and the camera together")
    func reset() async {
        let store = await loadedStore()
        store.select(try! #require(store.listings.first))
        store.setBedrooms(.twoPlus)
        store.cycleRentCeiling()

        store.resetFilters()

        #expect(store.filter == .none)
        #expect(store.selectedListingID == nil)
        #expect(store.region.center.latitude == SanFrancisco.cityRegion.center.latitude)
    }
}

@Suite("Region maths")
struct RegionTests {
    @Test("An empty set has no enclosing region")
    func emptyIsNil() {
        #expect(SanFrancisco.region(enclosing: []) == nil)
    }

    @Test("A single point still gets a usable span")
    func singlePointHasSpan() throws {
        let region = try #require(SanFrancisco.region(enclosing: [
            Coordinate(latitude: 37.7749, longitude: -122.4194)
        ]))
        // A zero span resolves to maximum zoom, which lands inside a wall.
        #expect(region.span.latitudeDelta >= 0.01)
        #expect(region.span.longitudeDelta >= 0.01)
    }

    @Test("Several points are enclosed and centred")
    func enclosesAll() throws {
        let region = try #require(SanFrancisco.region(enclosing: [
            Coordinate(latitude: 37.70, longitude: -122.50),
            Coordinate(latitude: 37.80, longitude: -122.40)
        ]))
        #expect(abs(region.center.latitude - 37.75) < 0.0001)
        #expect(abs(region.center.longitude - (-122.45)) < 0.0001)
        #expect(region.span.latitudeDelta > 0.1)
    }
}

@Suite("The list gate")
struct ListGateTests {
    @Test("Exactly three buildings are readable")
    func threeFree() {
        // Reads the domain rule, not the view. Reaching into a @MainActor View
        // from a nonisolated suite warned under Swift 6.
        #expect(FreeSurface.readableRowCount == 3)
    }

    @Test("Rows past the third are locked, at any list length")
    func lockedIndices() {
        for count in [1, 3, 4, 30] {
            let locked = (0 ..< count).filter { $0 >= FreeSurface.readableRowCount }
            #expect(locked.count == max(0, count - 3))
        }
    }
}
#endif
