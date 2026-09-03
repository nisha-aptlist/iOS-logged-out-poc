import ALCore
import CoreLocation
import Foundation

/// The authorization states that matter to this product, which is not the same
/// set as `CLAuthorizationStatus`.
///
/// Two distinctions the raw enum blurs and this one does not:
///
/// 1. `.restricted` and `.denied` are different causes with an identical remedy
///    (Settings), so they collapse into `.denied` for the UI.
/// 2. Precision is a second axis, not a state. Since iOS 14 a renter can grant
///    location while withholding precise location, which yields a fuzzed circle
///    of a few kilometres. That is adequate to centre a map and useless for
///    "12 minutes from here", so it is carried alongside, not folded in.
public struct LocationAuthorization: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case notDetermined
        case denied
        case whenInUse
        case always
    }

    public enum Precision: Equatable, Sendable {
        case full
        case reduced
    }

    public let status: Status
    public let precision: Precision

    public init(status: Status, precision: Precision) {
        self.status = status
        self.precision = precision
    }

    public static let unknown = LocationAuthorization(status: .notDetermined, precision: .full)

    public var isAuthorized: Bool { status == .whenInUse || status == .always }

    /// True only while the system prompt is still available to us. After a
    /// denial `requestWhenInUseAuthorization()` is a silent no-op for the life
    /// of the install, which is the single most important fact about this flow.
    public var canPrompt: Bool { status == .notDetermined }

    init(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .notDetermined:
            status = .notDetermined
        case .restricted, .denied:
            status = .denied
        case .authorizedWhenInUse:
            status = .whenInUse
        case .authorizedAlways:
            status = .always
        @unknown default:
            status = .denied
        }
        precision = manager.accuracyAuthorization == .reducedAccuracy ? .reduced : .full
    }
}

public protocol LocationClient: Sendable {
    /// Current authorization, read without prompting.
    func currentAuthorization() async -> LocationAuthorization

    /// Emits on every authorization change for the lifetime of the stream.
    func authorizationUpdates() -> AsyncStream<LocationAuthorization>

    /// Shows the system prompt if, and only if, it is still available.
    func requestWhenInUseAuthorization() async

    /// One coordinate, or nil if unauthorized or unavailable.
    ///
    /// Returns the domain `Coordinate`, not `CLLocationCoordinate2D`: Apple's
    /// struct is neither `Equatable` nor `Sendable`, so it cannot be observed
    /// with `.onChange` or held in `@Observable` state.
    func currentCoordinate() async -> Coordinate?
}
