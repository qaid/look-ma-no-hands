import Foundation
import AppKit
import CryptoKit
import Combine

/// Handles downloading, verifying, installing, and relaunching app updates from GitHub Releases.
class AutoUpdateService: NSObject, ObservableObject, @unchecked Sendable {

    static let shared = AutoUpdateService()

    // MARK: - Types

    enum UpdateState: Equatable {
        case idle
        case downloading(progress: Double)
        case verifying
        case installing
        case readyToRelaunch
        case failed(String)
    }

    // MARK: - Published State

    @Published private(set) var state: UpdateState = .idle

    // MARK: - Private Properties

    private var downloadTask: URLSessionDownloadTask?
    private var downloadContinuation: CheckedContinuation<URL, Error>?
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private let bundleID = "com.lookmanohands.app"
    private let appName = "Look Ma No Hands"
    private let installDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications")

    private var appPath: URL {
        installDir.appendingPathComponent("\(appName).app")
    }

    private static let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    // MARK: - Public API

    /// Full update pipeline: download, verify, install. Does NOT relaunch.
    func performUpdate(release: UpdateService.ReleaseInfo) async {
        await MainActor.run { state = .downloading(progress: 0) }

        var mountPoint: URL?
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LookMaNoHands-update-\(UUID().uuidString)")

        do {
            // Create temp directory
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // Step 1: Download DMG
            let dmgPath = try await downloadDMG(from: release.dmgURL, to: tempDir)

            // Step 2: Verify checksum
            await MainActor.run { state = .verifying }
            if let checksumsURL = release.checksumsURL {
                try await verifyChecksum(dmgPath: dmgPath, checksumsURL: checksumsURL, dmgFilename: release.dmgURL.lastPathComponent)
            } else {
                Logger.shared.warning("No checksums.txt available for this release, skipping verification")
            }

            // Step 3: Install
            await MainActor.run { state = .installing }

            // Mount DMG
            let mount = tempDir.appendingPathComponent("mount")
            try await mountDMG(at: dmgPath.path, mountPoint: mount.path)
            mountPoint = mount

            // Find .app bundle in mounted DMG
            let appBundle = try findAppBundle(in: mount)

            // Replace existing app
            try installApp(from: appBundle)

            // Post-install: reset TCC and update Launch Services
            await resetAccessibility()
            await updateLaunchServices()

            // Unmount and cleanup
            await unmountDMG(at: mount.path)
            mountPoint = nil
            try? FileManager.default.removeItem(at: tempDir)

            await MainActor.run { state = .readyToRelaunch }

        } catch {
            // Cleanup on failure
            if let mp = mountPoint {
                await unmountDMG(at: mp.path)
            }
            try? FileManager.default.removeItem(at: tempDir)

            if case .idle = await currentState() {
                // Was cancelled, don't overwrite idle state
                return
            }
            await MainActor.run { state = .failed(error.localizedDescription) }
        }
    }

