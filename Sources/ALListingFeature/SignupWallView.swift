// This module is iOS-only by its imports: UIKit, MapKit annotation views,
// UIImage, and iOS-only SwiftUI. The package declares macOS so that the pure
// modules (ALCore, ALAuth, ALLocation) have an honest availability floor —
// without it, Xcode building for "My Mac" fails in ALCore on `Duration` and
// `Task`. Guarding this file means the module compiles to nothing on macOS
// rather than failing to resolve UIKit, so EVERY scheme builds on EVERY
// destination and nobody has to know which one to pick.
#if os(iOS)
import ALAuth
import ALCore
import ALDesignSystem
import AuthenticationServices
import SwiftUI

/// The wall.
///
/// One screen, one specific promise, and the building still visible at the top,
/// so the ask has a subject. A generic "Sign up to continue" over a dimmed map
/// is the version that gets dismissed.
public struct SignupWallView: View {
    private let listing: Listing?
    /// Observed directly rather than passed as snapshots.
    ///
    /// `isAuthenticating` and `lastError` used to arrive as `Bool`/`AuthError?`
    /// read at the call site — which was inside a `.sheet` content closure, so
    /// `@Observable` never re-invoked it when the store changed. The result was
    /// a wall that showed neither the spinner nor the error: a typo'd email got
    /// no feedback at all. Reading the store in this view's own body is what
    /// registers the dependency.
    private let session: SessionStore
    private let onSignUp: (AuthMethod) -> Void
    private let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var email = ""
    @State private var showsEmailField = false

    public init(
        listing: Listing?,
        session: SessionStore,
        onSignUp: @escaping (AuthMethod) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.listing = listing
        self.session = session
        self.onSignUp = onSignUp
        self.onDismiss = onDismiss
    }

    private var isAuthenticating: Bool { session.isAuthenticating }
    private var error: AuthError? { session.lastError }

    public var body: some View {
        // Scrollable because the content grows: revealing the email field adds
        // roughly 78pt, and on a fixed detent the thing that went off the
        // bottom was the Continue button — the conversion action on the
        // conversion screen.
        ScrollView {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(ALColor.surface)
        .disabled(isAuthenticating)
        .overlay {
            if isAuthenticating {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ALColor.surface.opacity(0.6))
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button("Not now", action: onDismiss)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ALColor.inkSecondary)
                    .buttonStyle(.plain)
            }
            .padding(.top, 10)
            .padding(.bottom, 14)

            if let listing { peek(listing) }

            Text(headline)
                .font(ALTypography.display(26))
                .foregroundStyle(ALColor.ink)
                .padding(.bottom, 10)

            promise
                .padding(.bottom, 20)

            appleButton

            Group {
                if showsEmailField {
                    emailField
                } else {
                    Button("Continue with email") { showsEmailField = true }
                        .buttonStyle(ALSecondaryButtonStyle())
                }
            }
            .padding(.top, 10)

            if let error, let message = message(for: error) {
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(ALColor.danger)
                    .padding(.top, 10)
            }

            Text("Prototype. No account is created and nothing is sent.")
                .font(.system(size: 11.5))
                .foregroundStyle(ALColor.inkTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 26)
    }

    private var headline: String {
        guard let listing else { return "See every rental in San Francisco" }
        return "See every unit at \(listing.name)"
    }

    /// Names the unlock, and only what is actually delivered. The full photo
    /// set and the leasing contact were both claimed and neither exists yet.
    private var promise: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Create a free account to unlock:")
                .font(.system(size: 14.5))
                .foregroundStyle(ALColor.inkSecondary)
            ForEach(["Rent for every unit", "Move-in dates", "The exact address"], id: \.self) { item in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ALColor.accent)
                    Text(item)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(ALColor.ink)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func peek(_ listing: Listing) -> some View {
        HStack(spacing: 12) {
            ListingPhotoView(photo: .lead(for: listing.name.stableHash), seed: listing.name.stableHash)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: ALMetrics.thumbRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(listing.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(ALColor.ink)
                    .lineLimit(1)
                Text(listing.rentRange.formatted)
                    .font(ALTypography.mono(11.5))
                    .foregroundStyle(ALColor.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(ALColor.surfaceSunk, in: RoundedRectangle(cornerRadius: ALMetrics.cardRadius, style: .continuous))
        .padding(.bottom, 22)
    }

    /// `SignInWithAppleButton` rather than a hand-drawn Apple mark: the real
    /// control is required by App Review, and it handles its own localization,
    /// height, and corner radius.
    private var appleButton: some View {
        SignInWithAppleButton(.signUp) { request in
            request.requestedScopes = [.email]
        } onCompletion: { result in
            switch result {
            case .success:
                onSignUp(.apple)
            case .failure:
                // A cancelled Apple sheet is not an error worth surfacing.
                break
            }
        }
        // Apple's own control, so it follows the appearance rather than being
        // pinned to .black, which is a near-invisible capsule on #1D2225.
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 52)
        .clipShape(Capsule())
    }

    private var emailField: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label above the field, never a placeholder standing in for one.
            Text("Email")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ALColor.inkSecondary)
            TextField("you@example.com", text: $email)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .submitLabel(.go)
                .onSubmit { onSignUp(.email(email)) }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(ALColor.surfaceSunk, in: RoundedRectangle(cornerRadius: ALMetrics.inputRadius, style: .continuous))

            Button("Continue") { onSignUp(.email(email)) }
                .buttonStyle(ALPrimaryButtonStyle())
                .disabled(email.isEmpty)
        }
    }

    private func message(for error: AuthError) -> String? {
        switch error {
        case .cancelled: nil
        case .invalidEmail: "That does not look like an email address."
        case .transport: "Could not reach the server. Try again in a moment."
        }
    }
}
#endif
