//
//  DiskScannerService.swift
//  ZenMac
//
//  APFS-aware, non-destructive developer & user cache scanner and cleaner.
//  Uses FileManager.enumerator with .totalFileAllocatedSizeKey for exact physical block sizes.
//

import Foundation
import Observation
import OSLog

@MainActor
@Observable
public final class DiskScannerService {
    private let logger = Logger(subsystem: "com.zenmac.app", category: "DiskScannerService")

    public private(set) var categories: [CacheCategory] = []
    public private(set) var isScanning: Bool = false
    public private(set) var isCleaning: Bool = false
    public private(set) var lastReport: CleanupReport?
    public var selectedStrategy: CleanupStrategy = .moveToTrash

    private let worker = APFSDiskWorker()

    public init() {
        self.categories = Self.buildDefaultCategories()
    }

    /// Total physical disk space across all discovered cache categories.
    public var totalDiscoveredBytes: UInt64 {
        categories.reduce(0) { $0 + $1.totalAllocatedBytes }
    }

    /// Total physical disk space currently selected for cleanup.
    public var totalSelectedBytes: UInt64 {
        categories.reduce(0) { $0 + $1.selectedAllocatedBytes }
    }

    /// Scans all safe cache targets concurrently using APFS physical block allocation keys.
    public func scanAllCategories() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        for index in categories.indices {
            categories[index].isScanning = true
        }

        let currentCategories = categories
        let scannedCategories = await withTaskGroup(of: (Int, CacheCategory).self) { group in
            for (index, category) in currentCategories.enumerated() {
                group.addTask { [worker] in
                    let updated = await worker.scanCategory(category)
                    return (index, updated)
                }
            }

            var results = currentCategories
            for await (index, updated) in group {
                results[index] = updated
            }
            return results
        }

        self.categories = scannedCategories
    }

    /// Executes cleanup (Trash, Permanent Delete, or Dry-Run Preview) on selected items.
    public func executeCleanup(strategy: CleanupStrategy? = nil) async -> CleanupReport {
        let activeStrategy = strategy ?? selectedStrategy
        isCleaning = true
        defer { isCleaning = false }

        let itemsToProcess: [CacheItem] = categories
            .filter(\.isSelected)
            .flatMap { $0.items.filter(\.isSelected) }

        let report = await worker.performCleanup(items: itemsToProcess, strategy: activeStrategy)
        self.lastReport = report

        if activeStrategy != .dryRun {
            await scanAllCategories()
        }

        return report
    }

    /// Toggles selection for an entire category.
    public func toggleCategorySelection(categoryID: String, isSelected: Bool) {
        guard let idx = categories.firstIndex(where: { $0.id == categoryID }) else { return }
        categories[idx].isSelected = isSelected
        for itemIdx in categories[idx].items.indices {
            categories[idx].items[itemIdx].isSelected = isSelected
        }
    }

    /// Toggles selection for an individual item within a category.
    public func toggleItemSelection(categoryID: String, itemID: String, isSelected: Bool) {
        guard let catIdx = categories.firstIndex(where: { $0.id == categoryID }),
              let itemIdx = categories[catIdx].items.firstIndex(where: { $0.id == itemID }) else {
            return
        }
        categories[catIdx].items[itemIdx].isSelected = isSelected
        if isSelected && !categories[catIdx].isSelected {
            categories[catIdx].isSelected = true
        }
    }

    // MARK: - Default Safe Whitelist Targets

    private static func buildDefaultCategories() -> [CacheCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser

        // Critical Apple & system bundle directories inside ~/Library/Caches that must never be touched
        let protectedSystemCacheNames: Set<String> = [
            "CloudKit",
            "FamilyCircle",
            "GeoServices",
            "PassKit",
            "Safari",
            "com.apple.Safari",
            "com.apple.bird",
            "com.apple.cloudd",
            "com.apple.nsurlsessiond",
            "com.apple.ap.adprivacyd",
            "com.apple.HomeKit",
            "com.apple.iCloudHelper",
            "com.apple.Spotlight",
            "com.apple.parsecd",
            "com.apple.accountsd",
            "com.apple.akd",
            // Exclude caches already covered by dedicated developer categories below
            "Homebrew",
            "Yarn"
        ]

        return [
            CacheCategory(
                id: "user_app_caches",
                title: "User App Caches",
                subtitle: "~/Library/Caches (Excludes CloudKit, Safari & critical system services)",
                systemImage: "internaldrive.fill",
                targetURLs: [home.appendingPathComponent("Library/Caches", isDirectory: true)],
                scanMode: .topLevelChildren(excludedDirectoryNames: protectedSystemCacheNames)
            ),
            CacheCategory(
                id: "xcode_derived_data",
                title: "Xcode DerivedData",
                subtitle: "~/Library/Developer/Xcode/DerivedData (Intermediate build artifacts & indexes)",
                systemImage: "hammer.fill",
                targetURLs: [home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)],
                scanMode: .directoryContents
            ),
            CacheCategory(
                id: "homebrew_cache",
                title: "Homebrew Cache",
                subtitle: "~/Library/Caches/Homebrew (Downloaded bottles & source archives)",
                systemImage: "mug.fill",
                targetURLs: [home.appendingPathComponent("Library/Caches/Homebrew", isDirectory: true)],
                scanMode: .directoryContents
            ),
            CacheCategory(
                id: "node_package_caches",
                title: "Node / npm / pnpm / Yarn Caches",
                subtitle: "~/.npm/_cacache, ~/Library/Caches/Yarn, ~/Library/pnpm/store",
                systemImage: "shippingbox.fill",
                targetURLs: [
                    home.appendingPathComponent(".npm/_cacache", isDirectory: true),
                    home.appendingPathComponent("Library/Caches/Yarn", isDirectory: true),
                    home.appendingPathComponent("Library/pnpm/store", isDirectory: true)
                ],
                scanMode: .directoryContents
            ),
            CacheCategory(
                id: "user_logs",
                title: "User Application Logs",
                subtitle: "~/Library/Logs (Diagnostic & application log files)",
                systemImage: "doc.text.fill",
                targetURLs: [home.appendingPathComponent("Library/Logs", isDirectory: true)],
                scanMode: .directoryContents
            )
        ]
    }
}

