import Foundation

/// The two filters the logged-out map exposes. A value type, so the map store
/// can diff it and the tests can drive it without any UI.
public struct ListingFilter: Hashable, Sendable {
    public enum Bedrooms: Hashable, Sendable, CaseIterable {
        case any, studio, one, twoPlus

        public var label: String {
            switch self {
            case .any: "Any beds"
            case .studio: "Studio"
            case .one: "1 bd"
            case .twoPlus: "2+ bd"
            }
        }
    }

    /// Nil is "no ceiling". The cycle order matches the pill's tap order.
    public static let rentCeilings: [Money?] = [
        nil, Money(dollars: 3_000), Money(dollars: 4_000), Money(dollars: 5_000)
    ]

    public var bedrooms: Bedrooms
    public var maxRent: Money?
    /// Nil is the whole city.
    public var neighborhood: String?

    public init(bedrooms: Bedrooms = .any, maxRent: Money? = nil, neighborhood: String? = nil) {
        self.bedrooms = bedrooms
        self.maxRent = maxRent
        self.neighborhood = neighborhood
    }

    public static let none = ListingFilter()

    public var isActive: Bool { self != .none }

    public var rentPillLabel: String {
        guard let maxRent else { return "Max rent" }
        return "Under \(maxRent.abbreviated)"
    }

    public var placeLabel: String { neighborhood ?? "San Francisco" }

    public func matches(_ listing: Listing) -> Bool {
        if let neighborhood, listing.neighborhood != neighborhood { return false }

        // The rent ceiling tests the floor of the range: a building whose
        // cheapest unit is over budget is out, even if a pricier one is listed.
        if let maxRent, listing.rentRange.low > maxRent { return false }

        switch bedrooms {
        case .any:
            return true
        case .studio:
            return listing.bedroomsAvailable.contains(.studio)
        case .one:
            return listing.bedroomsAvailable.contains(.one)
        case .twoPlus:
            return listing.bedroomsAvailable.contains { $0 >= .two }
        }
    }
}

/// How much of the inventory an anonymous renter may read.
///
/// Lives in the domain, not on the view. It is a product rule, a test should not
/// have to reach into a `View` to read it, and doing so warned under Swift 6
/// because a `View` is `@MainActor` by inference.
public enum FreeSurface {
    public static let readableRowCount = 3
}

/// A filtered slice of inventory plus the counts the chrome reports.
///
/// The count is a sum of *units*, not buildings, because "420 rentals" is what a
/// renter is told and 30 buildings is what they can tap. Conflating the two is
/// how a count pill ends up lying.
public struct ListingResults: Sendable, Equatable {
    public let listings: [Listing]
    public let place: String

    public init(listings: [Listing], place: String) {
        self.listings = listings
        self.place = place
    }

    public var buildingCount: Int { listings.count }
    public var rentalCount: Int { listings.reduce(0) { $0 + $1.availableUnitCount } }
    public var isEmpty: Bool { listings.isEmpty }

    public var countLabel: String {
        "\(rentalCount.formatted(.number)) rental\(rentalCount == 1 ? "" : "s") in \(place)"
    }
}
