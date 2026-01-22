import Foundation
import Darwin

/// Service for handling crashes and capturing diagnostics
/// Must be initialized early in app lifecycle (applicationDidFinishLaunching)
final class CrashReporter {

    static let shared = CrashReporter()

    /// Crash report directory
    private let crashDirectory: URL

    /// Previous exception handler (to chain if set by another framework)
    /// Note: fileprivate to allow access from the module-level exception handler function
    fileprivate var previousExceptionHandler: (@convention(c) (NSException) -> Void)?

    /// App state snapshot for crash diagnostics
    struct AppStateSnapshot: Codable {
        var isRecording: Bool = false
        var recordingStartTime: Date?
        var audioBufferSamples: Int = 0
        var transcriptionSegmentsCount: Int = 0
        var memoryUsageMB: UInt64 = 0
        var lastTranscription: String?
        var timestamp: Date = Date()
    }

    /// Current state snapshot (updated by services)
    private(set) var lastKnownState = AppStateSnapshot()
    private let stateLock = NSLock()

    private init() {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        crashDirectory = libraryURL.appendingPathComponent("Logs/LookMaNoHands/crashes")

        // Create crash directory
        try? FileManager.default.createDirectory(at: crashDirectory, withIntermediateDirectories: true)
    }

    /// Install all crash handlers - call early in app startup
    func install() {
        installSignalHandlers()
        installExceptionHandler()
        Logger.shared.info("CrashReporter installed", category: .crash)
    }

    // MARK: - Signal Handlers

    /// Install Unix signal handlers for crash detection
    private func installSignalHandlers() {
        // Store reference to self for signal handler access
        sharedCrashReporter = self

        // Install handlers for common crash signals
        signal(SIGSEGV, signalHandler)  // Segmentation fault
        signal(SIGABRT, signalHandler)  // Abort (assert, fatal error)
        signal(SIGBUS, signalHandler)   // Bus error
        signal(SIGFPE, signalHandler)   // Floating point exception
        signal(SIGILL, signalHandler)   // Illegal instruction
        signal(SIGTRAP, signalHandler)  // Breakpoint trap
    }

    /// Install NSException handler for Objective-C exceptions
    private func installExceptionHandler() {
        previousExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler(exceptionHandler)
    }

    // MARK: - State Updates

    /// Update recording state (call from AudioRecorder)
    func updateRecordingState(isRecording: Bool, bufferSamples: Int = 0) {
        stateLock.lock()
        defer { stateLock.unlock() }

        lastKnownState.isRecording = isRecording
        lastKnownState.audioBufferSamples = bufferSamples
        if isRecording && lastKnownState.recordingStartTime == nil {
            lastKnownState.recordingStartTime = Date()
        } else if !isRecording {
            lastKnownState.recordingStartTime = nil
        }
        lastKnownState.timestamp = Date()

        saveStateToDisk()
    }

    /// Update memory usage (call from MemoryMonitor)
    func updateMemoryUsage(_ memoryMB: UInt64) {
        stateLock.lock()
        defer { stateLock.unlock() }

        lastKnownState.memoryUsageMB = memoryMB
        lastKnownState.timestamp = Date()
    }

    /// Update transcription state
    func updateTranscriptionState(segmentsCount: Int, lastTranscription: String?) {
        stateLock.lock()
        defer { stateLock.unlock() }

        lastKnownState.transcriptionSegmentsCount = segmentsCount
        lastKnownState.lastTranscription = lastTranscription
        lastKnownState.timestamp = Date()

        saveStateToDisk()
    }

    // MARK: - Crash Report Writing

    /// Write crash report synchronously (safe to call from signal handler)
    func writeCrashReport(signal: Int32?, exception: NSException?) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fileName = "crash-\(timestamp.replacingOccurrences(of: ":", with: "-")).txt"
        let crashFileURL = crashDirectory.appendingPathComponent(fileName)

        var report = """
        ================================================================================
        LOOK MA NO HANDS CRASH REPORT
        ================================================================================
        Time: \(timestamp)

        """

        if let signal = signal {
            report += """
        Signal: \(signalName(signal)) (\(signal))

        """
        }

        if let exception = exception {
            report += """
        Exception: \(exception.name.rawValue)
        Reason: \(exception.reason ?? "Unknown")

        """
        }

        // Add app state
        stateLock.lock()
        let state = lastKnownState
        stateLock.unlock()

        report += """
        APP STATE AT CRASH
        ------------------
        Recording: \(state.isRecording)
        Recording Start: \(state.recordingStartTime?.description ?? "N/A")
        Audio Buffer Samples: \(state.audioBufferSamples)
        Transcription Segments: \(state.transcriptionSegmentsCount)
        Memory Usage: \(state.memoryUsageMB) MB
        Last State Update: \(state.timestamp)

        """

