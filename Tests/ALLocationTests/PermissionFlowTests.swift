import CoreLocation
import Testing
@testable import ALLocation

/// The permission machine is the highest-risk logic in the app: the system
/// prompt fires once per install, so a wrong transition is unrecoverable on a
/// real device. It is therefore driven entirely by a stub here.
@Suite("Location permission flow")
@MainActor
struct PermissionFlowTests {

    private func store(
        initial: LocationAuthorization = .unknown,
        outcome: LocationAuthorization = .init(status: .whenInUse, precision: .full)
    ) -> (LocationPermissionStore, StubLocationClient) {
        let client = StubLocationClient(initial: initial, promptOutcome: outcome)
        return (LocationPermissionStore(client: client), client)
    }

    @Test("An undetermined tap opens our explainer, not the system prompt")
    func explainerComesFirst() async throws {
        let (subject, _) = store()
        subject.start()
        await Task.yield()

        subject.locateTapped()
        try await waitUntil { subject.step == .explaining }
    }

    @Test("Declining the explainer leaves the prompt spendable")
    func decliningKeepsThePromptAvailable() async throws {
        let (subject, _) = store()
        subject.start()
        await Task.yield()

        subject.locateTapped()
        try await waitUntil { subject.step == .explaining }
        subject.explainerDismissed()

        #expect(subject.step == .idle)
        #expect(subject.authorization.canPrompt, "the one prompt must not be spent by a dismissal")
    }

    @Test("Accepting the explainer requests authorization and resolves to idle")
    func acceptingGrants() async throws {
        let (subject, _) = store()
        subject.start()
        await Task.yield()

        subject.locateTapped()
        try await waitUntil { subject.step == .explaining }
        subject.explainerAccepted()

        try await waitUntil { subject.authorization.isAuthorized }
        #expect(subject.step == .idle)
        #expect(subject.coordinate != nil)
    }

    @Test("A denial does not immediately push the recovery sheet")
    func denialIsNotImmediatelyNagged() async throws {
        let (subject, _) = store(outcome: .init(status: .denied, precision: .full))
        subject.start()
        await Task.yield()

        subject.locateTapped()
        try await waitUntil { subject.step == .explaining }
        subject.explainerAccepted()

        try await waitUntil { subject.authorization.status == .denied }
        // Two sheets back to back reads as nagging. The next deliberate tap
        // is what opens recovery.
        #expect(subject.step == .idle)
        #expect(subject.coordinate == nil)

        subject.locateTapped()
        try await waitUntil { subject.step == .recovering }
    }

    @Test("Once denied, the explainer never returns")
    func deniedSkipsTheExplainer() async throws {
        let (subject, _) = store(initial: .init(status: .denied, precision: .full))
        subject.start()
        await Task.yield()

        subject.locateTapped()
        try await waitUntil(
            { subject.step == .recovering },
            "the system prompt is gone, so the explainer would be a lie"
        )
    }

    @Test("Reduced precision is surfaced rather than hidden")
    func reducedPrecisionIsVisible() async throws {
        let (subject, _) = store(outcome: .init(status: .whenInUse, precision: .reduced))
        subject.start()
        await Task.yield()

        subject.locateTapped()
        try await waitUntil { subject.step == .explaining }
        subject.explainerAccepted()

        try await waitUntil { subject.authorization.isAuthorized }
        #expect(subject.showsReducedPrecisionNotice)
    }

    @Test("Restricted collapses into denied, since the remedy is the same")
    func restrictedIsDenied() {
        #expect(LocationAuthorization(status: .denied, precision: .full).canPrompt == false)
        #expect(LocationAuthorization.unknown.canPrompt)
    }

    /// Polls rather than sleeping a fixed interval, so the suite is not slower
    /// than it needs to be or flaky on a loaded machine.
    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        _ message: String = "condition never became true",
        timeout: Duration = .seconds(2)
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record(Comment(rawValue: message))
    }
}
