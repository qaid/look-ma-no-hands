import Foundation
import Dispatch

/// Service for monitoring memory usage and handling memory pressure
final class MemoryMonitor {

    static let shared = MemoryMonitor()

    /// Memory pressure source from system
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    /// Timer for periodic memory checks
    private var memoryCheckTimer: DispatchSourceTimer?

    /// Whether monitoring is active
    private(set) var isMonitoring = false

    /// Warning threshold in MB (default: 200MB)
    var warningThresholdMB: UInt64 = 200

    /// Critical threshold in MB (default: 400MB)
    var criticalThresholdMB: UInt64 = 400

    /// Callback when memory warning is triggered
    var onMemoryWarning: ((UInt64) -> Void)?

    /// Callback when memory critical is triggered
    var onMemoryCritical: ((UInt64) -> Void)?

    /// Last recorded memory usage
    private(set) var lastMemoryUsageMB: UInt64 = 0

    /// Peak memory usage during session
    private(set) var peakMemoryUsageMB: UInt64 = 0

    private init() {}

    /// Start monitoring memory
    func startMonitoring() {
        guard !isMonitoring else { return }

        setupMemoryPressureHandler()
        setupPeriodicMemoryCheck()

        isMonitoring = true
        Logger.shared.info("MemoryMonitor started (warning: \(warningThresholdMB)MB, critical: \(criticalThresholdMB)MB)", category: .memory)
    }

    /// Stop monitoring memory
    func stopMonitoring() {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil

        memoryCheckTimer?.cancel()
        memoryCheckTimer = nil

        isMonitoring = false
        Logger.shared.info("MemoryMonitor stopped", category: .memory)
    }

    // MARK: - Memory Pressure Handler

    /// Setup DispatchSource for system memory pressure notifications
    private func setupMemoryPressureHandler() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )

        memoryPressureSource?.setEventHandler { [weak self] in
            guard let self = self else { return }

            let event = self.memoryPressureSource?.data ?? []
            let currentMemory = self.getCurrentMemoryUsageMB()

            if event.contains(.critical) {
                Logger.shared.fault("CRITICAL system memory pressure! App usage: \(currentMemory)MB", category: .memory)
                self.onMemoryCritical?(currentMemory)
            } else if event.contains(.warning) {
                Logger.shared.warning("System memory pressure warning. App usage: \(currentMemory)MB", category: .memory)
                self.onMemoryWarning?(currentMemory)
            }
        }

        memoryPressureSource?.resume()
    }

    // MARK: - Periodic Memory Check

    /// Periodic memory check (every 5 seconds)
    private func setupPeriodicMemoryCheck() {
        memoryCheckTimer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        memoryCheckTimer?.schedule(deadline: .now(), repeating: .seconds(5))

        memoryCheckTimer?.setEventHandler { [weak self] in
            guard let self = self else { return }

            let memoryMB = self.getCurrentMemoryUsageMB()
            self.lastMemoryUsageMB = memoryMB

            // Track peak usage
            if memoryMB > self.peakMemoryUsageMB {
                self.peakMemoryUsageMB = memoryMB
            }

            // Update crash reporter state
            CrashReporter.shared.updateMemoryUsage(memoryMB)

            // Check thresholds
            if memoryMB > self.criticalThresholdMB {
                Logger.shared.fault("CRITICAL memory usage: \(memoryMB)MB exceeds \(self.criticalThresholdMB)MB threshold", category: .memory)
                DispatchQueue.main.async {
                    self.onMemoryCritical?(memoryMB)
                }
            } else if memoryMB > self.warningThresholdMB {
                Logger.shared.warning("Elevated memory usage: \(memoryMB)MB (threshold: \(self.warningThresholdMB)MB)", category: .memory)
            }
        }

        memoryCheckTimer?.resume()
    }

    // MARK: - Memory Usage Query

    /// Get current memory usage in MB using Mach APIs
    func getCurrentMemoryUsageMB() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            Logger.shared.error("Failed to get memory info: \(result)", category: .memory)
            return 0
        }

        let memoryMB = info.resident_size / (1024 * 1024)

        // Always update peak when querying current
        if memoryMB > peakMemoryUsageMB {
            peakMemoryUsageMB = memoryMB
        }
        lastMemoryUsageMB = memoryMB

        return memoryMB
    }

    /// Get current memory usage in bytes
    func getCurrentMemoryUsageBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }
        return info.resident_size
    }

    /// Get formatted memory usage string
    func getFormattedMemoryUsage() -> String {
        let bytes = getCurrentMemoryUsageBytes()

        if bytes >= 1_073_741_824 { // 1 GB
            return String(format: "%.2f GB", Double(bytes) / 1_073_741_824)
        } else if bytes >= 1_048_576 { // 1 MB
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        } else if bytes >= 1024 { // 1 KB
            return String(format: "%.0f KB", Double(bytes) / 1024)
        } else {
            return "\(bytes) bytes"
        }
    }

    /// Get memory statistics for diagnostics
    func getMemoryStatistics() -> [String: Any] {
        return [
            "currentMB": getCurrentMemoryUsageMB(),
            "peakMB": peakMemoryUsageMB,
            "warningThresholdMB": warningThresholdMB,
            "criticalThresholdMB": criticalThresholdMB,
            "isMonitoring": isMonitoring
        ]
    }

    /// Reset peak memory tracking
    func resetPeakMemory() {
        peakMemoryUsageMB = getCurrentMemoryUsageMB()
        Logger.shared.info("Peak memory tracking reset to \(peakMemoryUsageMB)MB", category: .memory)
    }
}
