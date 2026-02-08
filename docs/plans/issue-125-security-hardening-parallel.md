# Issue #125: Security Hardening - Parallel Execution Plan

## Overview

This plan addresses 14 security improvements from the comprehensive audit. The work is divided into **5 independent workstreams** that can be executed by separate Claude agents in parallel, followed by 1 sequential workstream that depends on Workstream 2.

**Already Complete:** 5 items (graceful shutdown, update signature verification, temp file handling, update size limits, copyright year)

**To Implement:** 9 items across 6 workstreams

---

## Parallelization Strategy

```
┌─────────────────────────────────────────────────────────────┐
│                    PARALLEL EXECUTION                        │
├─────────────────┬─────────────────┬─────────────────────────┤
│  Workstream 1   │  Workstream 2   │  Workstream 3          │
│  Model Security │  Build Scripts  │  Runtime Security      │
│  (1 file)       │  (2 files)      │  (2 files)             │
│                 │                 │                         │
│  DEP-002        │  BUILD-004      │  CODE-007               │
│  CODE-011       │  BUILD-002      │  CODE-008               │
│  CODE-004       │                 │                         │
└─────────────────┴─────────────────┴─────────────────────────┘
                          │
                          │ Workstream 2 completes
                          ↓
                  ┌───────────────────┐
                  │  Workstream 5     │
                  │  Production       │
                  │  Hardening        │
                  │  (depends on WS2) │
                  │                   │
                  │  BUILD-003        │
                  │  ARTIFACT-001     │
                  └───────────────────┘

┌─────────────────────────────────────────────────────────────┐
│             PARALLEL (Independent of above)                  │
├─────────────────────────────────────────────────────────────┤
│              Workstream 4: CI/CD Security                    │
│              (4 files: workflows, configs)                   │
│                                                              │
│              CICD-001, CICD-002, DEP-001                     │
└─────────────────────────────────────────────────────────────┘
```

---

## Workstream 1: Model Download Security 🔴 HIGH PRIORITY

**Agent Responsibility:** Secure Whisper model downloads from tampering, oversized files, and malicious archives

**Files to Modify:**
- `Sources/LookMaNoHands/Services/WhisperService.swift` (lines 220-297)

**Issues Addressed:**
- **DEP-002:** Add SHA256 checksum verification
- **CODE-011:** Add download size validation
- **CODE-004:** Secure process execution (safe unzip)

**Dependencies:** NONE - Can start immediately

### Implementation Details

#### Step 1: Add Model Metadata (Top of WhisperService.swift)

```swift
// Add after imports, before class definition

/// Known SHA256 checksums for official Whisper models
/// Source: https://huggingface.co/ggerganov/whisper.cpp
private static let modelChecksums: [String: String] = [
    // TODO: Compute actual SHA256 hashes from HuggingFace
    "ggml-tiny.bin": "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21",
    "ggml-base.bin": "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe",
    "ggml-small.bin": "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b",
    "ggml-medium.bin": "f9d4bcee140d9e2e5c9a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3",
    "ggml-large-v3.bin": "64d1b2e1a8f9e4c7d3b6a5f8e9d0c1b2a3f4e5d6c7b8a9f0e1d2c3b4a5f6e7d8"
]

/// Expected file sizes (bytes) with 10% tolerance
private static let modelSizes: [String: (min: Int64, max: Int64)] = [
    "ggml-tiny.bin": (70_000_000, 80_000_000),          // ~75MB
    "ggml-base.bin": (135_000_000, 150_000_000),        // ~142MB
    "ggml-small.bin": (440_000_000, 490_000_000),       // ~466MB
    "ggml-medium.bin": (1_400_000_000, 1_600_000_000), // ~1.5GB
    "ggml-large-v3.bin": (2_900_000_000, 3_300_000_000) // ~3.1GB
]
```

#### Step 2: Add SHA256 Verification Function

```swift
import CommonCrypto  // Add to imports

/// Verify file integrity using SHA256 checksum
private static func verifyChecksum(_ fileURL: URL, modelName: String) throws {
    let modelFileName = "ggml-\(modelName).bin"

    guard let expectedHash = modelChecksums[modelFileName] else {
        print("⚠️  No checksum available for \(modelFileName), skipping verification")
        print("   (This is expected for user-added custom models)")
        return
    }

    // Read file and compute SHA256
    let data = try Data(contentsOf: fileURL)
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { buffer in
        _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
    }

    let computedHash = hash.map { String(format: "%02x", $0) }.joined()

    guard computedHash == expectedHash else {
        throw WhisperError.downloadFailed(
            "Checksum verification failed for \(modelFileName)\n" +
            "Expected: \(expectedHash)\n" +
            "Got: \(computedHash)\n" +
            "⚠️  This may indicate a corrupted download or tampering."
        )
    }

    print("✅ Checksum verified: \(modelFileName)")
}
```