// MARK: - APFS Background Scanner & Non-Destructive Guardrail Worker

private actor APFSDiskWorker {
    private let logger = Logger(subsystem: "com.zenmac.app", category: "APFSDiskWorker")

    private static let resourceKeys: [URLResourceKey] = [
        .isRegularFileKey,
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey,
        .contentModificationDateKey
    ]

    /// Strict immutable blocklist preventing accidental modification of system, credential, or user data directories.
    private let blockedPathPrefixes: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        return [
            "/System",
            "/Library",
            "/Applications",
            "/bin",
            "/sbin",
            "/usr",
            "/var",
            "/private",
            "/etc",
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Downloads",
            "\(home)/Pictures",
            "\(home)/Movies",
            "\(home)/Music",
            "\(home)/Library/Application Support",
            "\(home)/Library/Preferences",
            "\(home)/Library/Keychains",
            "\(home)/Library/Safari",
            "\(home)/Library/Mail",
            "\(home)/Library/Messages",
            "\(home)/Library/Mobile Documents",
            "\(home)/Library/IdentityServices",
            "\(home)/Library/Calendars",
            "\(home)/Library/Contacts"
        ]
    }()

    func scanCategory(_ category: CacheCategory) -> CacheCategory {
        var updated = category
        updated.isScanning = false

        var discoveredItems: [CacheItem] = []
        var anyTargetExists = false
        let fm = FileManager.default

        for rootURL in category.targetURLs {
            let standardizedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: standardizedRoot.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            guard isSafeTargetURL(standardizedRoot) else {
                continue
            }
            anyTargetExists = true

            guard let children = try? fm.contentsOfDirectory(
                at: standardizedRoot,
                includingPropertiesForKeys: Self.resourceKeys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for childURL in children {
                let childName = childURL.lastPathComponent

                if case .topLevelChildren(let excludedNames) = category.scanMode {
                    if excludedNames.contains(childName) || childName.hasPrefix("com.apple.Safari") {
                        continue
                    }
                }

                guard isSafeTargetURL(childURL) else { continue }

                let allocatedBytes = calculatePhysicalAllocatedBytes(for: childURL)
                guard allocatedBytes > 0 else { continue }

                let modDate = (try? childURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                let displayName = category.targetURLs.count > 1
                    ? "\(rootURL.lastPathComponent)/\(childName)"
                    : childName

                discoveredItems.append(
                    CacheItem(
                        name: displayName,
                        url: childURL,
                        allocatedBytes: allocatedBytes,
                        modificationDate: modDate,
                        isSelected: category.isSelected
                    )
                )
            }
        }

        discoveredItems.sort { $0.allocatedBytes > $1.allocatedBytes }
        updated.items = discoveredItems
        updated.existsOnDisk = anyTargetExists
        return updated
    }

    func performCleanup(items: [CacheItem], strategy: CleanupStrategy) -> CleanupReport {
        // Hard safety check: refuse to operate if running as root (UID == 0)
        if getuid() == 0 {
            return CleanupReport(
                strategy: strategy,
                processedItemsCount: 0,
                skippedOrFailedCount: items.count,
                bytesReclaimed: 0,
                dryRunPaths: [],
                errors: ["Security violation: ZenMac refuses to execute cleanup as root (UID 0)."],
                timestamp: Date()
            )
        }

        let fm = FileManager.default
        var processedCount = 0
        var failedCount = 0
        var reclaimedBytes: UInt64 = 0
        var dryRunPaths: [String] = []
        var errors: [String] = []

        for item in items {
            guard isSafeTargetURL(item.url) else {
                failedCount += 1
                errors.append("Blocked by safety policy: \(item.url.lastPathComponent)")
                continue
            }

            guard fm.fileExists(atPath: item.url.path) else {
                continue
            }

            switch strategy {
            case .dryRun:
                processedCount += 1
                reclaimedBytes += item.allocatedBytes
                dryRunPaths.append(item.url.path)

            case .moveToTrash:
                do {
                    var resultingURL: NSURL?
                    try fm.trashItem(at: item.url, resultingItemURL: &resultingURL)
                    processedCount += 1
                    reclaimedBytes += item.allocatedBytes
                } catch {
                    failedCount += 1
                    errors.append("\(item.name): \(error.localizedDescription)")
                }

            case .directRemove:
                do {
                    try fm.removeItem(at: item.url)
                    processedCount += 1
                    reclaimedBytes += item.allocatedBytes
                } catch {
                    failedCount += 1
                    errors.append("\(item.name): \(error.localizedDescription)")
                }
            }
        }

        return CleanupReport(
            strategy: strategy,
            processedItemsCount: processedCount,
            skippedOrFailedCount: failedCount,
            bytesReclaimed: reclaimedBytes,
            dryRunPaths: dryRunPaths,
            errors: errors,
            timestamp: Date()
        )
    }

    // MARK: - Fast APFS Physical Block Size Calculation

    /// Computes physical allocated size on APFS using `.totalFileAllocatedSizeKey` (falling back to `.fileAllocatedSizeKey`).
    /// Never follows symbolic links outside the target tree.
    private func calculatePhysicalAllocatedBytes(for url: URL) -> UInt64 {
        let keySet = Set(Self.resourceKeys)

        guard let values = try? url.resourceValues(forKeys: keySet) else {
            return 0
        }

        if values.isSymbolicLink == true {
            return 0
        }

        if values.isDirectory != true {
            return UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Self.resourceKeys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var totalBytes: UInt64 = 0

        for case let fileURL as URL in enumerator {
            guard let itemValues = try? fileURL.resourceValues(forKeys: keySet) else {
                continue
            }

            if itemValues.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }

            if itemValues.isRegularFile == true {
                let allocated = itemValues.totalFileAllocatedSize
                    ?? itemValues.fileAllocatedSize
                    ?? itemValues.fileSize
                    ?? 0
                totalBytes += UInt64(max(0, allocated))
            }
        }

        return totalBytes
    }

    // MARK: - Path Safety Verification

    private func isSafeTargetURL(_ url: URL) -> Bool {
        let resolvedPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path

        // Must reside strictly inside the current user's home directory
        guard resolvedPath.hasPrefix(homePath + "/") else {
            return false
        }

        // Must never match or reside inside any blocked prefix
        for blockedPrefix in blockedPathPrefixes {
            if resolvedPath == blockedPrefix || resolvedPath.hasPrefix(blockedPrefix + "/") {
                return false
            }
        }

        return true
    }
}
