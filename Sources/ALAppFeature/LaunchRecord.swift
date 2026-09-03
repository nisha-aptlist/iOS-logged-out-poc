// This module is iOS-only by its imports: UIKit, MapKit annotation views,
// UIImage, and iOS-only SwiftUI. The package declares macOS so that the pure
// modules (ALCore, ALAuth, ALLocation) have an honest availability floor —
// without it, Xcode building for "My Mac" fails in ALCore on `Duration` and
// `Task`. Guarding this file means the module compiles to nothing on macOS
// rather than failing to resolve UIKit, so EVERY scheme builds on EVERY
// destination and nobody has to know which one to pick.
#if os(iOS)
import Foundation

/// Whether this install has already seen the launch moment.
///
/// A protocol rather than a direct `UserDefaults` read so the demo build and
/// the UI tests can force a first run without deleting the app.
public protocol LaunchRecord: Sendable {
    var hasSeenLaunchMoment: Bool { get nonmutating set }
}

public struct DefaultsLaunchRecord: LaunchRecord {
    private let key = "ALHasSeenLaunchMoment"
    /// The suite name rather than the `UserDefaults` instance: `UserDefaults`
    /// is thread-safe but not `Sendable`, so storing one would force an
    /// `@unchecked` escape hatch for no benefit.
    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public var hasSeenLaunchMoment: Bool {
        get {
            let env = ProcessInfo.processInfo.environment
            // A UI test skips it outright. Without this, whichever test runs
            // first on a fresh simulator pays the full sequence — five answers
            // at 2.2s each, about 11 seconds — before the map appears, which is
            // pure variance in front of every assertion.
            if env["ALSkipLaunchMoment"] == "1" { return true }
            // A demo run can force the moment back on.
            if env["ALAlwaysShowLaunchMoment"] == "1" { return false }
            return defaults.bool(forKey: key)
        }
        nonmutating set { defaults.set(newValue, forKey: key) }
    }
}

/// Never records, so the moment always plays. Used by previews.
public struct EphemeralLaunchRecord: LaunchRecord {
    public init() {}
    public var hasSeenLaunchMoment: Bool {
        get { false }
        nonmutating set {}
    }
}

extension LaunchRecord where Self == DefaultsLaunchRecord {
    public static var standard: DefaultsLaunchRecord { DefaultsLaunchRecord() }
}
#endif
