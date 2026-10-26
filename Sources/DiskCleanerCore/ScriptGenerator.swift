// ScriptGenerator.swift – Builds the cleanup shell script
import Foundation

/// Generates a bash cleanup script from selected recommendations.
public struct ScriptGenerator: Sendable {

    public init() {}

    /// Generate a cleanup script for the selected recommendations.
    /// - Parameters:
    ///   - recs: The selected recommendations.
    ///   - home: The user's home directory path.
    ///   - date: The generation date (defaults to now).
    /// - Returns: A complete bash script string.
    public static func makeScript(for recs: [Recommendation], home: String, date: Date = Date()) -> String {
        let homePath = home.hasSuffix("/") ? String(home.dropLast()) : home
        let totalBytes = recs.reduce(Int64(0)) { $0 + $1.bytes }
        let totalFormatted = ByteFormatter.format(totalBytes)

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "en_US")
        let dateStr = formatter.string(from: date)

        var lines: [String] = []
        lines.append("#!/bin/bash")
        lines.append("#")
        lines.append("# Disk Cleaner – cleanup script")
        lines.append("# Generated: \(dateStr)")
        lines.append("# Total: \(totalFormatted)")
        lines.append("#")
        lines.append("# ⚠️  WARNING: Review every line before running.")
        lines.append("# This permanently deletes files.")
        lines.append("# Disk Cleaner never runs this itself.")
        lines.append("#")
        lines.append("")
        lines.append("set -euo pipefail")
        lines.append("")

        for rec in recs {
            let safetyLabel = rec.safety == .safe ? "Safe to remove" : "Review first"
            let sizeStr = ByteFormatter.format(rec.bytes)
            lines.append("# --- \(rec.title) (\(sizeStr)) — \(safetyLabel)")
            lines.append("# \(rec.detail)")
            lines.append("")

            switch rec.command {
            case .removePaths:
                for path in rec.paths {
                    if let relativePath = makeRelative(path: path, home: homePath) {
                        let quoted = shellQuote(relativePath)
                        lines.append("if [ -e \"$HOME\"/\(quoted) ]; then rm -rf -- \"$HOME\"/\(quoted); fi")
                    } else {
                        lines.append("# SKIPPED (outside home): \(path)")
                    }
                }

            case .shell(let script, _):
                // Emit the custom shell command
                for line in script.split(separator: "\n", omittingEmptySubsequences: false) {
                    lines.append(String(line))
                }
            }

            lines.append("")
        }

        lines.append("echo \"Done.\"")

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Path utilities

    /// Make a path relative to home, with safety checks.
    /// Returns nil if the path is not strictly inside home.
    private static func makeRelative(path: String, home: String) -> String? {
        // Standardize paths
        let standardPath = (path as NSString).standardizingPath
        let standardHome = (home as NSString).standardizingPath

        // Safety: path must be strictly inside home
        guard !standardPath.isEmpty else { return nil }
        guard standardPath != "/" else { return nil }
        guard standardPath != standardHome else { return nil }
        guard standardPath.hasPrefix(standardHome + "/") else { return nil }

        // Check it doesn't escape via ..
        let relative = String(standardPath.dropFirst(standardHome.count + 1))
        let components = relative.split(separator: "/")
        for comp in components {
            if comp == ".." { return nil }
        }

        return relative
    }

    /// Shell-quote a string using single quotes with proper escaping.
    /// Produces e.g. 'Library/Developer/Xcode/iOS DeviceSupport'
    public static func shellQuote(_ s: String) -> String {
        // If the string only has safe characters, no quoting needed
        let safeChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/_.-"))
        if s.unicodeScalars.allSatisfy({ safeChars.contains($0) }) {
            return s
        }
        // Single-quote with '\'' for embedded single quotes
        let escaped = s.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
