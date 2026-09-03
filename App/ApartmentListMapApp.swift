import ALAppFeature
import ALAuth
import ALCore
import ALLocation
import SwiftUI

/// Entry point and dependency composition root.
///
/// Every dependency is constructed exactly once, here, and injected downward.
/// No type in the graph reaches for a singleton, which is what lets any feature
/// be previewed or tested against a stub.
@main
struct ApartmentListMapApp: App {
    @State private var coordinator: AppCoordinator

    init() {
        // The demo build drives permissions through a stub. The real system
        // prompt can only be answered once per install, which makes the denial
        // path impossible to demonstrate twice on one device.
        let locationClient: LocationClient = AppConfiguration.usesStubLocation
            ? AppConfiguration.stubLocationClient()
            : SystemLocationClient()

        _coordinator = State(initialValue: .live(
            repository: MockListingsRepository(),
            authClient: MockAuthClient(),
            locationClient: locationClient
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(coordinator: coordinator, loopsLaunch: AppConfiguration.loopsLaunchMoment)
        }
    }
}

/// Build-time switches, read from Info.plist so a demo build needs no code edit.
enum AppConfiguration {
    static var usesStubLocation: Bool { flag("ALUsesStubLocation") }
    static var loopsLaunchMoment: Bool { flag("ALLoopsLaunchMoment") }

    /// Which permission outcome the demo build simulates.
    ///
    /// Without this, the stub always granted when-in-use at full precision, so
    /// three specified surfaces had never been rendered on a device at all: the
    /// recovery sheet and its Settings copy, the pre-denied first launch, and
    /// the "Approximate location" notice. Unit tests covered the transitions;
    /// nobody had looked at the screens.
    ///
    ///     SIMCTL_CHILD_ALStubLocationOutcome=denied     xcrun simctl launch …
    ///     SIMCTL_CHILD_ALStubLocationOutcome=predenied  …
    ///     SIMCTL_CHILD_ALStubLocationOutcome=reduced    …
    ///
    /// `predenied` is the one worth looking at: it simulates a renter who
    /// denied on a previous launch, so the prompt is already spent and the
    /// locate control must go straight to recovery.
    @MainActor
    static func stubLocationClient() -> StubLocationClient {
        switch ProcessInfo.processInfo.environment["ALStubLocationOutcome"]?.lowercased() {
        case "denied":
            return StubLocationClient(promptOutcome: .init(status: .denied, precision: .full))
        case "predenied":
            // Already spent: the explainer must never appear again.
            return StubLocationClient(
                initial: .init(status: .denied, precision: .full),
                promptOutcome: .init(status: .denied, precision: .full)
            )
        case "reduced":
            return StubLocationClient(promptOutcome: .init(status: .whenInUse, precision: .reduced))
        default:
            return StubLocationClient()
        }
    }

    /// Environment first, Info.plist second.
    ///
    /// The env override exists so a UI test or a screenshot run can pin a
    /// screen without rebuilding:
    ///
    ///     xcrun simctl launch --setenv ALLoopsLaunchMoment=0 <device> <bundle>
    ///
    /// Accepts 0/1, true/false, yes/no so it is not fussy about the caller.
    private static func flag(_ key: String) -> Bool {
        if let raw = ProcessInfo.processInfo.environment[key]?.lowercased() {
            return ["1", "true", "yes"].contains(raw)
        }
        return Bundle.main.object(forInfoDictionaryKey: key) as? Bool ?? false
    }
}
