//
//  SystemMetrics.swift
//  ZenMac
//
//  Native macOS System Monitor & Safe Developer Cache Cleaner
//

import Foundation

/// Real-time CPU load breakdown computed from Mach host_processor_info / host_statistics64 ticks.
public struct CPUMetrics: Sendable, Equatable {
    public let userPercentage: Double
    public let systemPercentage: Double
    public let idlePercentage: Double
    public let nicePercentage: Double

    /// Combined active CPU utilization (User + System + Nice) in the range 0.0...100.0
    public var totalUsagePercentage: Double {
        min(100.0, max(0.0, userPercentage + systemPercentage + nicePercentage))
    }

    public static let zero = CPUMetrics(
        userPercentage: 0,
        systemPercentage: 0,
        idlePercentage: 100,
        nicePercentage: 0
    )
}

/// System memory pressure classification aligned with Darwin VM statistics.
public enum MemoryPressureLevel: String, Sendable, Equatable {
    case nominal = "Nominal"
    case warning = "Elevated"
    case critical = "Critical"
}

/// Real-time Virtual Memory breakdown retrieved via Mach HOST_VM_INFO64.
public struct MemoryMetrics: Sendable, Equatable {
    public let totalBytes: UInt64
    public let activeBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    public let freeBytes: UInt64
    public let inactiveBytes: UInt64
    public let appMemoryBytes: UInt64

    /// Accurate Used RAM matching macOS Activity Monitor (Active + Wired + Compressed)
    public var usedBytes: UInt64 {
        min(totalBytes, activeBytes + wiredBytes + compressedBytes)
    }

    public var availableBytes: UInt64 {
        totalBytes > usedBytes ? (totalBytes - usedBytes) : 0
    }

    public var usagePercentage: Double {
        guard totalBytes > 0 else { return 0.0 }
        return (Double(usedBytes) / Double(totalBytes)) * 100.0
    }

    public var pressureLevel: MemoryPressureLevel {
        guard totalBytes > 0 else { return .nominal }
        let compressedRatio = Double(compressedBytes) / Double(totalBytes)
        let usedRatio = Double(usedBytes) / Double(totalBytes)

        if compressedRatio > 0.25 || usedRatio > 0.90 {
            return .critical
        } else if compressedRatio > 0.12 || usedRatio > 0.78 {
            return .warning
        }
        return .nominal
    }

    public static let zero = MemoryMetrics(
        totalBytes: 0,
        activeBytes: 0,
        wiredBytes: 0,
        compressedBytes: 0,
        freeBytes: 0,
        inactiveBytes: 0,
        appMemoryBytes: 0
    )
}

/// Aggregated snapshot of system telemetry at a point in time.
public struct SystemMetrics: Sendable, Equatable {
    public let cpu: CPUMetrics
    public let memory: MemoryMetrics
    public let primaryVolume: StorageVolume
    public let timestamp: Date

    public static let initial = SystemMetrics(
        cpu: .zero,
        memory: .zero,
        primaryVolume: .empty,
        timestamp: .now
    )
}
