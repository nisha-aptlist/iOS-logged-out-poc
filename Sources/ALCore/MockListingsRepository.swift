import Foundation

/// Hand-authored San Francisco inventory.
///
/// Mock, and labelled as such everywhere it surfaces. Rents and neighborhood
/// placement are plausible for the market; none of it came from production.
public actor MockListingsRepository: ListingsRepository {

    /// Simulated latency, so the UI has to have a loading state rather than
    /// getting data synchronously and hiding the fact that it never will.
    private let latency: Duration

    public init(latency: Duration = .milliseconds(220)) {
        self.latency = latency
    }

    public func listings(matching filter: ListingFilter) async throws -> ListingResults {
        try await Task.sleep(for: latency)
        let matched = Self.inventory.filter(filter.matches)
        return ListingResults(listings: matched, place: filter.placeLabel)
    }

    public func gatedDetails(for id: UUID, token: SessionToken) async throws -> GatedDetails {
        try await Task.sleep(for: latency)
        guard !token.value.isEmpty else { throw ListingsError.unauthorized }
        guard let listing = Self.inventory.first(where: { $0.id == id }),
              let details = Self.details(for: listing) else {
            throw ListingsError.notFound
        }
        return details
    }

    public func neighborhoods() async throws -> [String] {
        try await Task.sleep(for: latency)
        return Set(Self.inventory.map(\.neighborhood)).sorted()
    }

    // MARK: - Inventory

    /// Authored input. `targetLow` and `targetHigh` are the intended envelope,
    /// not the advertised range: the advertised range is derived from whatever
    /// units get generated inside it.
    struct Spec: Sendable {
        let name: String
        let neighborhood: String
        let latitude: Double
        let longitude: Double
        let targetLow: Money
        let targetHigh: Money
        let unitCount: Int
        let bedrooms: Set<BedroomCount>
        let era: BuildingEra
        let street: String

        /// Deterministic, so selection survives a relaunch and tests reproduce.
        var id: UUID { UUID(uuidString: MockListingsRepository.stableUUID(for: name)) ?? UUID() }
    }

    private static func make(
        _ name: String, _ hood: String, _ lat: Double, _ lng: Double,
        _ low: Int, _ high: Int, _ units: Int,
        _ beds: Set<BedroomCount>, _ era: BuildingEra, _ street: String
    ) -> Spec {
        Spec(
            name: name, neighborhood: hood, latitude: lat, longitude: lng,
            targetLow: Money(dollars: low), targetHigh: Money(dollars: high),
            unitCount: units, bedrooms: beds, era: era, street: street
        )
    }

    /// A name hashed into a v4-shaped UUID string. Stable across launches and
    /// across processes, which `hashValue` is not.
    static func stableUUID(for name: String) -> String {
        var h1: UInt64 = 0xcbf29ce484222325
        for byte in Array(name.utf8) {
            h1 = (h1 ^ UInt64(byte)) &* 0x100000001b3
        }
        var h2 = h1 &* 0x9E3779B97F4A7C15
        h2 ^= h2 >> 29
        let hex = String(format: "%016lx%016lx", h1, h2)
        let s = Array(hex)
        return "\(String(s[0..<8]))-\(String(s[8..<12]))-4\(String(s[13..<16]))-a\(String(s[17..<20]))-\(String(s[20..<32]))"
    }

    static let specs: [Spec] = [
        make("Vaquero Flats", "Mission", 37.7583, -122.4212, 2395, 4150, 12, [.studio, .one, .two], .victorian, "Valencia St"),
        make("The Duboce", "Duboce Triangle", 37.7692, -122.4331, 2650, 4400, 8, [.one, .two], .edwardian, "Duboce Ave"),
        make("388 Fulton", "Hayes Valley", 37.7768, -122.4243, 2950, 5600, 21, [.studio, .one, .two], .renovated, "Fulton St"),
        make("Bartlett Row", "Mission", 37.7517, -122.4184, 2250, 3600, 6, [.studio, .one], .victorian, "Bartlett St"),
        make("The Corbett", "Castro", 37.7614, -122.4386, 2500, 4250, 9, [.one, .two], .midcentury, "Corbett Ave"),
        make("Lyon & Green", "Cow Hollow", 37.7968, -122.4372, 3400, 6200, 14, [.one, .two], .edwardian, "Green St"),
        make("1188 Mission", "SoMa", 37.7772, -122.4145, 2150, 3950, 38, [.studio, .one, .two], .renovated, "Mission St"),
        make("Cypress & 19th", "Mission", 37.7601, -122.4213, 2400, 3850, 7, [.studio, .one], .stucco, "19th St"),
        make("The Alameda", "Potrero Hill", 37.7593, -122.4008, 2700, 4600, 16, [.one, .two], .renovated, "De Haro St"),
        make("Fell Street Flats", "NoPa", 37.7739, -122.4381, 2550, 4100, 10, [.one, .two], .victorian, "Fell St"),
        make("Irving & Ninth", "Inner Sunset", 37.7638, -122.4677, 2300, 3700, 11, [.studio, .one, .two], .stucco, "Irving St"),
        make("The Presidio Gate", "Inner Richmond", 37.7829, -122.4641, 2450, 3900, 13, [.one, .two], .edwardian, "Clement St"),
        make("Chestnut & Pierce", "Marina", 37.8017, -122.4362, 3200, 5400, 12, [.one, .two], .stucco, "Chestnut St"),
        make("Taylor House", "Nob Hill", 37.7924, -122.4127, 2400, 4200, 24, [.studio, .one], .edwardian, "Taylor St"),
        make("Green & Hyde", "Russian Hill", 37.8006, -122.4183, 2800, 4900, 15, [.studio, .one, .two], .edwardian, "Green St"),
        make("Dogpatch Ironworks", "Dogpatch", 37.7601, -122.3901, 2600, 4700, 27, [.studio, .one, .two], .prewarLoft, "Third St"),
        make("Cortland Yard", "Bernal Heights", 37.7392, -122.4163, 2200, 3550, 6, [.one, .two], .victorian, "Cortland Ave"),
        make("24th & Church", "Noe Valley", 37.7513, -122.4287, 2750, 4800, 9, [.one, .two], .victorian, "Church St"),
        make("The Panhandle", "NoPa", 37.7727, -122.4448, 2500, 3950, 8, [.one, .two], .victorian, "Oak St"),
        make("Cole & Carl", "Cole Valley", 37.7669, -122.4497, 2650, 4300, 7, [.one, .two], .edwardian, "Cole St"),
        make("Mission Bay Commons", "Mission Bay", 37.7702, -122.3921, 2850, 5200, 42, [.studio, .one, .two], .renovated, "Berry St"),
        make("Kearny & Vallejo", "North Beach", 37.7987, -122.4062, 2350, 3900, 10, [.studio, .one], .edwardian, "Vallejo St"),
        make("Fillmore & Bush", "Japantown", 37.7861, -122.4331, 2500, 4150, 18, [.studio, .one, .two], .midcentury, "Bush St"),
        make("The Broderick", "Pacific Heights", 37.7906, -122.4381, 3300, 6400, 11, [.one, .two], .victorian, "Broderick St"),
        make("Diamond & Bosworth", "Glen Park", 37.7341, -122.4337, 2300, 3700, 5, [.one, .two], .stucco, "Diamond St"),
        make("Mission & Persia", "Excelsior", 37.7247, -122.4262, 1950, 3100, 9, [.studio, .one, .two], .stucco, "Mission St"),
        make("Portola Terrace", "Portola", 37.7256, -122.4074, 2050, 3250, 7, [.one, .two], .stucco, "San Bruno Ave"),
        make("Judah & 46th", "Outer Sunset", 37.7602, -122.5014, 2100, 3400, 8, [.studio, .one, .two], .stucco, "Judah St"),
        make("Folsom & Sixth", "SoMa", 37.7787, -122.4062, 2050, 3450, 31, [.studio, .one], .prewarLoft, "Folsom St"),
        make("West Portal Mews", "West Portal", 37.7402, -122.4661, 2400, 3800, 6, [.one, .two], .midcentury, "Ulloa St")
    ]

    // MARK: - Gated details

    /// Units first, then the advertised range derived from them.
    ///
    /// The dependency used to run the other way: an authored `rentRange` was the
    /// teaser and units were generated inside it, with a `0.78` cap and a
    /// flooring rounding step. Measured across all thirty buildings, 24 had a
    /// cheapest unit ABOVE the advertised floor (worst case $350) and 29 had no
    /// unit within $50 of the advertised ceiling. So a pin read `from $2.4k` and
    /// the cheapest unit behind the gate was $2,575.
    ///
    /// That is the gate's payoff contradicting its own teaser, on the one screen
    /// where trust is being established, and it is the single thing this product
    /// cannot afford. Deriving the range from the units makes the contradiction
    /// unrepresentable rather than merely absent.
    private static let built: (listings: [Listing], details: [UUID: GatedDetails]) = {
        var listings: [Listing] = []
        var details: [UUID: GatedDetails] = [:]

        for spec in specs {
            let units = generateUnits(for: spec)
            guard let low = units.map(\.rent).min(), let high = units.map(\.rent).max() else {
                continue
            }
            let listing = Listing(
                id: spec.id,
                name: spec.name,
                neighborhood: spec.neighborhood,
                coordinate: Coordinate(latitude: spec.latitude, longitude: spec.longitude),
                rentRange: RentRange(low: low, high: high),
                availableUnitCount: spec.unitCount,
                bedroomsAvailable: spec.bedrooms,
                era: spec.era,
                street: spec.street
            )
            listings.append(listing)
            details[listing.id] = GatedDetails(
                listingID: listing.id,
                streetAddress: "\(1_200 + abs(spec.name.stableHash % 800)) \(spec.street), San Francisco, CA",
                units: units,
                amenities: spec.era.amenities
            )
        }
        return (listings, details)
    }()

    static var inventory: [Listing] { built.listings }

    private static func details(for listing: Listing) -> GatedDetails? {
        built.details[listing.id]
    }

    /// A fixed anchor for generated move-in dates.
    ///
    /// These were derived from `.now`, which made two calls for the same
    /// building unequal by a sub-second amount that `description` hid. Mock data
    /// has to be a pure function of the building, or the detail screen
    /// reshuffles on every open.
    private static let availabilityAnchor = Date(timeIntervalSince1970: 1_788_000_000)

    private static func generateUnits(for spec: Spec) -> [RentalUnit] {
        var generator = SplitMix64(seed: spec.name.stableHash)
        // Never empty: `bedOptions[index % 0]` divides by zero and traps.
        let bedOptions = spec.bedrooms.isEmpty ? [BedroomCount.one] : spec.bedrooms.sorted()
        let count = max(1, min(spec.unitCount, 5))
        let floor = spec.targetLow.cents
        let spread = spec.targetHigh.cents - floor

        let units: [RentalUnit] = (0 ..< count).map { index in
            let bedrooms = bedOptions[index % bedOptions.count]
            // Spans the full envelope: the cheapest unit sits exactly on the
            // floor and the dearest exactly on the ceiling, so nothing the map
            // advertises is unreachable behind the gate.
            let position = count > 1 ? Double(index) / Double(count - 1) : 0
            let jitter = count > 2 && index > 0 && index < count - 1
                ? (generator.nextUnit() - 0.5) * 0.06
                : 0
            let raw = Double(floor) + Double(spread) * min(1, max(0, position + jitter))
            // Rounds to the nearest $25 rather than flooring, which is what the
            // old comment claimed and the old code did not do.
            let cents = Int((raw / 2_500).rounded()) * 2_500

            let baseSquareFeet: Int
            switch bedrooms {
            case .studio: baseSquareFeet = 480
            case .one: baseSquareFeet = 690
            case .two: baseSquareFeet = 1_010
            case .threePlus: baseSquareFeet = 1_320
            }

            return RentalUnit(
                id: "\(2 + index)0\(1 + index)",
                bedrooms: bedrooms,
                bathrooms: bedrooms >= .two ? 2 : 1,
                squareFeet: baseSquareFeet + Int(generator.nextUnit() * 180),
                rent: Money(cents: cents),
                availableOn: Calendar(identifier: .gregorian)
                    .date(byAdding: .day, value: 9 + index * 14, to: availabilityAnchor)
            )
        }
        return units.sorted { $0.rent < $1.rent }
    }
}

// MARK: - Deterministic randomness

/// Seeded PRNG so generated mock units are identical on every launch. A stdlib
/// `SystemRandomNumberGenerator` would make the unit table shuffle every time
/// the detail screen opened, which reads as a bug.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: Int) { self.state = UInt64(bitPattern: Int64(seed)) }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextUnit() -> Double { Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0) }
}

extension String {
    /// FNV-1a. `hashValue` is seeded per process and therefore useless for
    /// anything that has to be stable across launches, which is exactly what a
    /// per-building photo rotation and crop anchor need.
    public var stableHash: Int {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in Array(utf8) { h = (h ^ UInt64(byte)) &* 0x100000001b3 }
        return Int(bitPattern: UInt(truncatingIfNeeded: h))
    }
}
