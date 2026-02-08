import Foundation

/// Checks GitHub Releases for new versions and downloads updates
class UpdateService {

    // MARK: - Configuration

    private let repoOwner = "qaid"
    private let repoName = "look-ma-no-hands"
    private let session = URLSession.shared

    // MARK: - Types

    struct UpdateInfo {
        let version: String
        let releaseNotes: String
        let downloadURL: URL
        let publishedAt: String
    }

    enum UpdateError: LocalizedError {
        case invalidURL
        case noReleaseFound
        case noCompatibleAsset
        case downloadFailed(String)
        case networkError(String)
        case invalidSignature
        case downloadTooLarge
        case invalidContentType

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid GitHub API URL"
            case .noReleaseFound:
                return "No releases found"
            case .noCompatibleAsset:
                return "No DMG download found for this release"
            case .downloadFailed(let reason):
                return "Download failed: \(reason)"
            case .networkError(let reason):
                return "Network error: \(reason)"
            case .invalidSignature:
                return "Update file signature verification failed"
            case .downloadTooLarge:
                return "Download exceeds maximum size limit"
            case .invalidContentType:
                return "Downloaded file is not a valid disk image"
            }
        }
    }

    // MARK: - GitHub API Response

    private struct GitHubRelease: Codable {
        let tagName: String
        let name: String?
        let body: String?
        let publishedAt: String?
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case publishedAt = "published_at"
            case assets
        }

        struct Asset: Codable {
            let name: String
            let browserDownloadUrl: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
            }
        }
    }

    // MARK: - Semantic Version

    struct SemanticVersion: Comparable {
        let major: Int
        let minor: Int
        let patch: Int

        static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
            if lhs.major != rhs.major { return lhs.major < rhs.major }
            if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
            return lhs.patch < rhs.patch
        }

        /// Parse a version string like "1.0", "1.0.0", or "v1.0.0"
        static func parse(_ string: String) -> SemanticVersion? {
            let cleaned = string.hasPrefix("v") ? String(string.dropFirst()) : string
            let parts = cleaned.split(separator: ".").compactMap { Int($0) }
            guard parts.count >= 2 else { return nil }
            return SemanticVersion(
                major: parts[0],
                minor: parts[1],
                patch: parts.count >= 3 ? parts[2] : 0
            )
        }
    }

    // MARK: - Public Methods

    /// Get the current app version from the bundle
    func getCurrentVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Check GitHub for a newer release. Returns nil if up to date.
    func checkForUpdates() async throws -> UpdateInfo? {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else {
            throw UpdateError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UpdateError.networkError(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if httpResponse.statusCode == 404 {
                throw UpdateError.noReleaseFound
            }
            throw UpdateError.networkError("HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        let release: GitHubRelease
        do {
            release = try decoder.decode(GitHubRelease.self, from: data)
        } catch {
            throw UpdateError.networkError("Failed to parse release: \(error.localizedDescription)")
        }

        // Compare versions
        let currentVersion = getCurrentVersion()
        guard let current = SemanticVersion.parse(currentVersion),
              let latest = SemanticVersion.parse(release.tagName) else {
            // Can't parse versions - treat as no update
            return nil
        }

        guard latest > current else {
            return nil // Up to date
        }

        // Find DMG asset
        guard let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }),
              let downloadURL = URL(string: dmgAsset.browserDownloadUrl) else {
            throw UpdateError.noCompatibleAsset
        }

        return UpdateInfo(
            version: release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName,
            releaseNotes: release.body ?? "No release notes available.",
            downloadURL: downloadURL,
            publishedAt: release.publishedAt ?? ""
        )
    }

    /// Download a DMG update to ~/Downloads and return the local file URL
    func downloadUpdate(from url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.timeoutInterval = 300  // 5 minute timeout for large downloads

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UpdateError.downloadFailed(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw UpdateError.downloadFailed("HTTP \(httpResponse.statusCode)")
        }

        // Security: Validate download size (max 500MB)
        let maxSize = 500 * 1024 * 1024
        guard data.count <= maxSize else {
            throw UpdateError.downloadTooLarge
        }

        // Security: Validate content type
        if let mimeType = response.mimeType, mimeType != "application/x-apple-diskimage" {
            Logger.shared.warning("Unexpected content type: \(mimeType)", category: .update)
        }

        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileName = url.lastPathComponent
        let destinationURL = downloadsURL.appendingPathComponent(fileName)

        // Remove existing file if present
        try? FileManager.default.removeItem(at: destinationURL)

        do {
            try data.write(to: destinationURL)
        } catch {
            throw UpdateError.downloadFailed("Could not save file: \(error.localizedDescription)")
        }

        // Security: Verify code signature before returning
        try await verifyDMGSignature(destinationURL)

        return destinationURL
    }

    // MARK: - Private Methods

    /// Verify the code signature of a downloaded DMG file
    private func verifyDMGSignature(_ fileURL: URL) async throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["--verify", "--deep", "--strict", fileURL.path]

        let pipe = Pipe()
        task.standardError = pipe
        task.standardOutput = pipe

        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "unknown error"
            Logger.shared.error("codesign verification failed: \(output)", category: .update)
            throw UpdateError.invalidSignature
        }

        Logger.shared.info("✅ Update signature verified successfully", category: .update)
    }
}
