import CoreLocation
import Foundation

/// A bedroom count, modelled as a type rather than an `Int` so that "studio"
/// stops being a magic zero scattered across filter and label code.
public enum BedroomCount: Int, Hashable, Sendable, Codable, CaseIterable, Comparable {
    case studio = 0
    case one = 1
    case two = 2
    case threePlus = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var shortLabel: String {
        switch self {
        case .studio: "Studio"
        case .one: "1 bd"
        case .two: "2 bd"
        case .threePlus: "3+ bd"
        }
    }
}

/// The housing stock the photography actually depicts. Drives amenity copy, and
/// exists so a 2019 tower never claims a radiator.
public enum BuildingEra: String, Hashable, Sendable, Codable {
    case victorian, edwardian, midcentury, stucco, prewarLoft, renovated

    public var amenities: [String] {
        switch self {
        case .victorian: ["Pre-1906 building", "Bay windows", "Shared garden", "Laundry on site", "Cats and dogs"]
        case .edwardian: ["1910s building", "Hardwood floors", "Elevator", "Bike room", "Cats only"]
        case .midcentury: ["1960s building", "Courtyard", "Elevator", "Storage lockers", "Cats only"]
        case .stucco: ["1940s building", "Garage parking", "Shared yard", "Laundry on site", "Cats and dogs"]
        case .prewarLoft: ["Pre-war building", "High ceilings", "Freight elevator", "Bike storage", "Cats and dogs"]
        case .renovated: ["Renovated 2019", "Roof deck", "In-unit laundry", "Package room", "Parking available"]
        }
    }
}

/// One rentable unit. Everything here is behind the signup gate.
public struct RentalUnit: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let bedrooms: BedroomCount
    public let bathrooms: Int
    public let squareFeet: Int
    public let rent: Money
    /// Nil means "call for availability", which is different from "available now".
    public let availableOn: Date?

    public init(
        id: String,
        bedrooms: BedroomCount,
        bathrooms: Int,
        squareFeet: Int,
        rent: Money,
        availableOn: Date?
    ) {
        self.id = id
        self.bedrooms = bedrooms
        self.bathrooms = bathrooms
        self.squareFeet = squareFeet
        self.rent = rent
        self.availableOn = availableOn
    }

    public var layoutLabel: String {
        bedrooms == .studio ? "Studio" : "\(bedrooms.rawValue) bd, \(bathrooms) ba"
    }
}

/// A building.
///
/// Deliberately split into what an anonymous renter may see and what only an
/// authenticated one may. `GatedDetails` is a separate type rather than a set of
/// optional fields so the compiler, not a code review, is what stops gated data
/// from reaching a logged-out view.
public struct Listing: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let name: String
    public let neighborhood: String
    public let coordinate: Coordinate
    public let rentRange: RentRange
    public let availableUnitCount: Int
    public let bedroomsAvailable: Set<BedroomCount>
    public let era: BuildingEra
    public let street: String

    public init(
        id: UUID = UUID(),
        name: String,
        neighborhood: String,
        coordinate: Coordinate,
        rentRange: RentRange,
        availableUnitCount: Int,
        bedroomsAvailable: Set<BedroomCount>,
        era: BuildingEra,
        street: String
    ) {
        self.id = id
        self.name = name
        self.neighborhood = neighborhood
        self.coordinate = coordinate
        self.rentRange = rentRange
        self.availableUnitCount = availableUnitCount
        self.bedroomsAvailable = bedroomsAvailable
        self.era = era
        self.street = street
    }

    public var bedroomSummary: String {
        bedroomsAvailable.sorted().map(\.shortLabel).joined(separator: ", ")
    }

    /// "12 units available". For the card, where there is room.
    public var unitCountLabel: String {
        "\(availableUnitCount) unit\(availableUnitCount == 1 ? "" : "s") available"
    }

    /// "12 units". For the list row, where the full label truncates. Still
    /// pluralised, which raw interpolation was not.
    public var unitCountShort: String {
        "\(availableUnitCount) unit\(availableUnitCount == 1 ? "" : "s")"
    }
}

/// Everything the signup wall is selling. Only obtainable through a repository
/// call that requires a session.
public struct GatedDetails: Hashable, Sendable, Codable {
    public let listingID: UUID
    public let streetAddress: String
    public let units: [RentalUnit]
    public let amenities: [String]

    public init(listingID: UUID, streetAddress: String, units: [RentalUnit], amenities: [String]) {
        self.listingID = listingID
        self.streetAddress = streetAddress
        self.units = units
        self.amenities = amenities
    }
}

/// `CLLocationCoordinate2D` is not `Codable` and gained `Sendable` only through
/// a retroactive conformance, so the domain carries its own value type and
/// converts at the MapKit boundary.
public struct Coordinate: Hashable, Sendable, Codable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}
