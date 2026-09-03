import ALCore
import CoreLocation
import Foundation

/// `CLLocationManager` bridged to structured concurrency.
///
/// The delegate is a private `NSObject` held by the client rather than the
/// client conforming to `CLLocationManagerDelegate` itself. Two reasons:
/// `CLLocationManager` must be created and messaged on the thread that owns its
/// run loop, and an actor cannot satisfy a non-`Sendable` delegate protocol
/// under Swift 6 without escape hatches. Confining all of it to `@MainActor` in
/// one small object is honest and needs no `nonisolated(unsafe)`.
public final class SystemLocationClient: LocationClient {
    private let bridge: Bridge

    /// `@MainActor` because `Bridge` owns a `CLLocationManager`, which must be
    /// created on the thread that owns its run loop. Constructing this from a
    /// background context would put the manager's delegate callbacks somewhere
    /// nobody is listening.
    @MainActor
    public init() {
        self.bridge = Bridge()
    }

    public func currentAuthorization() async -> LocationAuthorization {
        await bridge.authorization()
    }

    public func authorizationUpdates() -> AsyncStream<LocationAuthorization> {
        AsyncStream { continuation in
            Task { @MainActor in
                bridge.addObserver(continuation)
            }
        }
    }

    public func requestWhenInUseAuthorization() async {
        await bridge.requestWhenInUse()
    }

    public func currentCoordinate() async -> Coordinate? {
        await bridge.oneShotLocation()
    }
}

/// `@preconcurrency` on the conformance, not a blanket `nonisolated` on every
/// method.
///
/// `CLLocationManagerDelegate` predates concurrency and carries no isolation
/// annotation, so a `@MainActor` type conforming to it is a data-race warning by
/// default. It is sound here for a specific reason: Core Location delivers
/// delegate callbacks on the queue whose run loop owned the manager at creation,
/// and this manager is created on the main actor in `init`. Marking the methods
/// `nonisolated` instead would be worse — each would then have to read the
/// non-`Sendable` `CLLocationManager` off the main actor before hopping back,
/// which is the actual race.
@MainActor
private final class Bridge: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var observers: [AsyncStream<LocationAuthorization>.Continuation] = []
    private var observerIDs: [Int] = []
    private var nextObserverID = 0
    private var pendingLocation: [CheckedContinuation<Coordinate?, Never>] = []

    private func removeObserver(_ id: Int) {
        guard let index = observerIDs.firstIndex(of: id) else { return }
        observerIDs.remove(at: index)
        observers.remove(at: index)
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func authorization() -> LocationAuthorization { LocationAuthorization(manager) }

    func addObserver(_ continuation: AsyncStream<LocationAuthorization>.Continuation) {
        observers.append(continuation)
        continuation.yield(LocationAuthorization(manager))   // seed with current
        // Identity, so a terminated stream drops its own continuation instead
        // of leaking one per subscriber for the life of the process.
        let id = nextObserverID
        nextObserverID += 1
        observerIDs.append(id)
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.removeObserver(id) }
        }
    }

    func requestWhenInUse() {
        // Guarded because after a denial this call does nothing at all, and a
        // caller that does not know that will sit waiting for a prompt that can
        // never appear.
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func oneShotLocation() async -> Coordinate? {
        guard LocationAuthorization(manager).isAuthorized else { return nil }
        return await withCheckedContinuation { continuation in
            pendingLocation.append(continuation)
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let value = LocationAuthorization(manager)
        for observer in observers { observer.yield(value) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last.map { Coordinate($0.coordinate) }
        let waiting = pendingLocation
        pendingLocation.removeAll()
        for continuation in waiting { continuation.resume(returning: coordinate) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let waiting = pendingLocation
        pendingLocation.removeAll()
        for continuation in waiting { continuation.resume(returning: nil) }
    }
}

/// Drives every permission path in previews, tests, and the demo build without
/// touching the real system prompt (which can only be answered once per install).
public final class StubLocationClient: LocationClient, @unchecked Sendable {
    private let lock = NSLock()
    private var current: LocationAuthorization
    private var observers: [Int: AsyncStream<LocationAuthorization>.Continuation] = [:]
    private var nextObserverID = 0
    private let fixedCoordinate: Coordinate
    /// What the simulated prompt returns when it is shown. Private because
    /// `@unchecked Sendable` tells the compiler to stop checking, and a public
    /// `var` on such a type is an unsynchronised race by construction.
    private var _promptOutcome: LocationAuthorization

    public func setPromptOutcome(_ outcome: LocationAuthorization) {
        lock.withLock { _promptOutcome = outcome }
    }

    public init(
        initial: LocationAuthorization = .unknown,
        promptOutcome: LocationAuthorization = .init(status: .whenInUse, precision: .full),
        coordinate: Coordinate = .init(latitude: 37.7691, longitude: -122.4313)
    ) {
        self.current = initial
        self._promptOutcome = promptOutcome
        self.fixedCoordinate = coordinate
    }

    public func currentAuthorization() async -> LocationAuthorization {
        lock.withLock { current }
    }

    public func authorizationUpdates() -> AsyncStream<LocationAuthorization> {
        AsyncStream { continuation in
            // Keyed and shed on termination. Without this every store that ever
            // subscribed stayed in the array for the life of the process.
            let (id, value) = lock.withLock { () -> (Int, LocationAuthorization) in
                let id = nextObserverID
                nextObserverID += 1
                observers[id] = continuation
                return (id, current)
            }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.observers[id] = nil }
            }
            continuation.yield(value)
        }
    }

    public func requestWhenInUseAuthorization() async {
        let (shouldEmit, value) = lock.withLock { () -> (Bool, LocationAuthorization) in
            guard current.canPrompt else { return (false, current) }
            current = _promptOutcome
            return (true, current)
        }
        guard shouldEmit else { return }
        let targets = lock.withLock { Array(observers.values) }
        for observer in targets { observer.yield(value) }
    }

    public func currentCoordinate() async -> Coordinate? {
        lock.withLock { current.isAuthorized ? fixedCoordinate : nil }
    }

    /// Live subscriber count, so a leak is assertable rather than argued about.
    public var observerCount: Int { lock.withLock { observers.count } }
}