    /// Cancel an in-progress download
    func cancelUpdate() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadContinuation?.resume(throwing: CancellationError())
        downloadContinuation = nil
        state = .idle
    }

    /// Relaunch the app from the newly installed bundle
    func relaunchApp() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: appPath,
                                          configuration: config) { _, error in
            if let error = error {
                Logger.shared.error("Failed to relaunch app: \(error)")
            } else {
                DispatchQueue.main.async {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    // MARK: - Private Helpers

    @MainActor
    private func currentState() -> UpdateState {
        state
    }

    // MARK: - Download

    private func downloadDMG(from url: URL, to directory: URL) async throws -> URL {
        let dmgPath = directory.appendingPathComponent(url.lastPathComponent)

        return try await withCheckedThrowingContinuation { continuation in
            self.downloadContinuation = continuation
            let task = self.downloadSession.downloadTask(with: url)
            self.downloadTask = task
            task.resume()
        }
    }

    // MARK: - Checksum Verification

    private func verifyChecksum(dmgPath: URL, checksumsURL: URL, dmgFilename: String) async throws {
        // Download checksums.txt
        let (data, _) = try await URLSession.shared.data(from: checksumsURL)
        guard let checksumText = String(data: data, encoding: .utf8) else {
            Logger.shared.warning("Could not parse checksums.txt, skipping verification")
            return
        }

        // Parse checksums.txt (format: "sha256hash  filename" per line)
        let expectedHash = Self.parseChecksum(from: checksumText, forFile: dmgFilename)
        guard let expected = expectedHash else {
            Logger.shared.warning("DMG filename not found in checksums.txt, skipping verification")
            return
        }

        // Compute SHA256 of downloaded DMG
        let actualHash = try Self.sha256(ofFile: dmgPath)

        guard actualHash.lowercased() == expected.lowercased() else {
            try? FileManager.default.removeItem(at: dmgPath)
            throw NSError(domain: "AutoUpdateService", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Checksum verification failed. Expected \(expected), got \(actualHash)."])
        }

        Logger.shared.info("Checksum verified for \(dmgFilename)")
    }

    /// Parse a checksums.txt file to find the hash for a given filename
    static func parseChecksum(from text: String, forFile filename: String) -> String? {
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 && parts[1] == filename {
                return parts[0]
            }
        }
        return nil
    }

    /// Compute SHA256 hash of a file
    static func sha256(ofFile url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }

        var hasher = SHA256()
        let bufferSize = 1024 * 1024 // 1MB chunks
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: bufferSize)
            guard !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - DMG Operations

    private func mountDMG(at dmgPath: String, mountPoint: String) async throws {
        try FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)
        _ = try await runProcess("/usr/bin/hdiutil", ["attach", dmgPath, "-nobrowse", "-readonly", "-mountpoint", mountPoint])
    }

    private func unmountDMG(at mountPoint: String) async {
        do {
            _ = try await runProcess("/usr/bin/hdiutil", ["detach", mountPoint, "-force"])
        } catch {
            Logger.shared.warning("Failed to unmount DMG: \(error)")
        }
    }

    private func findAppBundle(in mountPoint: URL) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw NSError(domain: "AutoUpdateService", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "No .app bundle found in the downloaded DMG."])
        }
        return app
    }

    // MARK: - Installation

    private func installApp(from source: URL) throws {
        let fm = FileManager.default

        // Ensure ~/Applications exists
        try fm.createDirectory(at: installDir, withIntermediateDirectories: true)

        // Remove existing app bundle
        if fm.fileExists(atPath: appPath.path) {
            try fm.removeItem(at: appPath)
        }

        // Copy new app bundle
        try fm.copyItem(at: source, to: appPath)

        Logger.shared.info("Installed app to \(appPath.path)")
    }

    // MARK: - Post-Install

    private func resetAccessibility() async {
        do {
            _ = try await runProcess("/usr/bin/tccutil", ["reset", "Accessibility", bundleID])
            Logger.shared.info("Reset Accessibility TCC entry for \(bundleID)")
        } catch {
            Logger.shared.warning("Failed to reset TCC: \(error). Permission re-grant may require manual action.")
        }
    }

    private func updateLaunchServices() async {
        do {
            _ = try await runProcess(Self.lsregisterPath, ["-f", appPath.path])
            Logger.shared.info("Updated Launch Services for \(appPath.path)")
        } catch {
            Logger.shared.warning("Failed to update Launch Services: \(error)")
        }
    }

    // MARK: - Process Runner

    private func runProcess(_ executable: String, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outData, encoding: .utf8) ?? ""
                    let errOutput = String(data: errData, encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else {
                        let message = errOutput.isEmpty ? output : errOutput
                        continuation.resume(throwing: NSError(domain: "AutoUpdateService", code: Int(process.terminationStatus),
                                                             userInfo: [NSLocalizedDescriptionKey: "\(executable) failed: \(message)"]))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension AutoUpdateService: URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            self.state = .downloading(progress: progress)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Move file from temp location before it's deleted
        let destDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LookMaNoHands-update-download")
        let dest = destDir.appendingPathComponent(downloadTask.originalRequest?.url?.lastPathComponent ?? "update.dmg")

        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            downloadContinuation?.resume(returning: dest)
            downloadContinuation = nil
        } catch {
            downloadContinuation?.resume(throwing: error)
            downloadContinuation = nil
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            downloadContinuation?.resume(throwing: error)
            downloadContinuation = nil
        }
    }
}
