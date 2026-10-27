//
//  SystemMonitorService.swift
//  ZenMac
//
//  Zero-subprocess real-time system telemetry using Mach & Darwin APIs:
//  - host_statistics64(HOST_CPU_LOAD_INFO) & host_processor_info(PROCESSOR_CPU_LOAD_INFO)
//  - host_statistics64(HOST_VM_INFO64)
//  - statfs & URLResourceKey (.volumeAvailableCapacityForImportantUsageKey)
//

import Foundation
import Darwin
import Observation
import OSLog

@MainActor
@Observable
public final class SystemMonitorService {
    private let logger = Logger(subsystem: "com.zenmac.app", category: "SystemMonitorService")

    public private(set) var metrics: SystemMetrics = .initial
    public private(set) var cpuHistory: [Double] = Array(repeating: 0.0, count: 30)
    public private(set) var isMonitoring: Bool = false

    private var pollingTask: Task<Void, Never>?
    private let sampler = MachTelemetrySampler()

    public init() {}

    /// Starts the 1-second low-overhead Mach polling loop.
    public func startMonitoring(intervalSeconds: Double = 1.0) {
        guard pollingTask == nil else { return }
        isMonitoring = true

        pollingTask = Task { [weak self] in
            guard let self else { return }
            // Take an initial baseline sample immediately
            let initialSnapshot = await self.sampler.sampleMetrics()
            self.applySnapshot(initialSnapshot)

            let intervalNanoseconds = UInt64(max(0.25, intervalSeconds) * 1_000_000_000)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
                guard !Task.isCancelled else { break }
                let snapshot = await self.sampler.sampleMetrics()
                self.applySnapshot(snapshot)
            }
        }
    }

    /// Stops the active polling loop.
    public func stopMonitoring() {
        pollingTask?.cancel()
        pollingTask = nil
        isMonitoring = false
    }

    /// Triggers an immediate single refresh of all system metrics.
    public func refreshNow() async {
        let snapshot = await sampler.sampleMetrics()
        applySnapshot(snapshot)
    }

    private func applySnapshot(_ snapshot: SystemMetrics) {
        self.metrics = snapshot
        var updatedHistory = self.cpuHistory
        if updatedHistory.count >= 30 {
            updatedHistory.removeFirst()
        }
        updatedHistory.append(snapshot.cpu.totalUsagePercentage)
        self.cpuHistory = updatedHistory
    }
}

// MARK: - Low-Level Mach & Darwin Telemetry Actor

