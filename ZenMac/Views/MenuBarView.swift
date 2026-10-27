//
//  MenuBarView.swift
//  ZenMac
//
//  Lightweight MenuBarExtra status bar interface with Liquid Glass squircle cards and capsule controls.
//

import SwiftUI

public struct MenuBarView: View {
    @Bindable var monitorService: SystemMonitorService
    @Bindable var scannerService: DiskScannerService
    @Environment(\.openWindow) private var openWindow

    public init(monitorService: SystemMonitorService, scannerService: DiskScannerService) {
        self.monitorService = monitorService
        self.scannerService = scannerService
    }

    public var body: some View {
        ZStack {
            LiquidAmbientBackground()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("ZenMac Telemetry", systemImage: "leaf.circle.fill")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.mint)
                    Spacer()
                    Text(monitorService.metrics.memory.pressureLevel.rawValue)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .liquidGlassPill(tint: .mint, isProminent: false)
                }

                // Telemetry Squircle Pod
                VStack(alignment: .leading, spacing: 10) {
                    // CPU Metric Bar
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("CPU Load")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f%%", monitorService.metrics.cpu.totalUsagePercentage))
                                .font(.caption.monospacedDigit().bold())
                        }
                        ProgressView(value: min(100, monitorService.metrics.cpu.totalUsagePercentage), total: 100)
                            .tint(.cyan)
                    }

                    // Memory Metric Bar
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Memory Used")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(
                                "\(formatBytes(monitorService.metrics.memory.usedBytes)) (\(String(format: "%.0f%%", monitorService.metrics.memory.usagePercentage)))"
                            )
                            .font(.caption.monospacedDigit().bold())
                        }
                        ProgressView(value: min(100, monitorService.metrics.memory.usagePercentage), total: 100)
                            .tint(.mint)
                    }

                    // Disk Metric Bar
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Disk Free (\(monitorService.metrics.primaryVolume.name))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatBytes(monitorService.metrics.primaryVolume.availableBytes))
                                .font(.caption.monospacedDigit().bold())
                        }
                        ProgressView(value: min(100, monitorService.metrics.primaryVolume.usagePercentage), total: 100)
                            .tint(.blue)
                    }
                }
                .padding(14)
                .liquidGlassCard(cornerRadius: 20, tint: .cyan, isInteractive: false)

                // Quick Safe Clean Capsule Pill
                Button {
                    Task {
                        if scannerService.totalDiscoveredBytes == 0 {
                            await scannerService.scanAllCategories()
                        }
                        _ = await scannerService.executeCleanup(strategy: .moveToTrash)
                    }
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        if scannerService.isScanning || scannerService.isCleaning {
                            Text("Scanning / Cleaning Caches...")
                        } else if scannerService.totalSelectedBytes > 0 {
                            Text("Clean Caches (\(formatBytes(scannerService.totalSelectedBytes)))")
                        } else {
                            Text("Quick Scan & Clean Caches")
                        }
                        Spacer()
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .liquidGlassPill(tint: .mint, isProminent: true)
                .disabled(scannerService.isScanning || scannerService.isCleaning)

                HStack {
                    Button {
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: "main-window")
                    } label: {
                        Text("Open Dashboard")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    .liquidGlassPill(tint: .cyan, isProminent: false)

                    Spacer()

                    Button("Quit ZenMac") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .frame(width: 305)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
