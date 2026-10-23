//
//  AppSupport.swift
//  SwiftMediaInfo
//
//  The app's folder in Application Support,
//  ~/Library/Application Support/SwiftMediaInfo, which holds:
//
//  • AnalysisCache/ — whole analyses, so files reopen instantly (AnalysisCache)
//  • HashCache.json — SHA-256 checksums already calculated (FileHasher)
//  • TimeSpent.plist — the time-spent total's backup copy (UsageTracker)
//
//  Temporary files (preview clips, share uploads) go in the temporary folder
//  instead; see SecureTemporaryDirectory.
//

import Foundation

nonisolated enum AppSupport {
    /// ~/Library/Application Support/SwiftMediaInfo. Nil if the system can't
    /// provide Application Support.
    static var folder: URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        
        return support.appendingPathComponent("SwiftMediaInfo", isDirectory: true)
    }
}
