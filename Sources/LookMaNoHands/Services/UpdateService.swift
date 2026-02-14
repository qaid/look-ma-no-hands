import Foundation

/// Checks GitHub for new commits on main branch
class UpdateService {

    // MARK: - Configuration

    private let repoOwner = "qaid"
    private let repoName = "look-ma-no-hands"
    private let session = URLSession.shared

    // MARK: - File Classification

    private static let nonFunctionalPatterns: [String] = [
        ".md",                          // All markdown files
        ".claude/",                     // Claude project directory
        "CLAUDE.md",                    // Claude config at root
        ".gitignore",                   // Git config
        ".gitattributes",               // Git config
        ".github/ISSUE_TEMPLATE/",      // GitHub templates
        ".github/PULL_REQUEST_TEMPLATE/", // GitHub templates
        ".github/",                     // GitHub markdown docs (with .md check)
        "LICENSE",                      // License files
        "COPYING",                      // License files
        ".vscode/",                     // Editor config
        ".idea/",                       // Editor config
        ".context/",                    // Conductor workspace context
    ]

    private static let functionalPatterns: [String] = [
        "Sources/",                     // Swift source (when .swift extension)
        "Package.swift",                // Package manifest
        "scripts/",                     // Build/deploy scripts
        ".github/workflows/",           // CI/CD (when .yml/.yaml)
        ".entitlements",                // Entitlements files
        "Info.plist",                   // Info.plist files
    ]

    // MARK: - Types

    struct CommitSummary {
        let sha: String
        let shortSHA: String
        let message: String
        let author: String
        let date: String
    }

    struct UpdateInfo {
        let commitCount: Int
        let latestCommitSHA: String
        let commitSummaries: [CommitSummary]
        let compareURL: String
        let repoURL: String
    }

