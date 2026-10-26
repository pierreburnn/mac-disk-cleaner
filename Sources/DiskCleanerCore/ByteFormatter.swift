// ByteFormatter.swift – Human-readable size formatting (decimal/1000-based like Finder)
import Foundation

public struct ByteFormatter: Sendable {

    public init() {}

    /// Format bytes into a human-readable string like "13.4 GB", "512 MB", "0 B".
    /// Decimal (1000-based) like Finder.
    public static func format(_ bytes: Int64) -> String {
        let p = parts(bytes)
        return "\(p.value) \(p.unit)"
    }

    /// Split into value string and unit string, for the big stat display.
    /// e.g. (value: "41.7", unit: "GB")
    public static func parts(_ bytes: Int64) -> (value: String, unit: String) {
        let absBytes = abs(bytes)
        let sign = bytes < 0 ? "-" : ""

        if absBytes < 1000 {
            return (value: "\(sign)\(absBytes)", unit: "B")
        }

        let kb = Double(absBytes) / 1000.0
        if kb < 1000 {
            return (value: "\(sign)\(Int(kb))", unit: "KB")
        }

        let mb = kb / 1000.0
        if mb < 1000 {
            return (value: "\(sign)\(Int(mb))", unit: "MB")
        }

        let gb = mb / 1000.0
        if gb < 1000 {
            let formatted: String
            if gb >= 100 {
                formatted = String(format: "%.0f", gb)
            } else {
                formatted = String(format: "%.1f", gb)
            }
            return (value: "\(sign)\(formatted)", unit: "GB")
        }

        let tb = gb / 1000.0
        let formatted = String(format: "%.1f", tb)
        return (value: "\(sign)\(formatted)", unit: "TB")
    }

    /// Format with a sign prefix, e.g. "+52.5 GB"
    public static func formatSigned(_ bytes: Int64) -> String {
        let p = parts(bytes)
        let prefix = bytes > 0 ? "+" : ""
        return "\(prefix)\(p.value) \(p.unit)"
    }
}
