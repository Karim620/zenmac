//
//  CacheCategory.swift
//  ZenMac
//
//  Models for non-destructive developer and user cache scanning & cleanup.
//

import Foundation

/// Defines how a cache category should be cleaned to remain 100% non-destructive.
public enum CacheTargetScanMode: Sendable, Equatable {
    /// Clean individual child folders/files inside the target directory while preserving the parent directory and excluded bundle IDs.
    case topLevelChildren(excludedDirectoryNames: Set<String>)
    /// Clean the contents of the directory as a whole or its immediate subdirectories.
    case directoryContents
}

/// Represents an individual sub-item (e.g., a specific Xcode DerivedData project or app cache folder) within a category.
public struct CacheItem: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let url: URL
    public let allocatedBytes: UInt64
    public let modificationDate: Date?
    public var isSelected: Bool

    public init(
        name: String,
        url: URL,
        allocatedBytes: UInt64,
        modificationDate: Date? = nil,
        isSelected: Bool = true
    ) {
        self.id = url.path
        self.name = name
        self.url = url
        self.allocatedBytes = allocatedBytes
        self.modificationDate = modificationDate
        self.isSelected = isSelected
    }
}

/// A safe, regenerable developer or user cache target category.
public struct CacheCategory: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let systemImage: String
    public let targetURLs: [URL]
    public let scanMode: CacheTargetScanMode
    public var items: [CacheItem]
    public var isSelected: Bool
    public var isScanning: Bool
    public var existsOnDisk: Bool

    public init(
        id: String,
        title: String,
        subtitle: String,
        systemImage: String,
        targetURLs: [URL],
        scanMode: CacheTargetScanMode,
        items: [CacheItem] = [],
        isSelected: Bool = true,
        isScanning: Bool = false,
        existsOnDisk: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.targetURLs = targetURLs
        self.scanMode = scanMode
        self.items = items
        self.isSelected = isSelected
        self.isScanning = isScanning
        self.existsOnDisk = existsOnDisk
    }

    /// Total physical APFS allocated bytes across all discovered items in this category.
    public var totalAllocatedBytes: UInt64 {
        items.reduce(0) { $0 + $1.allocatedBytes }
    }

    /// Physical bytes of items currently selected for cleanup.
    public var selectedAllocatedBytes: UInt64 {
        guard isSelected else { return 0 }
        return items.filter(\.isSelected).reduce(0) { $0 + $1.allocatedBytes }
    }
}

/// Specifies the cleanup execution strategy.
public enum CleanupStrategy: String, CaseIterable, Identifiable, Sendable {
    case moveToTrash = "Move to Trash"
    case directRemove = "Permanent Delete"
    case dryRun = "Dry-Run"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .moveToTrash: return "trash"
        case .directRemove: return "xmark.bin.fill"
        case .dryRun: return "eye"
        }
    }
}

/// Summary report returned after executing a cleanup or dry-run operation.
public struct CleanupReport: Sendable, Equatable {
    public let strategy: CleanupStrategy
    public let processedItemsCount: Int
    public let skippedOrFailedCount: Int
    public let bytesReclaimed: UInt64
    public let dryRunPaths: [String]
    public let errors: [String]
    public let timestamp: Date
}
