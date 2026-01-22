import Foundation

/// Watchdog for detecting hung operations and enforcing timeouts
final class OperationWatchdog {

    static let shared = OperationWatchdog()

    /// Timeout configuration
    struct Configuration {
        /// Maximum time for whisper transcription (default: 60 seconds)
        var transcriptionTimeoutSeconds: TimeInterval = 60

        /// Maximum time for accessibility API calls (default: 5 seconds)
        var accessibilityTimeoutSeconds: TimeInterval = 5

        /// Maximum time for model loading (default: 120 seconds)
        var modelLoadTimeoutSeconds: TimeInterval = 120
    }

    /// Current configuration
    var configuration = Configuration()

    /// Active watchdog timers
    private var activeWatchdogs: [String: WatchdogEntry] = [:]
    private let lock = NSLock()

    /// Watchdog entry tracking
    private struct WatchdogEntry {
        let workItem: DispatchWorkItem
        let startTime: Date
        let timeout: TimeInterval
        let operation: String
    }

    private init() {}

    // MARK: - Watchdog Management

    /// Start a watchdog for an operation
    /// - Parameters:
    ///   - id: Unique identifier for this operation
    ///   - timeout: Timeout in seconds
    ///   - operation: Human-readable description of the operation
    ///   - onTimeout: Callback when timeout occurs
    func startWatchdog(id: String, timeout: TimeInterval, operation: String = "", onTimeout: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }

        // Cancel existing watchdog if any
        activeWatchdogs[id]?.workItem.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            let operationDesc = operation.isEmpty ? id : operation
            Logger.shared.error("WATCHDOG TIMEOUT: '\(operationDesc)' exceeded \(timeout)s", category: .app)

            // Log to crash reporter state
            Logger.shared.logSync("Watchdog timeout for \(operationDesc) after \(timeout)s", level: .error, category: .app)

            self.removeWatchdog(id: id)
            onTimeout()
        }

        let entry = WatchdogEntry(
            workItem: workItem,
            startTime: Date(),
            timeout: timeout,
            operation: operation.isEmpty ? id : operation
        )

        activeWatchdogs[id] = entry
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: workItem)

        Logger.shared.debug("Watchdog started: '\(entry.operation)' with \(timeout)s timeout", category: .app)
    }

    /// Complete an operation successfully (cancels watchdog)
    /// - Parameter id: The operation identifier
    func completeOperation(id: String) {
        lock.lock()
        defer { lock.unlock() }

        if let entry = activeWatchdogs[id] {
            entry.workItem.cancel()
            let elapsed = Date().timeIntervalSince(entry.startTime)
            Logger.shared.debug("Watchdog cleared: '\(entry.operation)' completed in \(String(format: "%.2f", elapsed))s", category: .app)
            activeWatchdogs.removeValue(forKey: id)
        }
    }

    /// Cancel a watchdog without logging completion
    /// - Parameter id: The operation identifier
    func cancelWatchdog(id: String) {
        lock.lock()
        defer { lock.unlock() }

        activeWatchdogs[id]?.workItem.cancel()
        activeWatchdogs.removeValue(forKey: id)
    }

    /// Remove watchdog entry (internal use)
    private func removeWatchdog(id: String) {
        lock.lock()
        defer { lock.unlock() }
        activeWatchdogs.removeValue(forKey: id)
    }

    // MARK: - Convenience Methods

    /// Start a transcription watchdog with default timeout
    func startTranscriptionWatchdog(id: String = "transcription", onTimeout: @escaping () -> Void) {
        startWatchdog(
            id: id,
            timeout: configuration.transcriptionTimeoutSeconds,
            operation: "Whisper transcription",
            onTimeout: onTimeout
        )
    }

    /// Start an accessibility operation watchdog with default timeout
    func startAccessibilityWatchdog(id: String = "accessibility", onTimeout: @escaping () -> Void) {
        startWatchdog(
            id: id,
            timeout: configuration.accessibilityTimeoutSeconds,
            operation: "Accessibility API call",
            onTimeout: onTimeout
        )
    }

    /// Start a model loading watchdog with default timeout
    func startModelLoadWatchdog(id: String = "model-load", onTimeout: @escaping () -> Void) {
        startWatchdog(
            id: id,
            timeout: configuration.modelLoadTimeoutSeconds,
            operation: "Whisper model loading",
            onTimeout: onTimeout
        )
    }

    // MARK: - Status

    /// Get list of active watchdogs (for diagnostics)
    func getActiveWatchdogs() -> [(id: String, operation: String, elapsed: TimeInterval, timeout: TimeInterval)] {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        return activeWatchdogs.map { (id, entry) in
            (id: id, operation: entry.operation, elapsed: now.timeIntervalSince(entry.startTime), timeout: entry.timeout)
        }
    }

    /// Check if an operation has an active watchdog
    func hasActiveWatchdog(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeWatchdogs[id] != nil
    }

    /// Cancel all active watchdogs
    func cancelAllWatchdogs() {
        lock.lock()
        defer { lock.unlock() }

        for (_, entry) in activeWatchdogs {
            entry.workItem.cancel()
        }
        activeWatchdogs.removeAll()

        Logger.shared.info("All watchdogs cancelled", category: .app)
    }
}

// MARK: - Async Timeout Helper

extension OperationWatchdog {

    /// Execute an async operation with timeout
    /// - Parameters:
    ///   - timeout: Timeout in seconds
    ///   - operation: Description for logging
    ///   - work: The async work to perform
    /// - Returns: The result of the work
    /// - Throws: `TimeoutError` if timeout occurs, or any error from work
    func withTimeout<T>(
        _ timeout: TimeInterval,
        operation: String,
        work: @escaping () async throws -> T
    ) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            // Add the actual work
            group.addTask {
                try await work()
            }

            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw TimeoutError(operation: operation, timeout: timeout)
            }

            // Return first to complete (either result or timeout)
            guard let result = try await group.next() else {
                throw TimeoutError(operation: operation, timeout: timeout)
            }

            // Cancel remaining tasks
            group.cancelAll()

            return result
        }
    }
}

/// Error thrown when an operation times out
struct TimeoutError: Error, LocalizedError {
    let operation: String
    let timeout: TimeInterval

    var errorDescription: String? {
        "Operation '\(operation)' timed out after \(timeout) seconds"
    }
}