    enum UpdateError: LocalizedError {
        case invalidURL
        case noBuildInfo
        case apiRateLimited
        case networkError(String)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid GitHub API URL"
            case .noBuildInfo:
                return "Build information not available"
            case .apiRateLimited:
                return "GitHub API rate limit exceeded. Try again later."
            case .networkError(let reason):
                return "Network error: \(reason)"
            case .parseError(let reason):
                return "Failed to parse response: \(reason)"
            }
        }
    }

    // MARK: - GitHub API Response

    private struct GitHubCommit: Codable {
        let sha: String
        let commit: CommitDetails

        struct CommitDetails: Codable {
            let message: String
            let author: Author

            struct Author: Codable {
                let name: String
                let date: String
            }
        }
    }

    private struct GitHubCompareResponse: Codable {
        let aheadBy: Int
        let behindBy: Int
        let status: String
        let commits: [GitHubCommit]

        enum CodingKeys: String, CodingKey {
            case aheadBy = "ahead_by"
            case behindBy = "behind_by"
            case status
            case commits
        }
    }

    private struct GitHubFile: Codable {
        let filename: String
        let status: String
        let additions: Int
        let deletions: Int
        let changes: Int
    }

    private struct GitHubCommitDetailResponse: Codable {
        let sha: String
        let files: [GitHubFile]
    }

    private struct CommitClassification {
        let isFunctional: Bool
        let functionalFileCount: Int
        let nonFunctionalFileCount: Int
    }

    private struct ClassifiedCommit {
        let commit: GitHubCommit
        let classification: CommitClassification
    }

    // MARK: - Private Methods - File Classification

    private func isNonFunctionalFile(_ filename: String) -> Bool {
        // Check if file ends with .md (any markdown file)
        if filename.hasSuffix(".md") {
            return true
        }

        // Check against non-functional patterns
        for pattern in Self.nonFunctionalPatterns {
            if pattern.hasSuffix("/") {
                // Directory pattern - check if path starts with it
                if filename.hasPrefix(pattern) {
                    return true
                }
            } else {
                // Exact match or contains pattern
                if filename == pattern || filename.contains(pattern) {
                    return true
                }
            }
        }

        return false
    }

    private func isFunctionalFile(_ filename: String) -> Bool {
        // First check if it's explicitly non-functional
        if isNonFunctionalFile(filename) {
            return false
        }

        // Check against functional patterns
        for pattern in Self.functionalPatterns {
            if pattern.hasSuffix("/") {
                // Directory pattern
                if filename.hasPrefix(pattern) {
                    return true
                }
            } else {
                // Exact match or extension check
                if filename == pattern || filename.contains(pattern) || filename.hasSuffix(pattern) {
                    return true
                }
            }
        }

        // Default to functional (safe default - avoid missing important changes)
        return true
    }

    private func classifyCommit(files: [GitHubFile]) -> CommitClassification {
        var functionalCount = 0
        var nonFunctionalCount = 0

        for file in files {
            if isFunctionalFile(file.filename) {
                functionalCount += 1
            } else {
                nonFunctionalCount += 1
            }
        }

        return CommitClassification(
            isFunctional: functionalCount > 0,
            functionalFileCount: functionalCount,
            nonFunctionalFileCount: nonFunctionalCount
        )
    }

    // MARK: - Public Methods

    /// Get the current app version from the bundle
    func getCurrentVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Get the short commit SHA from build info
    func getBuildCommitShort() -> String {
        BuildInfo.commitShortSHA
    }

    /// Get the build date
    func getBuildDate() -> String {
        BuildInfo.buildDate
    }

    /// Check if this is a development build
    func isDevelopmentBuild() -> Bool {
        BuildInfo.commitSHA == "development"
    }

    // MARK: - Private Methods - Commit Classification

    private func fetchCommitFiles(sha: String) async throws -> [GitHubFile] {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/commits/\(sha)"
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

        // Check for rate limiting
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 403 {
                if let remaining = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
                   remaining == "0" {
                    throw UpdateError.apiRateLimited
                }
            }
            if httpResponse.statusCode != 200 {
                throw UpdateError.networkError("HTTP \(httpResponse.statusCode)")
            }
        }

        let decoder = JSONDecoder()
        do {
            let commitDetail = try decoder.decode(GitHubCommitDetailResponse.self, from: data)
            return commitDetail.files
        } catch {
            throw UpdateError.parseError(error.localizedDescription)
        }
    }

    private func classifyCommits(_ commits: [GitHubCommit]) async throws -> [ClassifiedCommit] {
        try await withThrowingTaskGroup(of: ClassifiedCommit.self) { group in
            var results: [ClassifiedCommit] = []

            // Launch parallel tasks to fetch and classify each commit
            for commit in commits {
                group.addTask {
                    let files = try await self.fetchCommitFiles(sha: commit.sha)
                    let classification = self.classifyCommit(files: files)
                    return ClassifiedCommit(commit: commit, classification: classification)
                }
            }

            // Collect results in order
            for try await classified in group {
                results.append(classified)
            }

            return results
        }
    }

    /// Check GitHub for new commits on main branch. Returns nil if up to date.
    func checkForUpdates() async throws -> UpdateInfo? {
        // Don't check for updates in development builds
        guard !isDevelopmentBuild() else {
            throw UpdateError.noBuildInfo
        }

        let buildSHA = BuildInfo.commitSHA
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/compare/\(buildSHA)...main"
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

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 403 {
                // Check if it's a rate limit issue
                if let remaining = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
                   remaining == "0" {
                    throw UpdateError.apiRateLimited
                }
            }
            if httpResponse.statusCode != 200 {
                throw UpdateError.networkError("HTTP \(httpResponse.statusCode)")
            }
        }

        let decoder = JSONDecoder()
        let compareResponse: GitHubCompareResponse
        do {
            compareResponse = try decoder.decode(GitHubCompareResponse.self, from: data)
        } catch {
            throw UpdateError.parseError(error.localizedDescription)
        }

        // If ahead_by is 0, we're up to date
        guard compareResponse.aheadBy > 0 else {
            return nil
        }

        // Classify commits and filter out non-functional ones
        let functionalCommits: [GitHubCommit]
        do {
            let classifiedCommits = try await classifyCommits(compareResponse.commits)
            functionalCommits = classifiedCommits
                .filter { $0.classification.isFunctional }
                .map { $0.commit }

            Logger.shared.info("Classified \(compareResponse.commits.count) commits: \(functionalCommits.count) functional, \(compareResponse.commits.count - functionalCommits.count) non-functional")
        } catch {
            // Graceful fallback: if classification fails, show all commits
            Logger.shared.warning("Failed to classify commits: \(error). Showing all commits.")
            functionalCommits = compareResponse.commits
        }

        // If no functional commits, return nil (no update needed)
        guard !functionalCommits.isEmpty else {
            Logger.shared.info("No functional commits found. No update notification needed.")
            return nil
        }

        // Extract commit summaries from functional commits only
        let summaries = functionalCommits.map { commit in
            CommitSummary(
                sha: commit.sha,
                shortSHA: String(commit.sha.prefix(7)),
                message: commit.commit.message.split(separator: "\n").first.map(String.init) ?? "",
                author: commit.commit.author.name,
                date: commit.commit.author.date
            )
        }

        let compareURL = "https://github.com/\(repoOwner)/\(repoName)/compare/\(buildSHA)...main"
        let repoURL = "https://github.com/\(repoOwner)/\(repoName)"

        return UpdateInfo(
            commitCount: functionalCommits.count,
            latestCommitSHA: functionalCommits.last?.sha ?? "",
            commitSummaries: summaries,
            compareURL: compareURL,
            repoURL: repoURL
        )
    }
}
