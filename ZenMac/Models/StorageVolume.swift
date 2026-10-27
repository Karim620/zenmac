//
//  StorageVolume.swift
//  ZenMac
//
//  Native APFS/Darwin Volume telemetry using statfs & URLResourceKey.
//

import Foundation

/// Represents an APFS or POSIX storage volume queried directly via Darwin `statfs` and `URLResourceKey`.
public struct StorageVolume: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let mountPoint: String
    public let fileSystemType: String
    public let totalBytes: UInt64
    public let availableBytes: UInt64
    public let purgeableBytes: UInt64

    /// Strictly used bytes excluding purgeable APFS space when available.
    public var usedBytes: UInt64 {
        totalBytes > availableBytes ? (totalBytes - availableBytes) : 0
    }

    public var usagePercentage: Double {
        guard totalBytes > 0 else { return 0.0 }
        return (Double(usedBytes) / Double(totalBytes)) * 100.0
    }

    public static let empty = StorageVolume(
        id: "/",
        name: "Macintosh HD",
        mountPoint: "/",
        fileSystemType: "apfs",
        totalBytes: 0,
        availableBytes: 0,
        purgeableBytes: 0
    )
}
