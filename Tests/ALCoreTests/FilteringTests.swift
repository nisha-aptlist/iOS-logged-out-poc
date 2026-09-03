import Testing
@testable import ALCore

/// Swift Testing rather than XCTest: parameterised cases and plain `#expect`
/// make the filter matrix readable, which matters because this is where the
/// count in the chrome comes from.
@Suite("Listing filtering")
struct FilteringTests {

    private func listing(
        low: Int, high: Int, beds: Set<BedroomCount>, hood: String = "Mission", units: Int = 4
    ) -> Listing {
        Listing(
            name: "Test", neighborhood: hood,
            coordinate: Coordinate(latitude: 37.75, longitude: -122.42),
            rentRange: RentRange(low: Money(dollars: low), high: Money(dollars: high)),
            availableUnitCount: units, bedroomsAvailable: beds, era: .victorian, street: "Test St"
        )
    }

    @Test("An empty filter matches everything")
    func emptyFilterMatchesAll() {
        let filter = ListingFilter.none
        #expect(filter.matches(listing(low: 1_000, high: 9_000, beds: [.studio])))
        #expect(!filter.isActive)
    }

    @Test("The rent ceiling tests the floor of the range, not the top")
    func rentCeilingUsesRangeFloor() {
        // A building from $2,400 to $6,000 is reachable on a $3,000 budget: the
        // cheap unit qualifies. Testing `high` would wrongly exclude it, which
        // would hide most large buildings from every filtered search.
        let filter = ListingFilter(maxRent: Money(dollars: 3_000))
        #expect(filter.matches(listing(low: 2_400, high: 6_000, beds: [.one])))
        #expect(!filter.matches(listing(low: 3_400, high: 3_600, beds: [.one])))
    }

    @Test("Two plus matches three bedroom inventory")
    func twoPlusIsInclusive() {
        let filter = ListingFilter(bedrooms: .twoPlus)
        #expect(filter.matches(listing(low: 4_000, high: 5_000, beds: [.threePlus])))
        #expect(filter.matches(listing(low: 4_000, high: 5_000, beds: [.two])))
        #expect(!filter.matches(listing(low: 2_000, high: 2_400, beds: [.studio, .one])))
    }

    @Test("Neighborhood is an exact match")
    func neighborhoodFilter() {
        let filter = ListingFilter(neighborhood: "SoMa")
        #expect(!filter.matches(listing(low: 2_000, high: 3_000, beds: [.one], hood: "Mission")))
        #expect(filter.matches(listing(low: 2_000, high: 3_000, beds: [.one], hood: "SoMa")))
    }

    @Test("The count reports units, not buildings")
    func countsAreUnits() {
        let results = ListingResults(
            listings: [
                listing(low: 2_000, high: 3_000, beds: [.one], units: 12),
                listing(low: 2_000, high: 3_000, beds: [.one], units: 8)
            ],
            place: "San Francisco"
        )
        #expect(results.buildingCount == 2)
        #expect(results.rentalCount == 20)
        #expect(results.countLabel == "20 rentals in San Francisco")
    }

    @Test("A single rental is not pluralised")
    func singularCount() {
        let results = ListingResults(
            listings: [listing(low: 2_000, high: 2_000, beds: [.studio], units: 1)],
            place: "Mission"
        )
        #expect(results.countLabel == "1 rental in Mission")
    }
}

@Suite("Money formatting")
struct MoneyTests {
    @Test("Whole dollars, no cents, grouped")
    func whole() {
        #expect(Money(dollars: 2_395).formatted == "$2,395")
    }

    @Test("Pins abbreviate and drop a trailing zero")
    func abbreviation() {
        #expect(Money(dollars: 2_400).abbreviated == "$2.4k")
        #expect(Money(dollars: 3_000).abbreviated == "$3k")
        #expect(Money(dollars: 950).abbreviated == "$950")
    }

    /// `from $X` is a lower-bound promise, so the label must never sit BELOW
    /// the true floor. Above is pessimistic and safe; below advertises a price
    /// the building cannot honour.
    @Test("Abbreviation rounds up, so a pin can never advertise an unattainable floor",
          arguments: [
            (1_950, "$2k"), (2_050, "$2.1k"), (2_950, "$3k"),
            (2_395, "$2.4k"), (3_000, "$3k"), (2_999, "$3k")
          ])
    func abbreviationNeverUnderstates(dollars: Int, expected: String) {
        #expect(Money(dollars: dollars).abbreviated == expected)
    }

