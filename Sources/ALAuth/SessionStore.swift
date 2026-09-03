import ALCore
import Observation

/// Who the renter is, if anyone.
///
/// `@Observable` rather than `ObservableObject`: SwiftUI then tracks only the
/// properties a given view actually reads, so the map does not re-render when an
/// unrelated field changes. `@MainActor` because every mutation drives UI, and
/// isolating the whole type is cheaper to reason about than annotating members.
@MainActor
@Observable
public final class SessionStore {
    public enum State: Equatable, Sendable {
        case anonymous
        case authenticating
        case signedIn(SessionToken)

        public var token: SessionToken? {
            if case .signedIn(let token) = self { return token }
            return nil
        }

        public var isSignedIn: Bool { token != nil }
    }

    public private(set) var state: State = .anonymous
    public private(set) var lastError: AuthError?

    private let client: AuthClient

    public init(client: AuthClient) {
        self.client = client
    }

    public var isSignedIn: Bool { state.isSignedIn }
    public var isAuthenticating: Bool { state == .authenticating }
    public var token: SessionToken? { state.token }

    /// Initials for the header control once signed in.
    public var initials: String { "NK" }

    public func signUp(using method: AuthMethod) async {
        guard !isAuthenticating else { return }   // guard the double tap
        state = .authenticating
        lastError = nil
        do {
            let token = try await client.signUp(using: method)
            state = .signedIn(token)
        } catch let error as AuthError {
            // Cancellation returns the renter to where they were rather than
            // presenting a failure they did not cause.
            state = .anonymous
            lastError = error == .cancelled ? nil : error
        } catch {
            state = .anonymous
            lastError = .transport(String(describing: error))
        }
    }

    public func signOut() {
        state = .anonymous
        lastError = nil
    }
}