/// Isolated background actor executing zero-allocation Mach traps and `statfs` calls.
private actor MachTelemetrySampler {
    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private let machHost: host_t = mach_host_self()
    private let physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory

    func sampleMetrics() -> SystemMetrics {
        let cpu = readCPULoad()
        let memory = readMemoryMetrics()
        let volume = readPrimaryStorageVolume()

        return SystemMetrics(
            cpu: cpu,
            memory: memory,
            primaryVolume: volume,
            timestamp: Date()
        )
    }

    // MARK: 1. CPU Telemetry via Mach host_processor_info & host_statistics64(HOST_CPU_LOAD_INFO)

    private func readCPULoad() -> CPUMetrics {
        // Attempt per-core aggregation via host_processor_info first; fallback to HOST_CPU_LOAD_INFO
        let currentTicks = readPerProcessorTicks() ?? readHostCPULoadTicks()
        guard let currentTicks else { return .zero }

        defer {
            previousCPUTicks = currentTicks
        }

        guard let previous = previousCPUTicks else {
            return .zero
        }

        let userDelta = currentTicks.user >= previous.user ? (currentTicks.user - previous.user) : 0
        let systemDelta = currentTicks.system >= previous.system ? (currentTicks.system - previous.system) : 0
        let idleDelta = currentTicks.idle >= previous.idle ? (currentTicks.idle - previous.idle) : 0
        let niceDelta = currentTicks.nice >= previous.nice ? (currentTicks.nice - previous.nice) : 0

        let totalDelta = userDelta + systemDelta + idleDelta + niceDelta
        guard totalDelta > 0 else { return .zero }

        let totalDouble = Double(totalDelta)
        return CPUMetrics(
            userPercentage: (Double(userDelta) / totalDouble) * 100.0,
            systemPercentage: (Double(systemDelta) / totalDouble) * 100.0,
            idlePercentage: (Double(idleDelta) / totalDouble) * 100.0,
            nicePercentage: (Double(niceDelta) / totalDouble) * 100.0
        )
    }

    /// Reads CPU ticks across all logical cores using `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`
    /// and immediately deallocates the out-of-line Mach VM buffer to prevent memory leaks.
    private func readPerProcessorTicks() -> (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)? {
        var processorCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            machHost,
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &infoArray,
            &infoCount
        )

        guard result == KERN_SUCCESS, let array = infoArray else {
            return nil
        }

        defer {
            let byteCount = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: array), byteCount)
        }

        var totalUser: UInt64 = 0
        var totalSystem: UInt64 = 0
        var totalIdle: UInt64 = 0
        var totalNice: UInt64 = 0

        let stride = Int(CPU_STATE_MAX)
        for core in 0..<Int(processorCount) {
            let base = core * stride
            totalUser += UInt64(UInt32(bitPattern: array[base + Int(CPU_STATE_USER)]))
            totalSystem += UInt64(UInt32(bitPattern: array[base + Int(CPU_STATE_SYSTEM)]))
            totalIdle += UInt64(UInt32(bitPattern: array[base + Int(CPU_STATE_IDLE)]))
            totalNice += UInt64(UInt32(bitPattern: array[base + Int(CPU_STATE_NICE)]))
        }

        return (totalUser, totalSystem, totalIdle, totalNice)
    }

    /// Reads aggregate host CPU ticks via `host_statistics64(HOST_CPU_LOAD_INFO)`.
    private func readHostCPULoadTicks() -> (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)? {
        var cpuLoadInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let kernResult = withUnsafeMutablePointer(to: &cpuLoadInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(machHost, HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }

        guard kernResult == KERN_SUCCESS else { return nil }

        return (
            user: UInt64(cpuLoadInfo.cpu_ticks.0),
            system: UInt64(cpuLoadInfo.cpu_ticks.1),
            idle: UInt64(cpuLoadInfo.cpu_ticks.2),
            nice: UInt64(cpuLoadInfo.cpu_ticks.3)
        )
    }

    // MARK: 2. Memory Telemetry via Mach host_statistics64(HOST_VM_INFO64)

    private func readMemoryMetrics() -> MemoryMetrics {
        var vmStats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let kernResult = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(machHost, HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard kernResult == KERN_SUCCESS else {
            return .zero
        }

        var pageSize: vm_size_t = 0
        let pageResult = host_page_size(machHost, &pageSize)
        let fallbackPageSize = vm_size_t(getpagesize())
        let pageBytes = UInt64(pageResult == KERN_SUCCESS && pageSize > 0 ? pageSize : fallbackPageSize)

        let activeBytes = UInt64(vmStats.active_count) * pageBytes
        let wiredBytes = UInt64(vmStats.wire_count) * pageBytes
        let compressedBytes = UInt64(vmStats.compressor_page_count) * pageBytes
        let freeBytes = UInt64(vmStats.free_count) * pageBytes
        let inactiveBytes = UInt64(vmStats.inactive_count) * pageBytes

        let internalPages = vmStats.internal_page_count >= vmStats.purgeable_count
            ? (vmStats.internal_page_count - vmStats.purgeable_count)
            : vmStats.internal_page_count
        let appMemoryBytes = UInt64(internalPages) * pageBytes

        return MemoryMetrics(
            totalBytes: physicalMemoryBytes,
            activeBytes: activeBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            freeBytes: freeBytes,
            inactiveBytes: inactiveBytes,
            appMemoryBytes: appMemoryBytes
        )
    }

    // MARK: 3. Disk Volume Telemetry via Darwin statfs & URLResourceKey

    private func readPrimaryStorageVolume() -> StorageVolume {
        let rootPath = "/"
        let rootURL = URL(fileURLWithPath: rootPath)

        var fsStats = statfs()
        guard statfs(rootPath, &fsStats) == 0 else {
            return .empty
        }

        let blockSize = UInt64(fsStats.f_bsize)
        let statfsTotalBytes = UInt64(fsStats.f_blocks) * blockSize
        let statfsAvailBytes = UInt64(fsStats.f_bavail) * blockSize

        let fsTypeName = withUnsafePointer(to: &fsStats.f_fstypename) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                String(cString: $0)
            }
        }

        // Enrich with APFS-aware URLResourceKey for purgeable space awareness
        let resourceKeys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]

        let resourceValues = try? rootURL.resourceValues(forKeys: resourceKeys)
        let volumeName = resourceValues?.volumeName ?? "Macintosh HD"
        let totalBytes = UInt64(resourceValues?.volumeTotalCapacity ?? Int(statfsTotalBytes))

        let importantAvail = UInt64(
            max(0, resourceValues?.volumeAvailableCapacityForImportantUsage ?? Int64(statfsAvailBytes))
        )
        let strictAvail = UInt64(
            max(0, resourceValues?.volumeAvailableCapacity ?? Int(statfsAvailBytes))
        )
        let purgeableBytes = importantAvail > strictAvail ? (importantAvail - strictAvail) : 0

        return StorageVolume(
            id: rootPath,
            name: volumeName,
            mountPoint: rootPath,
            fileSystemType: fsTypeName,
            totalBytes: totalBytes,
            availableBytes: importantAvail,
            purgeableBytes: purgeableBytes
        )
    }
}