#### Step 3: Add Size Validation Function

```swift
/// Validate download size is within expected range
private static func validateSize(_ fileURL: URL, modelName: String) throws {
    let modelFileName = "ggml-\(modelName).bin"

    guard let (minSize, maxSize) = modelSizes[modelFileName] else {
        print("⚠️  No size range for \(modelFileName), skipping validation")
        return
    }

    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    guard let fileSize = attributes[.size] as? Int64 else {
        throw WhisperError.downloadFailed("Could not determine file size")
    }

    guard fileSize >= minSize && fileSize <= maxSize else {
        throw WhisperError.downloadFailed(
            "File size out of expected range for \(modelFileName)\n" +
            "Expected: \(minSize)-\(maxSize) bytes\n" +
            "Got: \(fileSize) bytes\n" +
            "⚠️  This may indicate a malicious or corrupted file."
        )
    }

    print("✅ Size validated: \(modelFileName) (\(fileSize) bytes)")
}
```

#### Step 4: Add Safe Unzip Function

```swift
/// Safely extract zip archive with path traversal and zip bomb protection
private static func safeUnzip(_ zipURL: URL, to destDir: URL) throws {
    // Validate destination exists
    guard FileManager.default.fileExists(atPath: destDir.path) else {
        throw WhisperError.downloadFailed("Destination directory does not exist")
    }

    // Setup unzip process
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-o", zipURL.path, "-d", destDir.path]
    process.currentDirectoryURL = destDir

    // Capture output for error reporting
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()

    // Wait with 10-second timeout (Core ML zips can be slow)
    let deadline = Date().addingTimeInterval(10)
    while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.1)
    }

    // Check if timeout occurred
    if process.isRunning {
        process.terminate()
        throw WhisperError.downloadFailed(
            "Unzip operation timed out after 10 seconds. " +
            "This may indicate a zip bomb or corrupted archive."
        )
    }

    // Check exit status
    guard process.terminationStatus == 0 else {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? "unknown error"
        throw WhisperError.downloadFailed("Unzip failed: \(output)")
    }

    // Validate extracted files don't escape destination (path traversal check)
    let extractedFiles = try FileManager.default.contentsOfDirectory(
        at: destDir,
        includingPropertiesForKeys: [.isSymbolicLinkKey],
        options: []
    )

    for file in extractedFiles {
        // Resolve symlinks to detect path traversal
        let resolved = file.resolvingSymlinksInPath()
        if !resolved.path.hasPrefix(destDir.path) {
            // Path traversal detected - cleanup and abort
            print("⚠️  Path traversal detected: \(file.path) -> \(resolved.path)")
            try? FileManager.default.removeItem(at: destDir)
            throw WhisperError.downloadFailed(
                "Security violation: Archive contains path traversal attempt"
            )
        }
    }

    print("✅ Archive extracted safely to \(destDir.path)")
}
```

#### Step 5: Update downloadModel() Function (Lines 220-297)

Replace the existing download logic with security-enhanced version:

```swift
static func downloadModel(named modelName: String, progress: @escaping (Double) -> Void) async throws {
    let modelFileName = "ggml-\(modelName).bin"
    let modelPath = getModelPath(modelName: modelName)

    // Skip if already exists
    if FileManager.default.fileExists(atPath: modelPath.path) {
        print("Model \(modelFileName) already exists at \(modelPath.path)")
        return
    }

    // Setup download URL
    let baseURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
    let downloadURL = URL(string: "\(baseURL)/\(modelFileName)")!

    print("Downloading \(modelFileName) from \(downloadURL)")

    let session = URLSession.shared
    let (tempURL, response) = try await session.download(from: downloadURL, delegate: nil)

    // Validate HTTP response
    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw WhisperError.downloadFailed("HTTP request failed for \(modelFileName)")
    }

    // SECURITY: Validate Content-Length if present
    if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
       let expectedSize = Int64(contentLength) {
        if let (minSize, maxSize) = modelSizes[modelFileName] {
            if expectedSize < minSize || expectedSize > maxSize {
                throw WhisperError.downloadFailed(
                    "Content-Length (\(expectedSize) bytes) out of expected range for \(modelFileName)"
                )
            }
        }
    }

    // SECURITY: Validate actual downloaded size
    try validateSize(tempURL, modelName: modelName)

    // SECURITY: Verify SHA256 checksum
    try verifyChecksum(tempURL, modelName: modelName)

    // Move to final location
    let modelDir = modelPath.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: tempURL, to: modelPath)

    print("✅ Model downloaded and verified: \(modelPath.path)")

    // Download Core ML version if available
    let coreMLFileName = "ggml-\(modelName)-encoder.mlmodelc.zip"
    let coreMLURL = URL(string: "\(baseURL)/\(coreMLFileName)")!

    do {
        let (coreMLTempURL, coreMLResponse) = try await session.download(from: coreMLURL, delegate: nil)

        if let httpResponse = coreMLResponse as? HTTPURLResponse, httpResponse.statusCode == 200 {
            // Move to temp location for extraction
            let tempZipPath = modelDir.appendingPathComponent("temp-coreml.zip")
            try? FileManager.default.removeItem(at: tempZipPath)
            try FileManager.default.moveItem(at: coreMLTempURL, to: tempZipPath)

            // SECURITY: Use safe unzip with validation
            try safeUnzip(tempZipPath, to: modelDir)

            // Cleanup zip file
            try? FileManager.default.removeItem(at: tempZipPath)

            print("✅ Core ML encoder downloaded and extracted")
        }
    } catch {
        print("ℹ️  Core ML encoder not available (CPU-only mode will work): \(error)")
    }
}
```

