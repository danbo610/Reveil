//
//  DiskUsage.swift
//  Reveil
//
//  Created by Lessica on 2023/10/2.
//

import Foundation

final class DiskUsage {
    static let shared = DiskUsage()

    // The dashboard's timer asks every module to reload once a second. Free space does not move
    // that fast, and asking for it is not free, so the answer is kept for a while.
    private static let refreshInterval: TimeInterval = 10
    private var lastRefresh: Date

    private init() {
        totalDiskSpaceInBytes = Self.getTotalDiskSpaceInBytes()
        freeDiskSpaceInBytes = Self.getFreeDiskSpaceInBytes()
        lastRefresh = Date()
    }

    private static func getTotalDiskSpaceInBytes() -> Int64 {
        if let systemAttributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory() as String),
           let space = (systemAttributes[FileAttributeKey.systemSize] as? NSNumber)?.int64Value
        {
            space
        } else {
            0
        }
    }

    var totalDiskSpaceInBytes: Int64

    private static func getFreeDiskSpaceInBytes() -> Int64 {
        // Not volumeAvailableCapacityForImportantUsageKey. That one reports free space plus
        // whatever could be purged to make room, which it works out by asking every registered
        // cache-delete service in turn — around forty round trips per call on this device, and
        // the dashboard was making that call on the main thread once a second. The plain key is
        // a statfs, and it agrees with df and with the app's own file system page.
        if let space = try? URL(fileURLWithPath: NSHomeDirectory() as String).resourceValues(forKeys: [URLResourceKey.volumeAvailableCapacityKey]).volumeAvailableCapacity {
            Int64(space)
        } else {
            0
        }
    }

    var freeDiskSpaceInBytes: Int64

    func reloadData() {
        guard Date().timeIntervalSince(lastRefresh) >= Self.refreshInterval else {
            return
        }
        totalDiskSpaceInBytes = Self.getTotalDiskSpaceInBytes()
        freeDiskSpaceInBytes = Self.getFreeDiskSpaceInBytes()
        lastRefresh = Date()
    }

    var usedDiskSpaceInBytes: Int64 { totalDiskSpaceInBytes - freeDiskSpaceInBytes }
    var usedRatio: Double { Double(usedDiskSpaceInBytes) / Double(totalDiskSpaceInBytes) }
}
