// VolumeInfo.swift – Volume capacity information
import Foundation

/// Disk volume capacity information.
public struct VolumeInfo: Sendable {
    /// Total capacity of the volume in bytes.
    public let totalCapacity: Int64
    /// Available (free) capacity in bytes.
    public let availableCapacity: Int64
    /// Used capacity = total - available.
    public var usedCapacity: Int64 { totalCapacity - availableCapacity }

    public init(totalCapacity: Int64, availableCapacity: Int64) {
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
    }

    /// Compute "free after cleanup" given selected cleanup bytes.
    public func freeAfterCleanup(selectedBytes: Int64) -> Int64 {
        return availableCapacity + selectedBytes
    }

    /// Compute "not scanned" bytes: used capacity minus what we scanned.
    public func notScanned(scannedTotal: Int64) -> Int64 {
        return max(0, usedCapacity - scannedTotal)
    }

    /// Query volume info for the volume containing the given URL.
    public static func query(for url: URL) -> VolumeInfo? {
        do {
            #if os(macOS)
            let values = try url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let available: Int64
            if let importantUsage = values.volumeAvailableCapacityForImportantUsage, importantUsage > 0 {
                available = importantUsage
            } else {
                available = Int64(values.volumeAvailableCapacity ?? 0)
            }
            #else
            let values = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let available = Int64(values.volumeAvailableCapacity ?? 0)
            #endif
            return VolumeInfo(totalCapacity: total, availableCapacity: available)
        } catch {
            return nil
        }
    }
}
