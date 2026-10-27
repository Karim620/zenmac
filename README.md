# 🧘‍♂️ ZenMac

> **A 100% Native, lightweight, non-destructive macOS system monitor & developer cache cleaner built with Swift 6, SwiftUI, and Darwin/Mach APIs.**

![ZenMac App Icon](icon.png)

ZenMac is a minimalist macOS utility (targeting **macOS 14.0+ Sonoma / Sequoia**) built for developers and power users who want real-time kernel telemetry and safe storage reclamation without risking system integrity. Unlike bloated Electron wrappers or aggressive cleaners that demand `sudo` and run destructive `rm -rf` commands, **ZenMac is engineered from the ground up using native Darwin/Mach APIs and strict non-destructive guardrails.**

---

## ✨ Key Engineering Highlights

- **⚡ Zero Shell Subprocesses:** Never spawns `Process()` / `NSTask` to run `top`, `vm_stat`, `df`, or `du`. All telemetry is sampled directly from the XNU kernel via Mach traps (`host_processor_info`, `host_statistics64(HOST_CPU_LOAD_INFO)`, `host_statistics64(HOST_VM_INFO64)`) and `statfs`.
- **🪶 Ultra-Low Footprint:** Targets **< 25 MB RAM** and **< 1% CPU** during active 1-second polling, with deterministic `vm_deallocate` Mach buffer cleanup.
- **💾 APFS-Aware Physical Sizing:** Uses `FileManager.enumerator` with `.totalFileAllocatedSizeKey` and `.volumeAvailableCapacityForImportantUsageKey` for accurate physical block allocation and purgeable space telemetry on APFS volumes.
- **🧹 Safe Developer & User Cache Cleaner:** Targets strictly regenerable caches (`Xcode DerivedData`, `Homebrew`, `npm` / `pnpm` / `Yarn`, `~/Library/Caches`, and `~/Library/Logs`) with **Move to Trash**, **Dry-Run Preview**, and **Permanent Delete** modes.
- **🪟 Native macOS Vibrancy & Menu Bar Extra:** Built with SwiftUI `NavigationSplitView`, `.ultraThinMaterial` glass vibrancy, and a live `MenuBarExtra` status bar widget.

---

## 🔒 Security Architecture (4 Core Pillars)

| Pillar | Implementation |
| :--- | :--- |
| **1. Hard Anti-Root Check (`UID != 0`)** | On launch (`ZenMacApp.init`) and before any cleanup (`APFSDiskWorker`), ZenMac checks `getuid() == 0`. If run with `sudo` or as `root`, it immediately aborts. |
| **2. Strict Whitelist & Protected Bundle Exclusions** | Only scans predefined regenerable cache paths. Automatically excludes critical Apple services in `~/Library/Caches` (`CloudKit`, `Safari`, `PassKit`, `GeoServices`, `FamilyCircle`, etc.). |
| **3. Symlink-Resolved Blocklist** | Resolves symlinks (`resolvingSymlinksInPath()`) and blocks operations on `/System`, `/Library`, `/Applications`, `~/Desktop`, `~/Documents`, `~/Downloads`, `~/Library/Application Support`, `~/Library/Preferences`, and `~/Library/Keychains`. |
| **4. Reversible Cleanup & Dry-Run** | Defaults to `FileManager.default.trashItem(at:resultingItemURL:)` so cleaned caches can be restored from the macOS Trash, alongside a zero-modification **Dry-Run Preview** inspector. |

---

## 🗂️ Project Structure

```text
ZenMac/
├── ZenMacApp.swift                  # App entry point, anti-root check, WindowGroup & MenuBarExtra scenes
├── Models/
│   ├── SystemMetrics.swift          # Sendable structs for CPUMetrics, MemoryMetrics & MemoryPressureLevel
│   ├── StorageVolume.swift          # APFS/POSIX volume capacity & purgeable space model
│   └── CacheCategory.swift          # CacheCategory, CacheItem, CleanupStrategy & CleanupReport models
├── Services/
│   ├── SystemMonitorService.swift   # @Observable @MainActor service + MachTelemetrySampler actor
│   └── DiskScannerService.swift     # Concurrent APFS block scanner & non-destructive cleanup actor
└── Views/
    ├── MainWindowView.swift         # NavigationSplitView with .ultraThinMaterial vibrancy
    ├── DashboardView.swift          # Live CPU gauges, sparkline, VM_INFO64 RAM & APFS storage bars
    ├── CleanerView.swift            # Category disclosure list, Dry-Run sheet & Trash execution
    └── MenuBarView.swift            # Lightweight MenuBarExtra status item & 1-click safe clean
```

---

## 🚀 Getting Started

### Prerequisites

- **macOS 14.0+** (Sonoma or Sequoia)
- **Xcode 16.0+** (Swift 6 toolchain)

### Build & Run via Swift Package Manager / CLI

```bash
# Clone the repository
git clone https://github.com/yourusername/zenmac.git
cd mac-cleaner-stats

# Compile with Swift 6 strict concurrency
swift build -c release

# Or open directly in Xcode
xed .
```

### Configuring Xcode Signing & Capabilities

1. **App Sandbox:** Disable `App Sandbox` under **Signing & Capabilities** (or set `com.apple.security.app-sandbox` to `false`) so `FileManager` can directly inspect and clean `~/Library/Developer/Xcode/DerivedData`, `~/Library/Caches/Homebrew`, `~/.npm/_cacache`, and `~/Library/pnpm/store`.
2. **Hardened Runtime:** Keep **Hardened Runtime** enabled for macOS Notarization outside the Mac App Store.
3. **Full Disk Access (Optional):** If macOS TCC restricts specific third-party subdirectories inside `~/Library/Caches` or `~/Library/Logs`, grant ZenMac permission in **System Settings → Privacy & Security → Full Disk Access**.

---

## 🛠️ Tech Stack

- **Language:** Swift 6 (Strict Concurrency, `Sendable`, Actors, `@Observable`)
- **UI Framework:** SwiftUI (`NavigationSplitView`, `MenuBarExtra`, `.ultraThinMaterial`)
- **System Telemetry:** Darwin / Mach (`host_processor_info`, `host_statistics64`, `statfs`, `URLResourceKey`)
- **Zero External Dependencies:** Pure Apple system frameworks (`SwiftUI`, `Foundation`, `AppKit`, `Darwin`, `OSLog`)
