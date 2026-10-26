// ScriptTests.swift – Tests for ScriptGenerator bash script emission and execution
import XCTest
import Foundation
@testable import DiskCleanerCore

final class ScriptTests: XCTestCase {

    func testScriptHeaderAndWarning() {
        let fakeHome = "/Users/testuser"
        let rec = Recommendation(
            id: "sample-rec",
            title: "Sample Cache",
            displayPath: "~/.sample",
            paths: ["\(fakeHome)/.sample"],
            bytes: 1_000_000,
            safety: .safe,
            detail: "Sample detail",
            command: .removePaths
        )

        let script = ScriptGenerator.makeScript(for: [rec], home: fakeHome)

        XCTAssertTrue(script.contains("#!/bin/bash"), "Script should start with bash shebang")
        XCTAssertTrue(script.contains("set -euo pipefail"), "Script should contain 'set -euo pipefail'")
        XCTAssertTrue(
            script.contains("WARNING: Review every line before running"),
            "Script should contain warning line about reviewing before running"
        )
    }

    func testBashSyntaxWithSpacesAndQuotes() throws {
        let fakeHome = "/Users/testuser"
        let quotedPath = "\(fakeHome)/Documents/My 'quoted' folder with spaces/file"
        let rec = Recommendation(
            id: "quoted-rec",
            title: "Quoted Folder",
            displayPath: "~/Documents/My 'quoted' folder",
            paths: [quotedPath],
            bytes: 500_000,
            safety: .safe,
            detail: "Quoted path test",
            command: .removePaths
        )

        let script = ScriptGenerator.makeScript(for: [rec], home: fakeHome)
        let tempScriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("syntax-check-\(UUID().uuidString).sh")
        defer { try? FileManager.default.removeItem(at: tempScriptURL) }

        try script.write(to: tempScriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-n", tempScriptURL.path]
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0, "bash -n should validate syntax successfully (status 0)")
    }

    func testScriptExecutionIntegrationRemovesTargetDirs() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent("ScriptExecHome-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempHome) }

        // 1. Dir with space
        let dir1 = tempHome.appendingPathComponent("dir with spaces", isDirectory: true)
        try fm.createDirectory(at: dir1, withIntermediateDirectories: true)
        try Data("content1".utf8).write(to: dir1.appendingPathComponent("data.txt"))

        // 2. Dir with space and single quote
        let dir2 = tempHome.appendingPathComponent("it's a 'quoted' dir", isDirectory: true)
        try fm.createDirectory(at: dir2, withIntermediateDirectories: true)
        try Data("content2".utf8).write(to: dir2.appendingPathComponent("data.txt"))

        // 3. Sibling untouched dir
        let dir3 = tempHome.appendingPathComponent("sibling untouched", isDirectory: true)
        try fm.createDirectory(at: dir3, withIntermediateDirectories: true)
        try Data("content3".utf8).write(to: dir3.appendingPathComponent("data.txt"))

        XCTAssertTrue(fm.fileExists(atPath: dir1.path))
        XCTAssertTrue(fm.fileExists(atPath: dir2.path))
        XCTAssertTrue(fm.fileExists(atPath: dir3.path))

        let rec = Recommendation(
            id: "integration-cleanup",
            title: "Integration Cleanup",
            displayPath: "~",
            paths: [dir1.path, dir2.path],
            bytes: 2_000_000,
            safety: .safe,
            detail: "Remove 2 dirs with spaces and quotes",
            command: .removePaths
        )

        let script = ScriptGenerator.makeScript(for: [rec], home: tempHome.path)
        let scriptURL = tempHome.appendingPathComponent("cleanup.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = tempHome.path
        process.environment = env
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0, "Generated bash script should run with exit status 0")

        // Target dirs must be gone
        XCTAssertFalse(fm.fileExists(atPath: dir1.path), "dir1 with space should be deleted")
        XCTAssertFalse(fm.fileExists(atPath: dir2.path), "dir2 with space and quote should be deleted")

        // Sibling untouched dir must still exist
        XCTAssertTrue(fm.fileExists(atPath: dir3.path), "dir3 untouched sibling should still exist")
    }

    func testUnselectedRecommendationsNotMentioned() {
        let fakeHome = "/Users/testuser"
        let selectedRec = Recommendation(
            id: "selected-rec",
            title: "Selected Rec",
            displayPath: "~/selected",
            paths: ["\(fakeHome)/selected-directory"],
            bytes: 1_000,
            safety: .safe,
            detail: "Selected",
            command: .removePaths
        )
        let unselectedRec = Recommendation(
            id: "unselected-rec",
            title: "Unselected Rec",
            displayPath: "~/unselected",
            paths: ["\(fakeHome)/unselected-directory-secret"],
            bytes: 5_000,
            safety: .review,
            detail: "Unselected",
            command: .removePaths
        )

        // Pass ONLY selectedRec
        let script = ScriptGenerator.makeScript(for: [selectedRec], home: fakeHome)

        XCTAssertTrue(script.contains("selected-directory"), "Script should mention selected recommendation path")
        XCTAssertFalse(script.contains("unselected-directory-secret"), "Script should not mention unselected path")
    }

    func testPathsOutsideHomeSkipped() {
        let home = "/Users/testuser"
        let outsidePaths = [
            "/usr/lib",
            "/Users/someoneelse/x",
            "\(home)/../escape",
            home,
            "/"
        ]

        let rec = Recommendation(
            id: "outside-paths",
            title: "Outside Paths",
            displayPath: "outside",
            paths: outsidePaths,
            bytes: 10_000,
            safety: .safe,
            detail: "Test outside home paths",
            command: .removePaths
        )

        let script = ScriptGenerator.makeScript(for: [rec], home: home)

        // 1. Each outside path is reported as SKIPPED
        for p in outsidePaths {
            XCTAssertTrue(
                script.contains("# SKIPPED (outside home): \(p)"),
                "Script should report '# SKIPPED (outside home): \(p)'"
            )
        }

        // 2. No non-comment line contains any of the outside paths
        let lines = script.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.hasPrefix("#") {
                for p in outsidePaths {
                    XCTAssertFalse(
                        trimmed.contains(p),
                        "Non-comment line '\(trimmed)' should not contain outside path '\(p)'"
                    )
                }
            }
        }
    }

    func testShellQuoteRoundTrip() throws {
        let original = "a'b c"
        let quoted = ScriptGenerator.shellQuote(original)
        XCTAssertEqual(quoted, "'a'\\''b c'")

        // Execute in /bin/bash to verify exact round-trip interpretation
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "printf '%s' \(quoted)"]

        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let result = String(data: outputData, encoding: .utf8)
        XCTAssertEqual(result, original, "Round trip through bash printf should equal original string")
    }

    func testShellQuoteSafeCharactersRemainUnquoted() {
        let safe1 = "simple_name"
        let safe2 = "path/to-file.txt"
        XCTAssertEqual(ScriptGenerator.shellQuote(safe1), safe1)
        XCTAssertEqual(ScriptGenerator.shellQuote(safe2), safe2)

        let withSpace = "name with spaces"
        XCTAssertEqual(ScriptGenerator.shellQuote(withSpace), "'name with spaces'")
    }
}