        if let lastTranscription = state.lastTranscription {
            report += """
        Last Transcription: \(lastTranscription.prefix(500))...

        """
        }

        // Add stack trace
        report += """
        STACK TRACE
        -----------
        \(Thread.callStackSymbols.joined(separator: "\n"))

        ================================================================================
        """

        // Write using low-level file operations (safer in signal context)
        do {
            try report.write(to: crashFileURL, atomically: false, encoding: .utf8)
        } catch {
            // Last resort: try to write to stderr
            fputs("CRASH REPORT WRITE FAILED: \(error)\n", stderr)
            fputs(report, stderr)
        }

        // Also log synchronously
        Logger.shared.logSync("Crash report written to \(crashFileURL.path)", level: .fault, category: .crash)
    }

    /// Get signal name from number
    private func signalName(_ signal: Int32) -> String {
        switch signal {
        case SIGSEGV: return "SIGSEGV (Segmentation Fault)"
        case SIGABRT: return "SIGABRT (Abort)"
        case SIGBUS: return "SIGBUS (Bus Error)"
        case SIGFPE: return "SIGFPE (Floating Point Exception)"
        case SIGILL: return "SIGILL (Illegal Instruction)"
        case SIGTRAP: return "SIGTRAP (Trap)"
        default: return "Signal \(signal)"
        }
    }

    // MARK: - State Persistence

    /// Save state to disk for crash recovery
    private func saveStateToDisk() {
        let stateFile = crashDirectory.appendingPathComponent("app-state.json")
        if let data = try? JSONEncoder().encode(lastKnownState) {
            try? data.write(to: stateFile)
        }
    }

    /// Load last saved state (for crash recovery)
    func loadSavedState() -> AppStateSnapshot? {
        let stateFile = crashDirectory.appendingPathComponent("app-state.json")
        guard let data = try? Data(contentsOf: stateFile),
              let state = try? JSONDecoder().decode(AppStateSnapshot.self, from: data) else {
            return nil
        }
        return state
    }

    // MARK: - Crash Report Retrieval

    /// Get the most recent crash report (if any)
    func getLastCrashReport() -> (url: URL, content: String)? {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: crashDirectory, includingPropertiesForKeys: [.creationDateKey])
            let crashFiles = files.filter { $0.lastPathComponent.hasPrefix("crash-") && $0.pathExtension == "txt" }
                .sorted { (url1, url2) -> Bool in
                    let date1 = (try? FileManager.default.attributesOfItem(atPath: url1.path)[.creationDate] as? Date) ?? Date.distantPast
                    let date2 = (try? FileManager.default.attributesOfItem(atPath: url2.path)[.creationDate] as? Date) ?? Date.distantPast
                    return date1 > date2
                }

            if let mostRecent = crashFiles.first,
               let content = try? String(contentsOf: mostRecent, encoding: .utf8) {
                return (mostRecent, content)
            }
        } catch {
            Logger.shared.error("Failed to read crash reports: \(error)", category: .crash)
        }
        return nil
    }

    /// Get all crash reports
    func getAllCrashReports() -> [URL] {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: crashDirectory, includingPropertiesForKeys: [.creationDateKey])
            return files.filter { $0.lastPathComponent.hasPrefix("crash-") && $0.pathExtension == "txt" }
                .sorted { (url1, url2) -> Bool in
                    let date1 = (try? FileManager.default.attributesOfItem(atPath: url1.path)[.creationDate] as? Date) ?? Date.distantPast
                    let date2 = (try? FileManager.default.attributesOfItem(atPath: url2.path)[.creationDate] as? Date) ?? Date.distantPast
                    return date1 > date2
                }
        } catch {
            return []
        }
    }

    /// Delete a crash report
    func deleteCrashReport(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Delete all crash reports
    func deleteAllCrashReports() {
        for url in getAllCrashReports() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Get crash directory URL (for diagnostics UI)
    var crashDirectoryURL: URL {
        return crashDirectory
    }
}

// MARK: - Signal Handler (C function)

/// Global reference for signal handler access
private var sharedCrashReporter: CrashReporter?

/// C-compatible signal handler function
private func signalHandler(signal: Int32) {
    // Write crash report
    sharedCrashReporter?.writeCrashReport(signal: signal, exception: nil)

    // Re-raise signal with default handler to allow normal termination
    Darwin.signal(signal, SIG_DFL)
    Darwin.raise(signal)
}

// MARK: - Exception Handler (C function)

/// C-compatible exception handler function
private func exceptionHandler(exception: NSException) {
    sharedCrashReporter?.writeCrashReport(signal: nil, exception: exception)

    // Call previous handler if any
    if let previousHandler = sharedCrashReporter?.previousExceptionHandler {
        previousHandler(exception)
    }
}