#### Step 6: Add WhisperError Case

In the `WhisperError` enum, ensure there's a case for checksum mismatch (if not already present):

```swift
enum WhisperError: Error {
    case downloadFailed(String)
    case checksumMismatch  // Add if not present
    // ... other cases
}
```

### Testing Instructions

1. **Test SHA256 Verification:**
   ```bash
   # Download official model and compute actual SHA256
   curl -L https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin -o /tmp/ggml-tiny.bin
   shasum -a 256 /tmp/ggml-tiny.bin
   # Update modelChecksums with actual hash
   ```

2. **Test Normal Download:** Download each model (tiny, base, small) and verify success

3. **Test Corrupted File:**
   ```bash
   # Manually corrupt a downloaded model
   echo "corrupted" >> ~/Library/Application\ Support/LookMaNoHands/models/ggml-tiny.bin
   # Attempt to load - should fail with checksum error
   ```

4. **Test Size Validation:** Modify a model file to exceed size limits, should fail

5. **Test Zip Bomb Protection:** Create a test zip with extreme compression, should timeout

6. **Test Path Traversal:**
   ```bash
   # Create malicious zip with ../ paths
   mkdir -p /tmp/evil && cd /tmp/evil
   mkdir -p subdir
   echo "malicious" > ../../../../tmp/evil-file.txt
   zip -r evil.zip subdir ../../../../tmp/evil-file.txt
   # Attempt to extract - should detect and fail
   ```

### Success Criteria

- ✅ All official models download with SHA256 verification
- ✅ Corrupted downloads rejected before use
- ✅ Oversized files blocked
- ✅ Core ML zips extracted safely with timeout protection
- ✅ Path traversal attempts detected and blocked
- ✅ User-added custom models still work (skip verification with warning)

---

## Workstream 2: Build Script Security 🟡 MEDIUM PRIORITY

**Agent Responsibility:** Make deployment scripts safer and preserve user settings

**Files to Modify:**
- `deploy.sh` (lines 32, 63, 67-72)
- `scripts/create-dmg.sh` (lines 15, 39, 51)

**Issues Addressed:**
- **BUILD-004:** Respect user settings during deployment
- **BUILD-002:** Add safety checks to destructive file operations

**Dependencies:** NONE - Can start immediately

### Implementation Details

#### Change 1: deploy.sh - Preserve User Settings

**Replace lines 67-72** with flag-based reset:

```bash
# Add near top of file (after #!/bin/bash and comments)
RESET_DEFAULTS=false
if [[ "$1" == "--reset-defaults" ]]; then
    RESET_DEFAULTS=true
    echo "🧹 Will reset app defaults (--reset-defaults flag provided)"
fi

# ... existing code ...

# Replace lines 67-72 (icon cache section)
echo ""
echo "=== Icon Cache & App Defaults ==="

# Icon cache cleanup (still unconditional - safe system cache)
if [ -d ~/Library/Caches/com.apple.iconservices.store ]; then
    echo "🔄 Clearing icon cache..."
    rm -rf ~/Library/Caches/com.apple.iconservices.store
fi

# App defaults (now conditional)
if [ "$RESET_DEFAULTS" = true ]; then
    echo "🧹 Resetting app defaults..."
    defaults delete com.lookmanohands.app 2>/dev/null || true
    defaults write com.lookmanohands.app triggerKey "Right Option"
    echo "   ✅ App defaults reset to factory settings"
else
    echo "ℹ️  Preserving existing app defaults"
    echo "   (use './deploy.sh --reset-defaults' to reset)"
fi
```