    @Test("No inventory floor is advertised below its true value")
    func noInventoryFloorUnderstated() async throws {
        let repository = MockListingsRepository(latency: .zero)
        let results = try await repository.listings(matching: .none)

        for listing in results.listings {
            let label = listing.rentRange.low.abbreviated       // e.g. "$3k"
            let digits = label.dropFirst().replacingOccurrences(of: "k", with: "")
            let shown = Int((Double(digits) ?? 0) * 1_000)
            #expect(
                shown >= listing.rentRange.low.dollars,
                "\(listing.name): pin says \(label), below its true floor of \(listing.rentRange.low.formatted) — a price nothing in the building meets"
            )
        }
    }

    @Test("A reversed range is corrected rather than trapping")
    func reversedRange() {
        let range = RentRange(low: Money(dollars: 5_000), high: Money(dollars: 2_000))
        #expect(range.low == Money(dollars: 2_000))
        #expect(range.high == Money(dollars: 5_000))
    }

    @Test("Ranges are spelled out for VoiceOver")
    func rangeReadsAloud() {
        let range = RentRange(low: Money(dollars: 2_395), high: Money(dollars: 4_150))
        #expect(range.formatted == "$2,395 to $4,150")
        // "$2.4k" for a $2,395 floor is correct, and this assertion was right
        // all along: the label may sit ABOVE the true floor, never below.
        #expect(range.fromFormatted == "from $2.4k")
    }
}

@Suite("Mock inventory")
struct InventoryTests {
    @Test("Gated details require a token")
    func gatingIsEnforced() async throws {
        let repository = MockListingsRepository(latency: .zero)
        let results = try await repository.listings(matching: .none)
        let first = try #require(results.listings.first)

        await #expect(throws: ListingsError.unauthorized) {
            try await repository.gatedDetails(for: first.id, token: SessionToken(value: ""))
        }

        let details = try await repository.gatedDetails(for: first.id, token: SessionToken(value: "ok"))
        #expect(details.listingID == first.id)
        #expect(!details.units.isEmpty)
    }

    @Test("Generated units are stable across calls")
    func unitsAreDeterministic() async throws {
        let repository = MockListingsRepository(latency: .zero)
        let results = try await repository.listings(matching: .none)
        let first = try #require(results.listings.first)
        let token = SessionToken(value: "ok")

        let a = try await repository.gatedDetails(for: first.id, token: token)
        let b = try await repository.gatedDetails(for: first.id, token: token)
        #expect(a == b)
    }

    @Test("Every unit's rent falls inside its building's advertised range")
    func rentsRespectTheRange() async throws {
        let repository = MockListingsRepository(latency: .zero)
        let results = try await repository.listings(matching: .none)
        let token = SessionToken(value: "ok")

        for listing in results.listings {
            let details = try await repository.gatedDetails(for: listing.id, token: token)
            for unit in details.units {
                #expect(unit.rent >= listing.rentRange.low, "\(listing.name) unit under range")
                #expect(unit.rent <= listing.rentRange.high, "\(listing.name) unit over range")
            }
        }
    }
}


@Suite("The advertised range must be reachable")
struct TeaserMatchesRewardTests {

    /// The defect this exists to prevent: the map advertised `from $2.4k` and
    /// the cheapest unit behind the gate was $2,575. Measured across the whole
    /// inventory, 24 of 30 buildings had a cheapest unit ABOVE their advertised
    /// floor. The teaser contradicting its own payoff is the one thing this
    /// product cannot afford, so it is now an invariant rather than a hope.
    @Test("Every building's advertised floor is an actual, rentable unit")
    func floorIsReachable() async throws {
        let repository = MockListingsRepository(latency: .zero)
        let results = try await repository.listings(matching: .none)
        let token = SessionToken(value: "ok")
        #expect(results.listings.count == 30)

        for listing in results.listings {
            let details = try await repository.gatedDetails(for: listing.id, token: token)
            let cheapest = try #require(details.units.map(\.rent).min())
            let dearest = try #require(details.units.map(\.rent).max())
            #expect(
                cheapest == listing.rentRange.low,
                "\(listing.name) advertises from \(listing.rentRange.low.formatted) but its cheapest unit is \(cheapest.formatted)"
            )
            #expect(
                dearest == listing.rentRange.high,
                "\(listing.name) advertises up to \(listing.rentRange.high.formatted) but its dearest unit is \(dearest.formatted)"
            )
        }
    }

    @Test("Rents round to the nearest $25, which the old code only claimed")
    func rentsAreOnQuarterBoundaries() async throws {
        let repository = MockListingsRepository(latency: .zero)
        let results = try await repository.listings(matching: .none)
        let token = SessionToken(value: "ok")
        for listing in results.listings {
            let details = try await repository.gatedDetails(for: listing.id, token: token)
            for unit in details.units {
                #expect(unit.rent.cents % 2_500 == 0, "\(listing.name) unit \(unit.id) is not on a $25 boundary")
            }
        }
    }
}
