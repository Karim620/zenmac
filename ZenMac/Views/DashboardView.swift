//
//  DashboardView.swift
//  ZenMac
//
//  Real-time CPU, Memory Pressure (Active + Wired + Compressed), and APFS Storage Dashboard
//  styled with Liquid Glass continuous squircles and specular edge refraction.
//

import SwiftUI

public struct DashboardView: View {
    @Bindable var monitorService: SystemMonitorService
    @Bindable var scannerService: DiskScannerService
    var onNavigateToCleaner: () -> Void

    public init(
        monitorService: SystemMonitorService,
        scannerService: DiskScannerService,
        onNavigateToCleaner: @escaping () -> Void = {}
    ) {
        self.monitorService = monitorService
        self.scannerService = scannerService
        self.onNavigateToCleaner = onNavigateToCleaner
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                headerBanner

                HStack(spacing: 20) {
                    cpuCard
                    memoryCard
                }

                storageCard
                cacheOverviewCard
            }
            .padding(26)
        }
    }

    // MARK: - Header Banner

    private var headerBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("System Telemetry")
                    .font(.system(.title2, design: .rounded).bold())
                Text("Direct Mach kernel statistics (`host_statistics64` & `statfs`) — zero shell subprocesses")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await monitorService.refreshNow() }
            } label: {
                Label("Sample Now", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .liquidGlassPill(tint: .cyan, isProminent: false)
        }
    }

    // MARK: - CPU Load Card (Liquid Glass Squircle)

    private var cpuCard: some View {
        let cpu = monitorService.metrics.cpu

        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("CPU Load", systemImage: "cpu.fill")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.cyan)
                Spacer()
                Text(String(format: "%.1f%%", cpu.totalUsagePercentage))
                    .font(.system(.title3, design: .rounded).monospacedDigit().bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .liquidGlassPill(tint: .cyan, isProminent: false)
            }

            HStack(spacing: 22) {
                LiquidCircularGauge(
                    percentage: cpu.totalUsagePercentage,
                    tint: cpuGaugeColor(cpu.totalUsagePercentage),
                    subtitle: "Active"
                )
                .frame(width: 102, height: 102)

                VStack(alignment: .leading, spacing: 9) {
                    metricRow(label: "User", value: String(format: "%.1f%%", cpu.userPercentage), color: .cyan)
                    metricRow(label: "System", value: String(format: "%.1f%%", cpu.systemPercentage), color: .indigo)
                    metricRow(label: "Idle", value: String(format: "%.1f%%", cpu.idlePercentage), color: .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SparklineBarView(samples: monitorService.cpuHistory, tint: .cyan)
                .frame(height: 38)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .liquidGlassCard(cornerRadius: 26, tint: .cyan)
    }

    // MARK: - Memory Pressure Card (Liquid Glass Squircle)

    private var memoryCard: some View {
        let mem = monitorService.metrics.memory
        let pColor = pressureColor(mem.pressureLevel)

        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Memory (VM_INFO64)", systemImage: "memorychip.fill")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.mint)
                Spacer()
                Text(mem.pressureLevel.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(pColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .liquidGlassPill(tint: pColor, isProminent: false)
            }

            HStack(spacing: 22) {
                LiquidCircularGauge(
                    percentage: mem.usagePercentage,
                    tint: pColor,
                    subtitle: ByteCountFormatter.string(fromByteCount: Int64(mem.usedBytes), countStyle: .memory)
                )
                .frame(width: 102, height: 102)

                VStack(alignment: .leading, spacing: 9) {
                    metricRow(label: "Active", value: formatBytes(mem.activeBytes), color: .mint)
                    metricRow(label: "Wired", value: formatBytes(mem.wiredBytes), color: .orange)
                    metricRow(label: "Compressed", value: formatBytes(mem.compressedBytes), color: .purple)
                    metricRow(label: "Total Physical", value: formatBytes(mem.totalBytes), color: .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Liquid tube progress bar
            LiquidTubeBar(percentage: mem.usagePercentage, colors: [pColor, .cyan])
                .frame(height: 10)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .liquidGlassCard(cornerRadius: 26, tint: .mint)
    }

    // MARK: - APFS Storage Volume Card

    private var storageCard: some View {
        let volume = monitorService.metrics.primaryVolume

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("\(volume.name) (\(volume.fileSystemType.uppercased()))", systemImage: "internaldrive.fill")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Text("\(formatBytes(volume.usedBytes)) used of \(formatBytes(volume.totalBytes))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            LiquidTubeBar(percentage: volume.usagePercentage, colors: [.blue, .cyan, .mint])
                .frame(height: 14)

            HStack {
                Text("Available (Important Usage): \(formatBytes(volume.availableBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if volume.purgeableBytes > 0 {
                    Text("APFS Purgeable Space: \(formatBytes(volume.purgeableBytes))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.mint)
                }
            }
        }
        .padding(22)
        .liquidGlassCard(cornerRadius: 26, tint: .blue)
    }

    // MARK: - Cache Quick Summary Card

    private var cacheOverviewCard: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.mint.opacity(0.35), .cyan.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                    )

                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
                    .shadow(color: .mint.opacity(0.6), radius: 6)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Reclaimable Developer & User Caches")
                    .font(.system(.headline, design: .rounded))
                if scannerService.totalDiscoveredBytes > 0 {
                    Text("\(formatBytes(scannerService.totalDiscoveredBytes)) discovered across safe regenerable caches.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Run an APFS block scan to inspect Xcode DerivedData, Homebrew, npm/pnpm/Yarn, and App Caches.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                onNavigateToCleaner()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("Open Safe Cleaner")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .liquidGlassPill(tint: .mint, isProminent: true)
        }
        .padding(22)
        .liquidGlassCard(cornerRadius: 26, tint: .mint)
    }

    // MARK: - Helpers

    private func metricRow(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.7), radius: 3)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
        }
    }

    private func cpuGaugeColor(_ percentage: Double) -> Color {
        if percentage > 85 { return .red }
        if percentage > 60 { return .orange }
        return .cyan
    }

    private func pressureColor(_ level: MemoryPressureLevel) -> Color {
        switch level {
        case .nominal: return .mint
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - Liquid Glass Gauge, Tube & Sparkline Subviews

private struct LiquidCircularGauge: View {
    let percentage: Double
    let tint: Color
    let subtitle: String

    var body: some View {
        let clamped = min(100.0, max(0.0, percentage)) / 100.0
        ZStack {
            // Outer glass bezel ring
            Circle()
                .fill(.ultraThinMaterial.opacity(0.5))
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.45), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                )

            // Track ring
            Circle()
                .stroke(.white.opacity(0.09), lineWidth: 10)
                .padding(6)

            // Glowing liquid arc
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.6), tint, .white.opacity(0.9), tint],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(6)
                .shadow(color: tint.opacity(0.55), radius: 6)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: clamped)

            VStack(spacing: 2) {
                Text(String(format: "%.0f%%", percentage))
                    .font(.system(.callout, design: .rounded).bold().monospacedDigit())
                Text(subtitle)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct LiquidTubeBar: View {
    let percentage: Double
    let colors: [Color]

    var body: some View {
        GeometryReader { geo in
            let ratio = min(1.0, max(0.02, percentage / 100.0))
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.08))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(0.20), lineWidth: 0.8)
                    )

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        // Top specular tube reflection
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.45), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .frame(width: geo.size.width * ratio)
                    .shadow(color: (colors.last ?? .cyan).opacity(0.45), radius: 5, x: 0, y: 2)
                    .animation(.spring(response: 0.4, dampingFraction: 0.82), value: ratio)
            }
        }
    }
}

private struct SparklineBarView: View {
    let samples: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let count = max(1, samples.count)
            let spacing: CGFloat = 4
            let barWidth = max(2, (geo.size.width - CGFloat(count - 1) * spacing) / CGFloat(count))

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, value in
                    let normalized = min(1.0, max(0.08, value / 100.0))
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.85), tint.opacity(0.80), tint.opacity(0.35)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: barWidth, height: geo.size.height * normalized)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}