#### Change 2: deploy.sh - Safe File Operations

**Replace line 32** (app bundle removal) with existence check:

```bash
# OLD:
rm -rf ~/Applications/LookMaNoHands.app

# NEW:
if [ -d ~/Applications/LookMaNoHands.app ]; then
    echo "🗑️  Removing old app bundle..."
    rm -rf ~/Applications/LookMaNoHands.app
else
    echo "ℹ️  No existing app bundle to remove"
fi
```

**Update line 63** (icon cache) - already shown above in Change 1

#### Change 3: create-dmg.sh - Safe File Operations

**Replace line 15:**
```bash
# OLD:
rm -rf "${APP_PATH}"

# NEW:
[ -d "${APP_PATH}" ] && rm -rf "${APP_PATH}"
```

**Replace lines 39 and 51** (duplicate cleanup):
```bash
# OLD (line 39):
rm -rf "${DMG_TEMP}"

# NEW (line 39):
[ -d "${DMG_TEMP}" ] && rm -rf "${DMG_TEMP}"

# Line 51 is duplicate - remove entirely (line 39 already cleans up)
```

**Replace line 17:**
```bash
# OLD:
rm -f "${BUILD_DIR}/${DMG_NAME}"

# NEW:
[ -f "${BUILD_DIR}/${DMG_NAME}" ] && rm -f "${BUILD_DIR}/${DMG_NAME}"
```

### Testing Instructions

1. **Test Settings Preservation:**
   ```bash
   # Set custom trigger key in app settings
   defaults write com.lookmanohands.app triggerKey "Caps Lock"

   # Deploy without flag
   ./deploy.sh

   # Check setting preserved
   defaults read com.lookmanohands.app triggerKey
   # Should still be "Caps Lock"
   ```

2. **Test Settings Reset:**
   ```bash
   # Deploy with reset flag
   ./deploy.sh --reset-defaults

   # Check setting reset
   defaults read com.lookmanohands.app triggerKey
   # Should be "Right Option"
   ```

3. **Test Safe rm Operations:**
   ```bash
   # Deploy with no existing app - should not error
   ./deploy.sh

   # Deploy with existing app - should cleanly remove
   ./deploy.sh

   # Create DMG with no existing files - should not error
   ./scripts/create-dmg.sh
   ```

### Success Criteria

- ✅ User settings preserved across normal deployments
- ✅ `--reset-defaults` flag correctly resets settings
- ✅ No errors when deploying to clean system
- ✅ No errors when files don't exist
- ✅ Existing app correctly replaced

---

## Workstream 3: Runtime Security Fixes 🟡 MEDIUM PRIORITY

**Agent Responsibility:** Fix permission checks and remove PII leaks from crash reports

**Files to Modify:**
- `Sources/LookMaNoHands/Services/SystemAudioRecorder.swift` (lines 42-50)
- `Sources/LookMaNoHands/Services/CrashReporter.swift` (lines 157-162)

**Issues Addressed:**
- **CODE-007:** Fix screen recording permission check
- **CODE-008:** Remove transcription character count from crash reports

**Dependencies:** NONE - Can start immediately

### Implementation Details

#### Fix 1: SystemAudioRecorder.swift - Accurate Permission Check

**Replace lines 42-50:**

```swift
// OLD:
static func hasPermission() -> Bool {
    if #available(macOS 14.0, *) {
        return true // Permission check simplified in macOS 14+
    } else {
        return true
    }
}

// NEW:
static func hasPermission() -> Bool {
    // Use CGPreflightScreenCaptureAccess to check actual permission state
    // This returns true if permission is already granted, false otherwise
    return CGPreflightScreenCaptureAccess()
}
```

**Context:** This one-line fix provides accurate permission status instead of always returning `true`. The `CGPreflightScreenCaptureAccess()` function checks whether the app currently has screen recording permission granted without triggering the permission dialog.

#### Fix 2: CrashReporter.swift - Remove Character Count Leak

**Replace lines 157-162:**

```swift
// OLD:
if let lastTranscription = state.lastTranscription {
    report += """
    Last Transcription: [REDACTED - \(lastTranscription.count) characters]
    """
}

// NEW:
if state.lastTranscription != nil {
    report += """
    Last Transcription: [REDACTED]

    """
}
```

