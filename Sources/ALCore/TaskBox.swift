import Foundation

/// A cancellable task handle that a `nonisolated deinit` may legally touch.
///
/// Why this exists: `deinit` on a `@MainActor`-isolated class is itself
/// nonisolated, so under Swift 6 it cannot read an isolated stored property.
/// Verified, not assumed:
///
///     @MainActor @Observable final class S {
///         private var task: Task<Void, Never>?
///         deinit { task?.cancel() }
///         //       ^ error: main actor-isolated property 'task' can not be
///         //         referenced from a nonisolated context
///     }
///
/// Holding the handle in a `Sendable` box with its own lock makes the box
/// nonisolated, so `deinit` may cancel through it. `nonisolated(unsafe)` appears
/// exactly once, here, guarded by the lock immediately around it, rather than
/// being sprinkled across every store that owns a task.
public final class TaskBox: Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var task: Task<Void, Never>?

    public init() {}

    /// Installs a new task, cancelling whatever it replaces.
    ///
    /// The previous task is cancelled *outside* the lock: `cancel()` can run
    /// arbitrary cancellation handlers, and holding a lock across that is how
    /// deadlocks get written.
    public func replace(with newTask: Task<Void, Never>) {
        let previous = lock.withLock {
            let old = task
            task = newTask
            return old
        }
        previous?.cancel()
    }

    /// True when nothing has been installed since the last `cancel()`.
    ///
    /// Deliberately NOT "nothing is running": a task that completes normally is
    /// never cleared, so this stays false afterwards. That is exactly what an
    /// idempotence guard like `LocationPermissionStore.start()` wants, but the
    /// name reads more absolute than it is.
    public var isIdle: Bool { lock.withLock { task == nil } }

    public func cancel() {
        let current = lock.withLock {
            let old = task
            task = nil
            return old
        }
        current?.cancel()
    }
}
