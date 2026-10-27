//
//  ZenMacApp.swift
//  ZenMac
//
//  Main application entry point targeting macOS 14.0+ (Sonoma / Sequoia) & Swift 6.
//

import SwiftUI
import AppKit
import Darwin

@main
struct ZenMacApp: App {
    @State private var monitorService: SystemMonitorService
    @State private var scannerService: DiskScannerService

    init() {
        // Security Pillar 1: Hard block against root / sudo execution
        if getuid() == 0 {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Security Policy Violation"
            alert.informativeText = "ZenMac is strictly a non-destructive user-space utility and refuses to run as root (UID 0). Please launch ZenMac as a standard macOS user."
            alert.runModal()
            exit(EXIT_FAILURE)
        }

        let monitor = SystemMonitorService()
        let scanner = DiskScannerService()
        _monitorService = State(initialValue: monitor)
        _scannerService = State(initialValue: scanner)

        monitor.startMonitoring(intervalSeconds: 1.0)
    }

    var body: some Scene {
        WindowGroup("ZenMac", id: "main-window") {
            MainWindowView(
                monitorService: monitorService,
                scannerService: scannerService
            )
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 940, height: 640)

        MenuBarExtra {
            MenuBarView(
                monitorService: monitorService,
                scannerService: scannerService
            )
        } label: {
            let cpu = Int(monitorService.metrics.cpu.totalUsagePercentage.rounded())
            let ram = Int(monitorService.metrics.memory.usagePercentage.rounded())
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                Text("CPU \(cpu)% · RAM \(ram)%")
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .menuBarExtraStyle(.window)
    }
}