**Rationale:** Character count could leak sensitive information (e.g., distinguishing between "yes" and "my credit card is 1234-5678-9012-3456"). Complete redaction is safer.

### Testing Instructions

#### Test CODE-007 (Permission Check):

1. **Fresh Install Test:**
   ```bash
   # On a clean macOS VM or new user account
   # Launch app
   # Check SystemAudioRecorder.hasPermission()
   # Should return false before permission granted
   ```

2. **Permission Grant Test:**
   ```bash
   # Grant Screen Recording permission in System Settings
   # Check SystemAudioRecorder.hasPermission()
   # Should return true
   ```

3. **Permission Revoke Test:**
   ```bash
   # Revoke permission in System Settings
   # Check SystemAudioRecorder.hasPermission()
   # Should return false
   ```

4. **Meeting Mode Integration:**
   ```bash
   # Start meeting mode
   # If permission not granted, should show proper prompt
   # After granting, should work correctly
   ```

#### Test CODE-008 (Crash Report Privacy):

1. **Trigger Test Crash:**
   ```swift
   // Add temporary test crash button in debug builds
   #if DEBUG
   Button("Test Crash") {
       fatalError("Test crash for privacy verification")
   }
   #endif
   ```

2. **Verify Crash Report:**
   ```bash
   # After crash, check log file
   cat ~/Library/Logs/LookMaNoHands/crashes/*.txt

   # Should show:
   # Last Transcription: [REDACTED]
   #
   # Should NOT show:
   # Last Transcription: [REDACTED - 47 characters]
   ```

3. **Test Without Transcription:**
   ```bash
   # Trigger crash without any active transcription
   # Should not include transcription line at all
   ```

### Success Criteria

- ✅ `hasPermission()` returns accurate state (false on fresh install)
- ✅ Permission check updates when user grants/revokes in System Settings
- ✅ Meeting mode properly detects permission state
- ✅ Crash reports show `[REDACTED]` without character count
- ✅ No other PII leakage in crash reports

---

## Workstream 4: CI/CD Security 🟢 LOW PRIORITY

**Agent Responsibility:** Add automated security checks, dependency scanning, and artifact provenance

**Files to Create/Modify:**
- `.github/dependabot.yml` (new)
- `.github/workflows/security.yml` (new)
- `.github/workflows/release.yml` (modify)
- `Package.swift` (modify line 18)

**Issues Addressed:**
- **CICD-001:** Add security scanning (Dependabot, dependency verification)
- **CICD-002:** Add artifact checksums and SBOM
- **DEP-001:** Pin dependencies to exact revisions

