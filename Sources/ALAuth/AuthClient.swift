import ALCore
import Foundation

public enum AuthMethod: Hashable, Sendable {
    case apple
    case email(String)

    public var analyticsName: String {
        switch self {
        case .apple: "apple"
        case .email: "email"
        }
    }
}

public enum AuthError: Error, Equatable, Sendable {
    case cancelled
    case invalidEmail
    case transport(String)
}

public protocol AuthClient: Sendable {
    /// Returns a token on success. Throwing `.cancelled` is a normal outcome,
    /// not an error state to surface: a renter dismissing Apple's sheet should
    /// land back on the card, not on an alert.
    func signUp(using method: AuthMethod) async throws -> SessionToken
}

/// Stands in for Sign in with Apple and the email flow.
public struct MockAuthClient: AuthClient {
    private let latency: Duration
    public init(latency: Duration = .milliseconds(450)) { self.latency = latency }

    public func signUp(using method: AuthMethod) async throws -> SessionToken {
        try await Task.sleep(for: latency)
        if case .email(let address) = method, !address.contains("@") {
            throw AuthError.invalidEmail
        }
        return SessionToken(value: "mock-\(method.analyticsName)-\(UUID().uuidString)")
    }
}
