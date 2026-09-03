import Foundation

/// Why gated reads take a token
///
/// The wall is a product decision, but it has to be enforced somewhere that a
/// future screen cannot casually bypass. Putting it in the repository signature
/// means a logged-out view physically cannot obtain `GatedDetails`: there is no
/// overload that omits the token. A `Bool isSignedIn` parameter, or an optional
/// field on `Listing`, would both have left the gate as a convention.
public struct SessionToken: Hashable, Sendable {
    public let value: String
    public init(value: String) { self.value = value }
}

public enum ListingsError: Error, Equatable, Sendable {
    case notFound
    case unauthorized
    case transport(String)
}

public protocol ListingsRepository: Sendable {
    /// Free surface: everything an anonymous renter may see.
    func listings(matching filter: ListingFilter) async throws -> ListingResults

    /// Gated surface. Unobtainable without a session.
    func gatedDetails(for id: UUID, token: SessionToken) async throws -> GatedDetails

    /// Neighborhoods present in inventory, for the search sheet.
    func neighborhoods() async throws -> [String]
}