**Dependencies:** NONE - Can start immediately (CI/CD changes don't affect app)

### Implementation Details

#### File 1: Create .github/dependabot.yml

```yaml
# Automated dependency updates for SwiftWhisper
version: 2
updates:
  - package-ecosystem: "swift"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 5
    labels:
      - "dependencies"
      - "security"
```

#### File 2: Create .github/workflows/security.yml

```yaml
name: Security Checks

on:
  push:
    branches: [ main, security-* ]
  pull_request:
    branches: [ main ]

permissions:
  contents: read

jobs:
  verify-dependencies:
    name: Verify Package.resolved Integrity
    runs-on: macos-14
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Resolve dependencies
        run: swift package resolve

      - name: Check for unexpected changes
        run: |
          if ! git diff --exit-code Package.resolved; then
            echo "❌ Package.resolved changed after resolve!"
            echo "This may indicate dependency tampering."
            exit 1
          fi
          echo "✅ Package.resolved integrity verified"

      - name: Verify SwiftWhisper revision
        run: |
          EXPECTED_REV="a192004db08de7c6eaa169eede77f1625e7d23fb"
          ACTUAL_REV=$(grep -A 5 '"identity" : "swiftwhisper"' Package.resolved | grep '"revision"' | cut -d'"' -f4)

          if [ "$ACTUAL_REV" != "$EXPECTED_REV" ]; then
            echo "❌ SwiftWhisper revision mismatch!"
            echo "Expected: $EXPECTED_REV"
            echo "Actual: $ACTUAL_REV"
            exit 1
          fi
          echo "✅ SwiftWhisper revision verified: $ACTUAL_REV"

  build-verification:
    name: Verify Clean Build
    runs-on: macos-14
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Build release
        run: swift build -c release

      - name: Run basic functionality test
        run: |
          # Verify binary was created
          test -f .build/release/LookMaNoHands
          echo "✅ Release binary built successfully"
```

#### File 3: Update .github/workflows/release.yml

Add checksum and SBOM generation after DMG creation (after line 27):

```yaml
      - name: Generate SHA256 Checksums
        run: |
          cd build
          echo "Generating checksums for release artifacts..."
          shasum -a 256 "Look Ma No Hands ${{ steps.version.outputs.VERSION }}.dmg" > checksums.txt
          shasum -a 256 "LookMaNoHands-${{ steps.version.outputs.VERSION }}.zip" >> checksums.txt
          echo ""
          echo "=== Checksums ==="
          cat checksums.txt

      - name: Generate SBOM (Software Bill of Materials)
        run: |
          echo "Generating SBOM..."
          swift package show-dependencies --format json > build/sbom.json
          echo "✅ SBOM generated"

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: |
            build/Look Ma No Hands ${{ steps.version.outputs.VERSION }}.dmg
            build/LookMaNoHands-${{ steps.version.outputs.VERSION }}.zip
            build/checksums.txt
            build/sbom.json
          generate_release_notes: true
          draft: false
```

#### File 4: Update Package.swift

**Replace line 18** (pin to exact revision instead of version range):

```swift
// OLD:
.package(url: "https://github.com/exPHAT/SwiftWhisper.git", from: "1.0.0")

// NEW (pin to exact commit):
.package(url: "https://github.com/exPHAT/SwiftWhisper.git",
         revision: "a192004db08de7c6eaa169eede77f1625e7d23fb")
```

**Rationale:** Exact revision pinning prevents unexpected dependency updates. When updating SwiftWhisper, the revision change will be explicit and reviewable.

### Testing Instructions

1. **Test Dependabot:**
   ```bash
   # After merging, check GitHub repository settings
   # Should see Dependabot alerts enabled
   # Should receive PR when SwiftWhisper updates
   ```

2. **Test Security Workflow:**
   ```bash
   # Create test branch
   git checkout -b test-security-workflow

   # Push to GitHub
   git push origin test-security-workflow

   # Check Actions tab - security workflow should run
   # Should pass all checks
   ```

3. **Test Dependency Tampering Detection:**
   ```bash
   # Modify Package.resolved manually
   # Push to GitHub
   # Security workflow should fail with integrity error
   ```

4. **Test Release Workflow:**
   ```bash
   # Create release tag
   git tag v1.1.2-test
   git push origin v1.1.2-test

   # Check release artifacts include:
   # - DMG file
   # - ZIP file
   # - checksums.txt
   # - sbom.json

   # Verify checksums match:
   shasum -a 256 "Look Ma No Hands 1.1.2-test.dmg"
   # Compare with checksums.txt
   ```

5. **Verify SBOM Content:**
   ```bash
   # Download sbom.json from release
   cat sbom.json | jq .
   # Should show SwiftWhisper as dependency
   ```

### Success Criteria

- ✅ Dependabot PRs created for SwiftWhisper updates
- ✅ Security workflow runs on all PRs
- ✅ Package.resolved integrity verified in CI
- ✅ SwiftWhisper revision verified in CI
- ✅ Release artifacts include SHA256 checksums
- ✅ Release artifacts include SBOM
- ✅ Checksums match downloaded files

---

## Workstream 5: Production Hardening 🟢 LOW PRIORITY (SEQUENTIAL)

**Agent Responsibility:** Add production code signing with hardened runtime and notarization

**⚠️  DEPENDENCY:** This workstream MUST wait for Workstream 2 to complete (deploy.sh and create-dmg.sh need to be updated first)

**Files to Create/Modify:**
- `Resources/App.entitlements` (new)
- `deploy.sh` (modify lines 53-54) - WAIT FOR WORKSTREAM 2
- `scripts/create-dmg.sh` (modify line 32) - WAIT FOR WORKSTREAM 2
- `.github/workflows/release.yml` (add notarization after line 22)

**Issues Addressed:**
- **BUILD-003:** Production code signing with Developer ID
- **ARTIFACT-001:** Hardened runtime with entitlements

**Requirements:**
- Apple Developer Program membership ($99/year)
- Developer ID Application certificate
- Apple ID and app-specific password for notarization

**Note:** This is LOW PRIORITY because current ad-hoc signing works fine for local development. Only needed for public distribution outside local machines.

### Implementation Details

#### File 1: Create Resources/App.entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Allow Apple Events for text insertion via AXUIElement -->
    <key>com.apple.security.automation.apple-events</key>
    <true/>

    <!-- Microphone access for voice dictation -->
    <key>com.apple.security.device.audio-input</key>
    <true/>

    <!-- User file access for settings and models -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>

    <!-- Network access for model downloads and updates -->
    <key>com.apple.security.network.client</key>
    <true/>

    <!-- Disable App Sandbox (required for accessibility features) -->
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

#### File 2: Update deploy.sh (lines 53-54)

**⚠️  WAIT FOR WORKSTREAM 2 TO COMPLETE FIRST**

```bash
# Replace lines 53-54 with conditional signing

# Check for Developer ID certificate (production) vs ad-hoc (dev)
if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "🔐 Signing with Developer ID (production)..."
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk '{print $2}')
    codesign --force \
        --sign "$SIGNING_IDENTITY" \
        --entitlements Resources/App.entitlements \
        --options runtime \
        --timestamp \
        --deep \
        "$APP_PATH"

    # Verify signature
    codesign --verify --deep --strict "$APP_PATH"
    if [ $? -eq 0 ]; then
        echo "   ✅ Production signature verified"
    else
        echo "   ❌ Production signature verification failed"
        exit 1
    fi
else
    echo "🔐 Signing with ad-hoc signature (development)..."
    codesign --force --sign - "$APP_PATH"
    echo "   ℹ️  Using ad-hoc signature (development mode)"
fi
```

#### File 3: Update create-dmg.sh (line 32)

**⚠️  WAIT FOR WORKSTREAM 2 TO COMPLETE FIRST**

```bash
# Replace line 32 with conditional signing

# Sign with Developer ID if available, otherwise ad-hoc
if [ -n "${DEVELOPER_ID_CERT:-}" ]; then
    echo "🔐 Signing with Developer ID..."
    codesign --force \
        --sign "$DEVELOPER_ID_CERT" \
        --entitlements Resources/App.entitlements \
        --options runtime \
        --timestamp \
        --deep \
        "${APP_PATH}"
else
    echo "🔐 Signing with ad-hoc signature..."
    codesign --force --sign - "${APP_PATH}"
fi
```

#### File 4: Update .github/workflows/release.yml

Add notarization step after DMG creation (after line 22, before checksums):

```yaml
      - name: Import Code Signing Certificate
        if: startsWith(github.ref, 'refs/tags/v')
        env:
          CERTIFICATE_BASE64: ${{ secrets.DEVELOPER_ID_CERT_BASE64 }}
          CERTIFICATE_PASSWORD: ${{ secrets.DEVELOPER_ID_CERT_PASSWORD }}
        run: |
          # Create temporary keychain
          KEYCHAIN_PATH=$RUNNER_TEMP/app-signing.keychain-db
          KEYCHAIN_PASSWORD=$(uuidgen)

          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

          # Import certificate
          echo "$CERTIFICATE_BASE64" | base64 --decode > certificate.p12
          security import certificate.p12 -k "$KEYCHAIN_PATH" -P "$CERTIFICATE_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

          # Set as default keychain
          security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain

          echo "✅ Certificate imported"

      - name: Sign and Notarize DMG
        if: startsWith(github.ref, 'refs/tags/v')
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_ID_PASSWORD: ${{ secrets.APPLE_ID_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          DMG_PATH="build/Look Ma No Hands ${{ steps.version.outputs.VERSION }}.dmg"

          # Sign DMG
          echo "🔐 Signing DMG..."
          codesign --force --sign "Developer ID Application" --timestamp "$DMG_PATH"

          # Verify signature
          codesign --verify --deep --strict "$DMG_PATH"
          echo "✅ DMG signed and verified"

          # Submit for notarization
          echo "📤 Submitting for notarization..."
          xcrun notarytool submit "$DMG_PATH" \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_ID_PASSWORD" \
            --team-id "$APPLE_TEAM_ID" \
            --wait

          # Staple notarization ticket
          echo "📎 Stapling notarization ticket..."
          xcrun stapler staple "$DMG_PATH"

          echo "✅ Notarization complete"

      # ... continue with checksums and release ...
```

### Required GitHub Secrets

Add these secrets to repository settings:

- `DEVELOPER_ID_CERT_BASE64` - Base64-encoded .p12 certificate
- `DEVELOPER_ID_CERT_PASSWORD` - Certificate password
- `APPLE_ID` - Apple ID email
- `APPLE_ID_PASSWORD` - App-specific password (not regular password)
- `APPLE_TEAM_ID` - Team ID from Apple Developer account

### Testing Instructions

**⚠️  Can only test with Apple Developer Program membership**

1. **Test Local Production Signing:**
   ```bash
   # Install Developer ID certificate in keychain
   # Run deploy.sh
   ./deploy.sh

   # Should detect certificate and use production signing
   # Verify signature:
   codesign --verify --deep --strict ~/Applications/LookMaNoHands.app
   codesign -dvv ~/Applications/LookMaNoHands.app | grep "Authority"
   # Should show "Developer ID Application: Your Name (TEAM_ID)"
   ```

2. **Test Dev Signing Still Works:**
   ```bash
   # Remove Developer ID certificate temporarily
   # Run deploy.sh
   ./deploy.sh

   # Should fall back to ad-hoc signing
   # Verify signature:
   codesign -dvv ~/Applications/LookMaNoHands.app
   # Should show "Signature=adhoc"
   ```

3. **Test Release Workflow:**
   ```bash
   # Add required secrets to GitHub repository
   # Create release tag
   git tag v1.1.2-signed
   git push origin v1.1.2-signed

   # Wait for workflow to complete
   # Download DMG from release

   # Verify notarization:
   spctl --assess --verbose --type install "Look Ma No Hands 1.1.2-signed.dmg"
   # Should show "accepted" and "source=Notarized Developer ID"

   # Verify stapled ticket:
   xcrun stapler validate "Look Ma No Hands 1.1.2-signed.dmg"
   # Should show "The validate action worked!"
   ```

4. **Test on Clean Mac:**
   ```bash
   # On a Mac without Xcode or Developer tools
   # Download and open DMG
   # Should open without Gatekeeper warnings
   # App should launch without "unidentified developer" error
   ```

### Success Criteria

- ✅ Local development still uses ad-hoc signing (no certificate required)
- ✅ Production builds use Developer ID signing when certificate available
- ✅ Hardened runtime enabled with proper entitlements
- ✅ CI successfully signs and notarizes releases
- ✅ Released DMG passes Gatekeeper on clean Macs
- ✅ No "unidentified developer" warnings for users

---

## Execution Timeline

### Immediate (Parallel - No Dependencies)
- **Workstream 1** - Model security (HIGH, 1 file, ~2-3 hours)
- **Workstream 2** - Build scripts (MEDIUM, 2 files, ~1 hour)
- **Workstream 3** - Runtime fixes (MEDIUM, 2 files, ~30 min)
- **Workstream 4** - CI/CD (LOW, 4 files, ~1 hour)

**Total parallel time: ~3 hours** (if all 4 agents work simultaneously)

### Sequential (After Workstream 2 completes)
- **Workstream 5** - Production hardening (LOW, 4 files, ~2 hours, optional)

---

## Coordination Notes

### Merge Order
1. Merge Workstreams 1, 3, 4 in any order (independent)
2. Merge Workstream 2 (required for Workstream 5)
3. Merge Workstream 5 last (optional, production only)

### Conflict Resolution
- **No file conflicts** between Workstreams 1-4 (all touch different files)
- **Workstream 5 depends on Workstream 2** - must wait for deploy.sh changes
- If Workstream 2 and 5 run in parallel, Workstream 5 must rebase after Workstream 2 merges

### Testing Integration
- Each workstream includes independent tests
- After all workstreams merge, run full integration test:
  ```bash
  # Test complete flow
  ./deploy.sh                          # Should preserve settings
  # Download a model                   # Should verify SHA256
  # Start meeting mode                 # Should check permissions correctly
  # Create release                     # Should include checksums + SBOM
  ```

---

## Summary of Changes by File

| File | Workstream | Lines Changed | Priority |
|------|------------|---------------|----------|
| `Sources/.../WhisperService.swift` | 1 | 220-297 (~80 lines) | HIGH |
| `deploy.sh` | 2, 5 | 32, 53-54, 67-72 | MEDIUM |
| `scripts/create-dmg.sh` | 2, 5 | 15, 17, 32, 39, 51 | MEDIUM |
| `Sources/.../SystemAudioRecorder.swift` | 3 | 42-50 (8 lines) | MEDIUM |
| `Sources/.../CrashReporter.swift` | 3 | 157-162 (6 lines) | MEDIUM |
| `.github/dependabot.yml` | 4 | NEW | LOW |
| `.github/workflows/security.yml` | 4 | NEW | LOW |
| `.github/workflows/release.yml` | 4, 5 | Add sections | LOW |
| `Package.swift` | 4 | 18 (1 line) | LOW |
| `Resources/App.entitlements` | 5 | NEW | LOW |

**Total: 10 files, ~150 lines of new/modified code**

---

## Questions for User Before Starting

1. **SHA256 Checksums:** Do you want me to compute actual SHA256 hashes for all Whisper models, or use placeholder values initially?

2. **Production Signing:** Are you planning to distribute publicly soon, or can Workstream 5 be deferred?

3. **Parallel Execution:** Should all 4 agents start immediately, or do you want to prioritize certain workstreams?

4. **Testing:** Do you want each agent to include automated tests, or manual testing is sufficient?
