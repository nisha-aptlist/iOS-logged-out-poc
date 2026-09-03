import ALCore
import CoreLocation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// The permission flow as an explicit state machine.
///
/// The shape exists because of one immovable platform fact: the system prompt
/// fires at most once per install. Everything here follows from that.
///
///                       ┌──────────── tap locate ───────────┐
///                       ▼                                   │
///     .idle ──▶ .explaining ──▶ .systemPrompt ──▶ .authorized (fly to me)
///                   │                   │
///              "Not now"           "Don't Allow"
///                   │                   ▼
///                   └──▶ .idle      .denied ──▶ .recovering ──▶ Settings
///
/// `.explaining` is ours and is the only reason a denial is recoverable at all:
/// it converts a likely no into a not-yet while the prompt is still spendable.
@MainActor
@Observable
public final class LocationPermissionStore {
    public enum Step: Equatable, Sendable {
        case idle
        /// Our pre-permission sheet.
        case explaining
        /// The system alert is on screen. Not ours to draw.
        case systemPrompt
        /// Settings-recovery sheet, the only route back after a denial.
        case recovering
    }

    public private(set) var step: Step = .idle
    public private(set) var authorization: LocationAuthorization = .unknown
    public private(set) var coordinate: Coordinate?
    /// Append-only log of explicit recentre intents. Observers watch the count,
    /// so a repeated tap at the same location still moves the camera.
    public private(set) var recenterRequests: [Coordinate] = []

    private let client: LocationClient
    /// Boxed for the same reason as `MapStore.loads`: `deinit` is nonisolated.
    private let observation = TaskBox()
    /// Serialises locate taps: `replace(with:)` cancels the previous one, so a
    /// double tap cannot land a stale `.explaining` over a `.systemPrompt`.
    private let locateWork = TaskBox()

    public init(client: LocationClient) {
        self.client = client
    }

    deinit {
        observation.cancel()
        locateWork.cancel()
    }

    public func start() {
        guard observation.isIdle else { return }   // idempotent: views call this in .task
        // `client` is Sendable, so holding it costs nothing. `self` is
        // re-checked per iteration and held across no suspension, so between
        // yields nothing retains the store: deinit runs, cancel() fires, the
        // stream terminates, and onTermination sheds the observer.
        //
        // The previous `guard let self` defeated the `[weak self]` entirely and
        // leaked the store for the life of the process.
        observation.replace(with: Task { [weak self] in
            guard let client = self?.client else { return }
            // Seeded by the client, so the first value is the real current state
            // rather than an assumed `.notDetermined`.
            for await value in client.authorizationUpdates() {
                guard let self else { return }
                await self.apply(value)
            }
        })
    }

    private func apply(_ value: LocationAuthorization) async {
        let wasAuthorized = authorization.isAuthorized
        authorization = value

        if value.isAuthorized {
            if step == .systemPrompt || step == .explaining { step = .idle }
            if !wasAuthorized { coordinate = await client.currentCoordinate() }
        } else if value.status == .denied {
            coordinate = nil
            // A denial closes the system prompt. Do not immediately push the
            // recovery sheet: two sheets back to back reads as nagging. The
            // next deliberate tap opens it.
            if step == .systemPrompt { step = .idle }
        }
    }

    // MARK: - Intents

    /// The locate control. One entry point, three outcomes, decided by state
    /// rather than by the view.
    ///
    /// Reads the client rather than the cached `authorization`: the stream seeds
    /// asynchronously, so a tap that lands before the first yield would still
    /// see `.notDetermined`. On a device where the renter denied on a previous
    /// launch, that showed an explainer for a prompt that can never fire again.
    public func locateTapped() {
        locateWork.replace(with: Task {
            let current = await client.currentAuthorization()
            authorization = current

            switch current.status {
            case .notDetermined:
                step = .explaining
            case .denied:
                step = .recovering
            case .whenInUse, .always:
                step = .idle
                coordinate = await client.currentCoordinate()
                // A stationary renter yields the same Coordinate, so an
                // `.onChange` observer never fires. Recentring is an intent.
                if let coordinate { recenterRequests.append(coordinate) }
            }
        })
    }

    public func explainerAccepted() {
        step = .systemPrompt
        Task { await client.requestWhenInUseAuthorization() }
    }

    public func explainerDismissed() {
        // Still `.notDetermined`, so the prompt remains spendable later. This is
        // the whole point of the explainer.
        step = .idle
    }

    public func recoveryDismissed() { step = .idle }

    /// Abandons an in-flight locate decision.
    ///
    /// `locateTapped()` resolves the client asynchronously, so between the tap
    /// and the decision the chrome is still live. Without this, tapping locate
    /// and then search left a pending Task that would later set
    /// `step = .explaining` underneath a search sheet the renter had opened.
    public func cancelPendingLocate() {
        locateWork.cancel()
        if step == .explaining || step == .recovering { step = .idle }
    }

    /// Deep-links to this app's own Settings page, which after a denial is the
    /// only route back.
    ///
    /// Guarded rather than importing UIKit unconditionally: this module is
    /// otherwise a pure state machine over CoreLocation, and one call to
    /// `UIApplication` made the whole thing unbuildable for macOS as soon as
    /// the package declared that platform.
    public func openSettings() {
        step = .idle
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    /// Shown under the locate control when precision was withheld. Distance
    /// claims are suppressed in that case rather than quietly wrong.
    public var showsReducedPrecisionNotice: Bool {
        authorization.isAuthorized && authorization.precision == .reduced
    }
}
