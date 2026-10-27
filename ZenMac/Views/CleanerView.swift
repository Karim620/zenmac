//
//  CleanerView.swift
//  ZenMac
//
//  Non-destructive Developer & User Cache Cleaner styled with Liquid Glass squircles & capsule pills.
//

import SwiftUI

public struct CleanerView: View {
    @Bindable var scannerService: DiskScannerService
    @State private var showingDryRunSheet = false
    @State private var showingConfirmationAlert = false

    public init(scannerService: DiskScannerService) {
        self.scannerService = scannerService
    }

    public var body: some View {
        VStack(spacing: 0) {
            cleanerHeader
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let report = scannerService.lastReport {
                        reportBanner(report)
                    }

                    ForEach(scannerService.categories) { category in
                        categorySection(category)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }

            cleanerActionFooter
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .liquidGlassCard(cornerRadius: 20, tint: .mint, isInteractive: false)
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, 16)
        }
        .sheet(isPresented: $showingDryRunSheet) {
            if let report = scannerService.lastReport {
                DryRunPreviewSheet(report: report)
            }
        }
        .alert("Confirm Cache Cleanup", isPresented: $showingConfirmationAlert) {
            Button("Cancel", role: .cancel) {}
            Button(
                scannerService.selectedStrategy == .directRemove ? "Delete Permanently" : "Move to Trash",
                role: scannerService.selectedStrategy == .directRemove ? .destructive : nil
            ) {
                Task {
                    _ = await scannerService.executeCleanup()
                }
            }
        } message: {
            Text(
                "Ready to process \(formatBytes(scannerService.totalSelectedBytes)) using strategy: \(scannerService.selectedStrategy.rawValue)."
            )
        }
        .task {
            if scannerService.totalDiscoveredBytes == 0 && !scannerService.isScanning {
                await scannerService.scanAllCategories()
            }
        }
    }

    // MARK: - Header (Liquid Glass Banner)

    private var cleanerHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Safe Developer & User Cache Cleaner")
                    .font(.system(.title2, design: .rounded).bold())
                Text("APFS `.totalFileAllocatedSizeKey` physical block sizing. Never touches Application Support, Keychains, or Preferences.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatBytes(scannerService.totalSelectedBytes))
                    .font(.system(.title2, design: .rounded).monospacedDigit().bold())
                    .foregroundStyle(.mint)
                Text("Selected to Reclaim")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .liquidGlassCard(cornerRadius: 16, tint: .mint, isInteractive: false)

            Button {
                Task { await scannerService.scanAllCategories() }
            } label: {
                HStack(spacing: 6) {
                    if scannerService.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    Text("Rescan APFS")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .liquidGlassPill(tint: .cyan, isProminent: false)
            .disabled(scannerService.isScanning || scannerService.isCleaning)
        }
    }

    // MARK: - Category Expandable Liquid Glass Card

    private func categorySection(_ category: CacheCategory) -> some View {
        DisclosureGroup {
            if category.items.isEmpty {
                HStack {
                    Text(category.existsOnDisk ? "No cleanable cache items found." : "Directory not present on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(category.items.prefix(35)) { item in
                        HStack {
                            Toggle(
                                isOn: Binding(
                                    get: { item.isSelected },
                                    set: { scannerService.toggleItemSelection(categoryID: category.id, itemID: item.id, isSelected: $0) }
                                )
                            ) {
                                Text(item.name)
                                    .font(.callout)
                                    .lineLimit(1)
                            }
                            .toggleStyle(.checkbox)

                            Spacer()

                            Text(formatBytes(item.allocatedBytes))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.white.opacity(0.06), in: Capsule())
                        }
                        .padding(.vertical, 3)
                    }
                    if category.items.count > 35 {
                        Text("+ \(category.items.count - 35) additional cache items included")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                }
                .padding(.top, 10)
            }
        } label: {
            HStack(spacing: 14) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { category.isSelected },
                        set: { scannerService.toggleCategorySelection(categoryID: category.id, isSelected: $0) }
                    )
                )
                .toggleStyle(.checkbox)
                .labelsHidden()

                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.mint.opacity(0.32), .cyan.opacity(0.14)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                        )

                    Image(systemName: category.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.system(.headline, design: .rounded))
                    Text(category.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if category.isScanning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatBytes(category.totalAllocatedBytes))
                            .font(.system(.subheadline, design: .rounded).monospacedDigit().weight(.semibold))
                        Text("\(category.items.count) items")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .liquidGlassPill(tint: .cyan, isProminent: false)
                }
            }
            .padding(.vertical, 4)
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: 22, tint: .cyan)
    }

    // MARK: - Footer Controls

    private var cleanerActionFooter: some View {
        HStack(spacing: 12) {
            // Custom Liquid Glass Segmented Pill Selector
            HStack(spacing: 4) {
                ForEach(CleanupStrategy.allCases) { strategy in
                    let isSelected = (scannerService.selectedStrategy == strategy)
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            scannerService.selectedStrategy = strategy
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: strategy.iconName)
                                .font(.system(size: 11, weight: .semibold))
                            Text(strategy.rawValue)
                                .font(.caption.weight(isSelected ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background {
                            if isSelected {
                                Capsule(style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                (strategy == .directRemove ? Color.orange : Color.mint).opacity(0.38),
                                                (strategy == .directRemove ? Color.orange : Color.cyan).opacity(0.18)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                                    )
                            }
                        }
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(.black.opacity(0.22), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .fixedSize()

            Spacer(minLength: 8)

            Button {
                Task {
                    _ = await scannerService.executeCleanup(strategy: .dryRun)
                    showingDryRunSheet = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                    Text("Preview")
                        .lineLimit(1)
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .liquidGlassPill(tint: .cyan, isProminent: false)
            .disabled(scannerService.totalSelectedBytes == 0 || scannerService.isScanning || scannerService.isCleaning)

            Button {
                if scannerService.selectedStrategy == .dryRun {
                    Task {
                        _ = await scannerService.executeCleanup(strategy: .dryRun)
                        showingDryRunSheet = true
                    }
                } else {
                    showingConfirmationAlert = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text(scannerService.selectedStrategy == .directRemove ? "Clean Permanently" : "Clean Selected")
                        .lineLimit(1)
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .liquidGlassPill(
                tint: scannerService.selectedStrategy == .directRemove ? .orange : .mint,
                isProminent: true
            )
            .disabled(scannerService.totalSelectedBytes == 0 || scannerService.isScanning || scannerService.isCleaning)
        }
    }

    // MARK: - Report Banner

    private func reportBanner(_ report: CleanupReport) -> some View {
        HStack(spacing: 12) {
            Image(systemName: report.strategy == .dryRun ? "info.circle.fill" : "checkmark.seal.fill")
                .foregroundStyle(report.strategy == .dryRun ? .cyan : .mint)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(report.strategy.rawValue): \(report.processedItemsCount) items (\(formatBytes(report.bytesReclaimed)))")
                    .font(.subheadline.weight(.semibold))
                if !report.errors.isEmpty {
                    Text("\(report.skippedOrFailedCount) items skipped due to active lock or permissions.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            if report.strategy == .dryRun && !report.dryRunPaths.isEmpty {
                Button {
                    showingDryRunSheet = true
                } label: {
                    Text("Inspect Paths")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .liquidGlassPill(tint: .cyan, isProminent: false)
            }
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: 20, tint: .mint, isInteractive: false)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - Dry-Run Preview Modal Sheet

private struct DryRunPreviewSheet: View {
    let report: CleanupReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LiquidAmbientBackground()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dry-Run Verification Preview")
                            .font(.system(.title3, design: .rounded).bold())
                        Text("Zero files were modified. Below are the exact \(report.dryRunPaths.count) paths verified for safe removal (\(ByteCountFormatter.string(fromByteCount: Int64(report.bytesReclaimed), countStyle: .file))).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    .liquidGlassPill(tint: .mint, isProminent: true)
                    .keyboardShortcut(.defaultAction)
                }

                List(report.dryRunPaths, id: \.self) { path in
                    Text(path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .scrollContentBackground(.hidden)
                .liquidGlassCard(cornerRadius: 18, tint: .cyan, isInteractive: false)
                .frame(minHeight: 300)
            }
            .padding(22)
        }
        .frame(width: 660, height: 460)
    }
}
