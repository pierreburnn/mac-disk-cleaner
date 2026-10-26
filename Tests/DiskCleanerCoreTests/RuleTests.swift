// RuleTests.swift – Tests for RuleDetector matching recommendations against FakeHome
import XCTest
import Foundation
@testable import DiskCleanerCore

final class RuleTests: XCTestCase {

    private func scanStandardTree(fakeHome: FakeHome) async throws -> ScanResult {
        try fakeHome.populateStandardTree()
        let scanner = DiskScanner()
        return await scanner.scan(root: fakeHome.url, progress: { _ in })
    }

    func testRecommendationsExistByTitleAndSafety() async throws {
        let fakeHome = try FakeHome()
        defer { fakeHome.tearDown() }
        let result = try await scanStandardTree(fakeHome: fakeHome)

        let detector = RuleDetector(minimumBytes: 100_000)
        let recs = detector.detect(root: result.root, home: fakeHome.path, now: Date())

        let expectedRules: [(title: String, safety: Safety)] = [
            ("npm cache", .safe),
            ("Next.js & Turbo build output", .safe),
            ("Gradle caches", .safe),
            ("Xcode DerivedData", .safe),
            ("uv & Puppeteer caches", .safe),
            ("Android SDK & emulators", .review),
            ("Ollama models", .review),
            ("atlas worktrees", .review),
            ("node_modules in idle projects", .review)
        ]

        for expected in expectedRules {
            guard let rec = recs.first(where: { $0.title == expected.title }) else {
                XCTFail("Missing expected recommendation with title '\(expected.title)'. Present titles: \(recs.map { $0.title })")
                continue
            }
            XCTAssertEqual(rec.safety, expected.safety, "Safety mismatch for '\(expected.title)': expected \(expected.safety), got \(rec.safety)")
            XCTAssertGreaterThanOrEqual(rec.bytes, 100_000, "Bytes for '\(expected.title)' should be >= minimumBytes")
            XCTAssertFalse(rec.paths.isEmpty, "Paths for '\(expected.title)' should not be empty")
        }
    }

    func testIdleNodeModulesIncludesOldProjAndNotFreshProj() async throws {
        let fakeHome = try FakeHome()
        defer { fakeHome.tearDown() }
        let result = try await scanStandardTree(fakeHome: fakeHome)

        let detector = RuleDetector(minimumBytes: 100_000)
        let nowDate = Date()
        let recs = detector.detect(root: result.root, home: fakeHome.path, now: nowDate)

        guard let idleRec = recs.first(where: { $0.title == "node_modules in idle projects" }) else {
            XCTFail("Recommendation 'node_modules in idle projects' not found")
            return
        }

        XCTAssertEqual(idleRec.safety, .review)

        let includesOldProj = idleRec.paths.contains { $0.contains("oldproj") }
        XCTAssertTrue(includesOldProj, "idle node_modules must include oldproj path: \(idleRec.paths)")

        let includesFreshProj = idleRec.paths.contains { $0.contains("freshproj") }
        XCTAssertFalse(includesFreshProj, "idle node_modules must NOT include freshproj path: \(idleRec.paths)")
    }

    func testAllRecommendationPathsInsideHome() async throws {
        let fakeHome = try FakeHome()
        defer { fakeHome.tearDown() }
        let result = try await scanStandardTree(fakeHome: fakeHome)

        let detector = RuleDetector(minimumBytes: 100_000)
        let recs = detector.detect(root: result.root, home: fakeHome.path, now: Date())

        XCTAssertFalse(recs.isEmpty, "Recommendations should not be empty")

        for rec in recs {
            for path in rec.paths {
                XCTAssertTrue(
                    path.hasPrefix(fakeHome.path),
                    "Recommendation path '\(path)' in '\(rec.title)' must be inside fake home '\(fakeHome.path)'"
                )
            }
        }
    }

    func testHighMinimumBytesReturnsEmpty() async throws {
        let fakeHome = try FakeHome()
        defer { fakeHome.tearDown() }
        let result = try await scanStandardTree(fakeHome: fakeHome)

        // 10 GB is larger than any recommendation in our ~28.5 MB fake home
        let detector = RuleDetector(minimumBytes: 10_000_000_000)
        let recs = detector.detect(root: result.root, home: fakeHome.path, now: Date())

        XCTAssertTrue(recs.isEmpty, "High minimumBytes threshold should yield empty recommendations, got \(recs.count)")
    }

    func testCleanablePathsSet() async throws {
        let fakeHome = try FakeHome()
        defer { fakeHome.tearDown() }
        let result = try await scanStandardTree(fakeHome: fakeHome)

        let detector = RuleDetector(minimumBytes: 100_000)
        let recs = detector.detect(root: result.root, home: fakeHome.path, now: Date())
        let pathsSet = detector.cleanablePaths(from: recs)

        XCTAssertFalse(pathsSet.isEmpty, "Cleanable paths set should not be empty")
        for rec in recs {
            for p in rec.paths {
                XCTAssertTrue(pathsSet.contains(p), "Cleanable paths set should contain '\(p)'")
            }
        }
    }
}
