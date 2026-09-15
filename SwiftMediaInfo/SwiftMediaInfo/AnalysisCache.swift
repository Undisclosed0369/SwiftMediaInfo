//
//  AnalysisCache.swift
//  SwiftMediaInfo
//
//  PHASE 10 — remembering a whole analysis, not just its checksum.
//
//  WHAT IT SOLVES
//
//  Reopening a file re-ran mediainfo from scratch every time. For a 50 GB
//  Matroska with forty-odd subtitle tracks that is a real wait, and the answer
//  is identical to the one produced a minute earlier. Nothing about a file that
//  has not changed can produce different metadata.
//
//  ONE FILE PER ENTRY
//
//  Rather than a single dictionary rewritten on every save. Entries hold five
//  format strings and can reach a few hundred kilobytes; rewriting the whole
//  cache to add one would mean writing megabytes to update a few pages, and a
//  crash mid-write would take every entry with it. Separate files also make
//  "show me" in Finder mean something.
//
//  IDENTITY, NOT LOCATION
//
//  Same scheme as HashCache: path, size and modification date. Any edit macOS
//  records changes at least one of the three, so a changed file misses and is
//  re-analysed.
//
//  VERSION STAMPED
//
//  Each entry records the mediainfo build that produced it. A newer mediainfo
//  can report fields the cached output does not have, so an entry from an older
//  build is offered for re-analysis rather than silently trusted or silently
//  discarded — see `isStale`. The checksum survives that: SHA-256 of the same
//  bytes does not depend on which version of mediainfo looked at them.
//
//  NO SIZE CAP
//
//  Deliberate. A cap means quietly throwing away work the user might be about
//  to want, and the only honest way to decide what to drop is to ask. Settings
//  shows the size and offers Clear.
//

import Foundation
import AppKit
import CryptoKit

// MARK: - One cached analysis

struct CachedAnalysis: Codable {
    /// The mediainfo build that produced this. Empty when it could not be
    /// determined, which is treated as "do not claim it is current".
    var mediaInfoVersion: String = ""
    
    var rawText:     String? = nil
    var rawTextFull: String? = nil
    var rawHTML:     String? = nil
    var rawXML:      String? = nil
    var rawJSON:     String? = nil
    
    /// Kept alongside the formats so one lookup answers both questions.
    var digest: String? = nil
    
    /// Whether the three formats loaded on open are all present.
    ///
    /// HTML and XML are deliberately excluded — they load only when their tab
    /// is opened, so requiring them would mean an entry never counted as
    /// usable for anyone who never visits those tabs.
    var hasInitialFormats: Bool {
        rawText != nil && rawTextFull != nil && rawJSON != nil
    }
    
    func isStale(against current: String?) -> Bool {
        guard let current, !current.isEmpty, !mediaInfoVersion.isEmpty else { return false }
        return mediaInfoVersion != current
    }
}

// MARK: - Store

enum AnalysisCache {
    
    static var directoryURL: URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        
        return support
            .appendingPathComponent("SwiftMediaInfo", isDirectory: true)
            .appendingPathComponent("AnalysisCache", isDirectory: true)
    }
    
    /// Path, size and modification time — the same identity HashCache uses.
    private static func identity(for url: URL) -> String? {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        
        guard let values = try? url.resourceValues(forKeys: keys),
              let size = values.fileSize,
              let modified = values.contentModificationDate else { return nil }
        
        return "\(url.path(percentEncoded: false))|\(size)|\(Int(modified.timeIntervalSince1970))"
    }
    
    /// A filename-safe, fixed-length name for an identity.
    ///
    /// Hashed rather than escaped: a path can be longer than a filename is
    /// allowed to be, and can contain characters a filename cannot. This is a
    /// naming scheme, not a security boundary.
    private static func fileURL(for url: URL) -> URL? {
        guard let identity = identity(for: url),
              let directory = directoryURL,
              let data = identity.data(using: .utf8) else { return nil }
        
        let name = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        
        return directory.appendingPathComponent(name + ".json")
    }
    
    static func entry(for url: URL) -> CachedAnalysis? {
        guard let fileURL = fileURL(for: url),
              let data = try? Data(contentsOf: fileURL),
              let entry = try? JSONDecoder().decode(CachedAnalysis.self, from: data)
        else { return nil }
        
        return entry
    }
    
    /// Read, change, write. Creates the entry when there isn't one.
    ///
    /// A read-modify-write rather than a plain set, because the five formats
    /// arrive at different times — three on open, HTML and XML only if their
    /// tabs are visited, the digest possibly minutes later. Each writes its own
    /// part without disturbing the others.
    static func update(for url: URL, _ mutate: (inout CachedAnalysis) -> Void) {
        guard let fileURL = fileURL(for: url) else { return }
        
        var entry = entry(for: url) ?? CachedAnalysis()
        mutate(&entry)
        
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
    
    /// Drop one entry, keeping the digest.
    ///
    /// Used when re-analysing after a mediainfo upgrade. The bytes have not
    /// changed, so the checksum is still correct and re-reading 50 GB to
    /// confirm what we already know would be the wrong kind of thorough.
    static func invalidateFormats(for url: URL, keepingDigest digest: String?) {
        update(for: url) { entry in
            entry = CachedAnalysis(mediaInfoVersion: "", digest: digest ?? entry.digest)
        }
    }
    
    // MARK: Housekeeping
    
    private static var files: [URL] {
        guard let directoryURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.fileSizeKey]
              )
        else { return [] }
        
        return contents.filter { $0.pathExtension == "json" }
    }
    
    static var count: Int { files.count }
    
    static var sizeOnDisk: String {
        let total = files.reduce(into: Int64(0)) { sum, url in
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                sum += Int64(size)
            }
        }
        
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
    
    static func revealInFinder() {
        guard let directoryURL else { return }
        
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        
        NSWorkspace.shared.open(directoryURL)
    }
    
    static func clear() {
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
