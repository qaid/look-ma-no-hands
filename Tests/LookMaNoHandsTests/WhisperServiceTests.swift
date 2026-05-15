import XCTest
@testable import LookMaNoHands

final class WhisperServiceTests: XCTestCase {

    private var tempCacheDir: URL!
    private var modelsParent: URL!

    override func setUp() {
        super.setUp()
        tempCacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperServiceTests-\(UUID().uuidString)")
        modelsParent = tempCacheDir
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
        try? FileManager.default.createDirectory(at: modelsParent, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempCacheDir)
        super.tearDown()
    }

    private func createModelDir(_ name: String) {
        let dir = modelsParent.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: - scanCacheForAliasedVariant

    func testScanFindsVersionedTurboDirectory() {
        createModelDir("openai_whisper-large-v3-v20240930_turbo_632MB")

        let result = WhisperService.scanCacheForAliasedVariant("large-v3-turbo", in: tempCacheDir)

        XCTAssertEqual(result, "large-v3-v20240930_turbo_632MB")
    }

    func testScanReturnsNilWhenNoMatchingDirectory() {
        createModelDir("openai_whisper-base")
        createModelDir("openai_whisper-small")

        let result = WhisperService.scanCacheForAliasedVariant("large-v3-turbo", in: tempCacheDir)

        XCTAssertNil(result)
    }

    func testScanReturnsNilWhenCacheDirectoryMissing() {
        let missingDir = tempCacheDir.appendingPathComponent("does-not-exist")

        let result = WhisperService.scanCacheForAliasedVariant("large-v3-turbo", in: missingDir)

        XCTAssertNil(result)
    }

    func testScanIgnoresDirectoriesWithoutOpenAIPrefix() {
        createModelDir("large-v3-turbo-stray")

        let result = WhisperService.scanCacheForAliasedVariant("large-v3-turbo", in: tempCacheDir)

        XCTAssertNil(result)
    }

    // MARK: - resolveCanonicalModelName

    func testResolveReturnsRawNameForNonAliasedModel() async {
        let result = await WhisperService.resolveCanonicalModelName("base", in: tempCacheDir)
        XCTAssertEqual(result, "base")
    }

    func testResolveDoesNotMatchSimilarNonAliasedName() async {
        // Guards against weak `contains("turbo")` regression — names like
        // "turbocharged-v1" must not trigger aliased resolution.
        let result = await WhisperService.resolveCanonicalModelName("turbocharged-v1", in: tempCacheDir)
        XCTAssertEqual(result, "turbocharged-v1")
    }

    func testResolveReturnsCachedVariantWhenAvailable() async {
        createModelDir("openai_whisper-large-v3-v20240930_turbo_632MB")

        let result = await WhisperService.resolveCanonicalModelName("large-v3-turbo", in: tempCacheDir)

        XCTAssertEqual(result, "large-v3-v20240930_turbo_632MB")
    }

    func testAliasedModelNamesIncludesLargeV3Turbo() {
        XCTAssertTrue(WhisperService.aliasedModelNames.contains("large-v3-turbo"))
    }
}
