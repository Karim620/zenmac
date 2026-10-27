//
//  MainWindowView.swift
//  ZenMac
//
//  Primary NavigationSplitView container with native macOS Liquid Glass geometry & refraction.
//

import SwiftUI

public enum ZenNavigationTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case cleaner = "Safe Cleaner"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .dashboard:
            return "gauge.with.dots.needle.33percent"
        case .cleaner:
            return "sparkles"
        }
    }
}

public struct MainWindowView: View {
    @Bindable var monitorService: SystemMonitorService
    @Bindable var scannerService: DiskScannerService
    @State private var selectedTab: ZenNavigationTab = .dashboard

    public init(monitorService: SystemMonitorService, scannerService: DiskScannerService) {
        self.monitorService = monitorService
        self.scannerService = scannerService
    }

    public var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 215, ideal: 230, max: 260)
        } detail: {
            ZStack {
                LiquidAmbientBackground()

                Group {
                    switch selectedTab {
                    case .dashboard:
                        DashboardView(
                            monitorService: monitorService,
                            scannerService: scannerService,
                            onNavigateToCleaner: { selectedTab = .cleaner }
                        )
                    case .cleaner:
                        CleanerView(scannerService: scannerService)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(selectedTab.rawValue)
        .frame(minWidth: 880, minHeight: 600)
    }

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Liquid Glass Brand Header Pill
            HStack(spacing: 12) {
                AppLogoView(size: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text("ZenMac")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                    Text("Liquid Darwin Engine")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .liquidGlassCard(cornerRadius: 20, tint: .mint, isInteractive: false)
            .padding(.horizontal, 12)
            .padding(.top, 10)

            // Custom Liquid Glass Navigation Pills
            VStack(spacing: 8) {
                ForEach(ZenNavigationTab.allCases) { tab in
                    let isSelected = (selectedTab == tab)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(isSelected ? .mint : .secondary)
                                .frame(width: 22)

                            Text(tab.rawValue)
                                .font(.system(.body, design: .rounded).weight(isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? .primary : .secondary)

                            Spacer()

                            if isSelected {
                                Capsule()
                                    .fill(Color.mint)
                                    .frame(width: 6, height: 16)
                                    .shadow(color: .mint.opacity(0.7), radius: 4)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .liquidGlassPill(tint: isSelected ? .mint : .cyan, isProminent: isSelected)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            // Mini status capsule in sidebar
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(monitorService.isMonitoring ? Color.mint : Color.orange)
                        .frame(width: 8, height: 8)
                        .shadow(color: .mint.opacity(0.8), radius: 5)
                    Text("Mach Host Polling: 1.0s")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.primary.opacity(0.85))
                }
                Text("Non-Destructive Guard Active")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassCard(cornerRadius: 18, tint: .cyan, isInteractive: false)
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - App Logo View with Liquid Glass Rim & Glow

public struct AppLogoView: View {
    public var size: CGFloat = 38

    public init(size: CGFloat = 38) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            // Liquid Glass circular backdrop
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.cyan.opacity(0.35),
                                    Color.mint.opacity(0.12),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: size * 0.75
                            )
                        )
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.75), .cyan.opacity(0.4), .white.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: .cyan.opacity(0.35), radius: 10, x: 0, y: 3)

            if let img = loadAppLogo() {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.85, height: size * 0.85)
                    .shadow(color: .cyan.opacity(0.45), radius: 6)
            } else {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.cyan)
            }
        }
        .frame(width: size, height: size)
    }

    private func loadAppLogo() -> NSImage? {
        // 1. Direct bundle resource
        if let url = Bundle.main.url(forResource: "icon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        // 2. Resources directory inside bundle
        let resURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/icon.png")
        if let img = NSImage(contentsOf: resURL) {
            return img
        }
        // 3. Application icon from system
        if let icon = NSApplication.shared.applicationIconImage, icon.isValid {
            return icon
        }
        // 4. File in current or parent working directory
        let searchPaths = [
            "icon.png",
            "../icon.png",
            "/Users/karimalshamy/dev/mac-cleaner-stats/icon.png"
        ]
        for p in searchPaths {
            let u = URL(fileURLWithPath: p)
            if let img = NSImage(contentsOf: u) {
                return img
            }
        }
        return nil
    }
}

