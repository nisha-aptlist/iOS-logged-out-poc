import Foundation

/// Why this exists at all
///
/// The stated purpose of this prototype is to settle where the signup gate
/// belongs. Every open question about it is empirical: how many asks, whether
/// the list should be readable, whether the launch moment costs retention,
/// whether the card gate converts better than the list gate. A prototype that
/// cannot measure its own central hypothesis is a demo, not an experiment.
///
/// The one field that does the most work is `ordinal` on `wallShown` and
/// `wallDismissed`: the count of walls a renter has already seen this session.
/// It answers the whole "how many asks" question on its own, it is trivial now,
/// and it cannot be reconstructed after the fact from anything else.
public struct AnalyticsEvent: Sendable, Equatable {
    public let name: String
    public let properties: [String: String]

    public init(name: String, properties: [String: String] = [:]) {
        self.name = name
        self.properties = properties
    }
}

/// Where a signup ask came from. The reason `wallShown` is worth logging at all
/// is to tell the surface that earns accounts from the one that merely
/// intercepts.
public enum GateEntry: String, Sendable {
    case card
    case listButton = "list_button"
    case blurredRow = "blurred_row"
    case header
}

public enum LaunchDismissal: String, Sendable {
    case timer
    case tap
    case reduceMotion = "reduce_motion"
    case mapReady = "map_ready"
    /// Skipped entirely because this install had already seen it.
    case alreadySeen = "already_seen"
}

public protocol AnalyticsClient: Sendable {
    func log(_ event: AnalyticsEvent)
}

extension AnalyticsClient {
    // MARK: Launch

    public func launchMomentShown() { log(.init(name: "launch_moment_shown")) }

    public func launchMomentDismissed(_ source: LaunchDismissal) {
        log(.init(name: "launch_moment_dismissed", properties: ["source": source.rawValue]))
    }

    // MARK: Browse

    public func mapLoaded(rentals: Int, buildings: Int, filtered: Bool) {
        log(.init(name: "map_loaded", properties: [
            "rentals": "\(rentals)", "buildings": "\(buildings)", "filtered": "\(filtered)"
        ]))
    }

    public func pinTapped(listing: UUID) {
        log(.init(name: "pin_tapped", properties: ["listing_id": listing.uuidString]))
    }

    public func rowTapped(listing: UUID, locked: Bool) {
        log(.init(name: "row_tapped", properties: [
            "listing_id": listing.uuidString, "locked": "\(locked)"
        ]))
    }

    public func cardOpened(listing: UUID) {
        log(.init(name: "card_opened", properties: ["listing_id": listing.uuidString]))
    }

    public func filterChanged(_ which: String, value: String) {
        log(.init(name: "filter_changed", properties: ["filter": which, "value": value]))
    }

    // MARK: The gate

    /// `ordinal` is 1 for the first wall of the session, 2 for the second, and
    /// so on. Dismissal rate by ordinal is the measurement that says whether
    /// repetition is training refusal.
    public func wallShown(entry: GateEntry, listing: UUID?, ordinal: Int) {
        log(.init(name: "wall_shown", properties: [
            "entry": entry.rawValue,
            "listing_id": listing?.uuidString ?? "none",
            "ordinal": "\(ordinal)"
        ]))
    }

    public func wallDismissed(entry: GateEntry, ordinal: Int) {
        log(.init(name: "wall_dismissed", properties: [
            "entry": entry.rawValue, "ordinal": "\(ordinal)"
        ]))
    }

    /// `method` is "apple" or "email". The address itself must never appear in
    /// a payload; see `ConsoleAnalyticsClient`.
    public func signupAttempted(method: String) {
        log(.init(name: "signup_attempted", properties: ["method": method]))
    }

    public func signupSucceeded(method: String, entry: GateEntry?) {
        log(.init(name: "signup_succeeded", properties: [
            "method": method, "entry": entry?.rawValue ?? "none"
        ]))
    }

    public func signupFailed(reason: String) {
        log(.init(name: "signup_failed", properties: ["reason": reason]))
    }

    public func detailOpened(listing: UUID, source: String) {
        log(.init(name: "detail_opened", properties: [
            "listing_id": listing.uuidString, "source": source
        ]))
    }

    // MARK: Location

    public func locateTapped(status: String) {
        log(.init(name: "locate_tapped", properties: ["authorization": status]))
    }

    public func locationExplainer(_ outcome: String) {
        log(.init(name: "location_explainer", properties: ["outcome": outcome]))
    }
}

/// Prints to the console and nothing else.
///
/// The point is that the call sites exist and are correct, so a real sink is a
/// one-line swap in the composition root.
///
/// Privacy, deliberately enforced here rather than trusted at the call sites:
/// nothing identifies a renter beyond an install-scoped anonymous id, and any
/// property that looks like an email address is dropped rather than sent. Easy
/// to get right now and expensive to retrofit after a leak.
public struct ConsoleAnalyticsClient: AnalyticsClient {
    private let installID: String

    public init(installID: String = ConsoleAnalyticsClient.persistentInstallID()) {
        self.installID = installID
    }

    public func log(_ event: AnalyticsEvent) {
        let safe = event.properties.filter { _, value in !value.contains("@") }
        let dropped = event.properties.count - safe.count
        let rendered = safe
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        print("[analytics] \(event.name) install=\(installID) \(rendered)"
              + (dropped > 0 ? " (dropped \(dropped) property containing an address)" : ""))
    }

    /// Install-scoped and anonymous. Not the vendor id, which is shared across
    /// every app from one publisher.
    public static func persistentInstallID() -> String {
        let key = "ALInstallID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }
}

/// Records events in memory so tests can assert on the funnel.
public final class RecordingAnalyticsClient: AnalyticsClient, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [AnalyticsEvent] = []

    public init() {}

    public func log(_ event: AnalyticsEvent) {
        lock.withLock { storage.append(event) }
    }

    public var events: [AnalyticsEvent] { lock.withLock { storage } }
    public func names() -> [String] { events.map(\.name) }
    public func first(_ name: String) -> AnalyticsEvent? { events.first { $0.name == name } }
}
