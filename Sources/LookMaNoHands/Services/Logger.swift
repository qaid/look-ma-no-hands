import Foundation
import os.log

/// Centralized logging service using Apple's unified logging system (OSLog)
/// Logs persist to ~/Library/Logs/LookMaNoHands/ and are viewable in Console.app
final class Logger {

    /// Shared instance for app-wide logging
    static let shared = Logger()

    /// OSLog subsystem identifier
    private let subsystem = Bundle.main.bundleIdentifier ?? "com.lookmanohands"

    /// Category-specific loggers for organized filtering in Console.app
    private lazy var appLogger = OSLog(subsystem: subsystem, category: "App")
    private lazy var audioLogger = OSLog(subsystem: subsystem, category: "Audio")
    private lazy var whisperLogger = OSLog(subsystem: subsystem, category: "Whisper")
    private lazy var accessibilityLogger = OSLog(subsystem: subsystem, category: "Accessibility")
    private lazy var keyboardLogger = OSLog(subsystem: subsystem, category: "Keyboard")
    private lazy var memoryLogger = OSLog(subsystem: subsystem, category: "Memory")
    private lazy var crashLogger = OSLog(subsystem: subsystem, category: "Crash")

    /// Log file URL
    private let logDirectory: URL
    private var logFileHandle: FileHandle?
    private let logQueue = DispatchQueue(label: "com.lookmanohands.logger", qos: .utility)

    /// Log levels matching OSLog types
    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        case fault = "FAULT"  // For crash-related critical errors
    }

    /// Log categories for filtering
    enum Category: String {
        case app = "App"
        case audio = "Audio"
        case whisper = "Whisper"
        case accessibility = "Accessibility"
        case keyboard = "Keyboard"
        case memory = "Memory"
        case crash = "Crash"
    }

    private init() {
        // Setup log directory
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        logDirectory = libraryURL.appendingPathComponent("Logs/LookMaNoHands")

        setupPersistentLogging()
    }

    /// Initialize persistent log file at ~/Library/Logs/LookMaNoHands/
    private func setupPersistentLogging() {
        do {
            // Create log directory if needed
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

            // Create log file with date stamp
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: Date())
            let logFileURL = logDirectory.appendingPathComponent("lookmanohands-\(dateString).log")

            // Create file if it doesn't exist
            if !FileManager.default.fileExists(atPath: logFileURL.path) {
                FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
            }

            // Open file handle for appending
            logFileHandle = try FileHandle(forWritingTo: logFileURL)
            logFileHandle?.seekToEndOfFile()

            // Write startup marker
            let startupMessage = "\n\n========== App Started at \(ISO8601DateFormatter().string(from: Date())) ==========\n"
            if let data = startupMessage.data(using: .utf8) {
                logFileHandle?.write(data)
            }

            // Cleanup old log files (keep last 7 days)
            cleanupOldLogs()

        } catch {
            // Fall back to OSLog only if file logging fails
            os_log("Failed to setup persistent logging: %{public}@", log: appLogger, type: .error, error.localizedDescription)
        }
    }

    /// Remove log files older than 7 days
    private func cleanupOldLogs() {
        let fileManager = FileManager.default
        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .day, value: -7, to: Date())!

        do {
            let logFiles = try fileManager.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: [.creationDateKey])

            for fileURL in logFiles {
                guard fileURL.pathExtension == "log" else { continue }

                if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                   let creationDate = attributes[.creationDate] as? Date,
                   creationDate < cutoffDate {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        } catch {
            // Ignore cleanup errors
        }
    }

    /// Main logging method
    func log(_ message: String, level: Level = .info, category: Category = .app,
             file: String = #file, function: String = #function, line: Int = #line) {

        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let formattedMessage = "[\(timestamp)] [\(level.rawValue)] [\(category.rawValue)] \(fileName):\(line) \(function) - \(message)"

        // Write to OSLog
        let osLog = osLogger(for: category)
        let osLogType = osLogType(for: level)
        os_log("%{public}@", log: osLog, type: osLogType, message)

        // Write to file asynchronously
        logQueue.async { [weak self] in
            self?.writeToFile(formattedMessage)
        }
    }

    /// Synchronous write for crash-critical moments (bypasses async queue)
    /// Use this when you need to guarantee the log is written before potential crash
    func logSync(_ message: String, level: Level = .fault, category: Category = .crash,
                 file: String = #file, function: String = #function, line: Int = #line) {

        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let formattedMessage = "[\(timestamp)] [\(level.rawValue)] [\(category.rawValue)] \(fileName):\(line) \(function) - \(message)"

        // Write to OSLog
        let osLog = osLogger(for: category)
        let osLogType = osLogType(for: level)
        os_log("%{public}@", log: osLog, type: osLogType, message)

        // Write to file synchronously
        writeToFile(formattedMessage)

        // Force flush
        logFileHandle?.synchronizeFile()
    }

    /// Write message to log file
    private func writeToFile(_ message: String) {
        guard let data = (message + "\n").data(using: .utf8) else { return }
        logFileHandle?.write(data)
    }

    /// Get OSLog instance for category
    private func osLogger(for category: Category) -> OSLog {
        switch category {
        case .app: return appLogger
        case .audio: return audioLogger
        case .whisper: return whisperLogger
        case .accessibility: return accessibilityLogger
        case .keyboard: return keyboardLogger
        case .memory: return memoryLogger
        case .crash: return crashLogger
        }
    }

    /// Convert Level to OSLogType
    private func osLogType(for level: Level) -> OSLogType {
        switch level {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .fault: return .fault
        }
    }

    /// Get the log directory URL (for diagnostics UI)
    var logDirectoryURL: URL {
        return logDirectory
    }

    /// Get list of log files
    func getLogFiles() -> [URL] {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: [.creationDateKey])
            return files.filter { $0.pathExtension == "log" }.sorted { $0.path > $1.path }
        } catch {
            return []
        }
    }

    /// Flush and close log file (call on app termination)
    func shutdown() {
        logQueue.sync {
            let shutdownMessage = "========== App Terminated at \(ISO8601DateFormatter().string(from: Date())) ==========\n"
            if let data = shutdownMessage.data(using: .utf8) {
                logFileHandle?.write(data)
            }
            logFileHandle?.synchronizeFile()
            try? logFileHandle?.close()
        }
    }

    deinit {
        shutdown()
    }
}

// MARK: - Convenience Methods

extension Logger {

    /// Log debug message
    func debug(_ message: String, category: Category = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, category: category, file: file, function: function, line: line)
    }

    /// Log info message
    func info(_ message: String, category: Category = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }

    /// Log warning message
    func warning(_ message: String, category: Category = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, category: category, file: file, function: function, line: line)
    }

    /// Log error message
    func error(_ message: String, category: Category = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }

    /// Log fault message (for critical errors that may lead to crash)
    func fault(_ message: String, category: Category = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .fault, category: category, file: file, function: function, line: line)
    }
}
