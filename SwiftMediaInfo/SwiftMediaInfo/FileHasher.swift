//
//  FileHasher.swift
//  SwiftMediaInfo
//
//  PHASE 10 — SHA-256 checksums.
//
//  WHY STREAMING
//
//  The whole point of this feature is large files. Reading one into memory to
//  hash it would mean a 50 GB allocation, so the file is read in fixed chunks
//  and fed to the digest as it goes. Memory use is constant regardless of file
//  size — a few megabytes, not fifty gigabytes.
//
//  WHY CANCELLABLE
//
//  A 50 GB file is several minutes of sustained disk reading. Anything that
//  runs that long and cannot be stopped is a trap, so cancellation is checked
//  between chunks and the file handle is always closed on the way out.
//
//  WHY THE THRESHOLD IS A FLOOR, NOT A CEILING
//
//  Only files above 10 GB are hashed. This is a deliberate product decision:
//  the checksum is here for large archival files where verifying an exact copy
//  matters, not as a field on every clip. Files below the threshold show no
//  checksum at all and offer no button.
//
//  ON PROGRESS BEING REAL
//
//  Unlike the Homebrew install in Phase 9, this progress is genuine — we know
//  the file size and how many bytes we have read. So this one gets a real bar.
//

import Foundation
import CryptoKit
import AppKit

// MARK: - Policy

/// What the app does about checksums, chosen in Settings.
enum HashPolicy: String, CaseIterable, Identifiable {
    /// Hash eligible files as soon as they open.
    case always
    /// Never hash, and offer no button.
    case never
    /// Offer a button on eligible files, but do nothing until it is pressed.
    case manual
    
    var id: String { rawValue }
    
    static let key = "hashPolicy"
    
    var title: String {
        switch self {
        case .always: return "On"
        case .never:  return "Off"
        case .manual: return "Manual"
        }
    }
    
    var explanation: String {
        switch self {
        case .always:
            return "Files over 10 GB are hashed as soon as they open."
        case .never:
            return "No checksums are calculated and no button is shown."
        case .manual:
            return "Files over 10 GB show a button, and nothing happens until you press it."
        }
    }
    
    /// The shipped default.
    ///
    /// Changed to `.manual` in Phase 11, from `.always`. Hashing a file over
    /// 10 GB is minutes of solid disk reading, and doing that unasked the
    /// instant a file opens is a large decision to make on someone's behalf —
    /// especially when most people opening a huge file want its metadata, not
    /// its digest. `.manual` still shows the button on every eligible file, so
    /// nothing becomes harder to find; it just waits to be asked.
    static let shippedDefault: HashPolicy = .manual
    
    /// Read from defaults, falling back to the shipped default.
    static var current: HashPolicy {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let policy = HashPolicy(rawValue: raw) else { return shippedDefault }
        return policy
    }
}

// MARK: - State

/// Where one file's checksum has got to.
enum HashState: Equatable {
    /// Not applicable — under the size threshold, or the policy is Off.
    case notApplicable
    /// Eligible and waiting for the user to ask. Only reachable under Manual.
    case awaitingRequest
    /// Running. The fraction is real, measured against the file size.
    case hashing(progress: Double)
    /// Finished. The lowercase hex digest.
    case ready(digest: String)
    /// Stopped at the user's request.
    case cancelled
    /// Something went wrong; the reason is fit to show.
    case failed(reason: String)
    
    var digest: String? {
        if case .ready(let digest) = self { return digest }
        return nil
    }
    
    var isRunning: Bool {
        if case .hashing = self { return true }
        return false
    }
    
    /// Whether a "Compute Checksum" control should be offered.
    var isRequestable: Bool {
        switch self {
        case .awaitingRequest, .cancelled, .failed: return true
        case .notApplicable, .hashing, .ready:      return false
        }
    }
}

// MARK: - Hasher

// Every member below is `nonisolated`.
//
// This project builds with Default Actor Isolation set to MainActor, so a
// plain `static let` here would belong to the main actor — and the hashing
// loop runs in a detached task, which cannot touch it.
//
// Xcode offers to fix that by inserting `await` at each use. Do not take it.
// Awaiting `chunkSize` inside the read loop would hop to the main thread once
// per 4 MB chunk — roughly thirteen thousand hops for a 50 GB file, each one
// competing with the UI it is trying to keep responsive. These are immutable
// constants of Sendable type with nothing to protect, so the right answer is
// to say they belong to no actor at all.
enum FileHasher {
    
    /// Files at or below this size are not hashed. See the note at the top.
    nonisolated static let sizeThreshold: Int64 = 10 * 1024 * 1024 * 1024   // 10 GB
    
    /// The MediaInfo-style field key the digest is injected under.
    ///
    /// Chosen to sit alongside real MediaInfo keys without pretending to be
    /// one — nothing in MediaInfo's own output uses this name, so a reader
    /// comparing two reports can tell where it came from.
    nonisolated static let fieldKey = "SHA256"
    
    /// Read size in bytes. Four megabytes is comfortably past the point where
    /// syscall overhead matters and far below anything that would show up as
    /// a memory spike.
    nonisolated private static let chunkSize = 4 * 1024 * 1024
    
    enum HashError: LocalizedError {
        case cannotOpen(String)
        case readFailed(String)
        
        // `LocalizedError` declares this without isolation, so under default
        // MainActor isolation it has to be opted out explicitly or the
        // conformance does not hold.
        nonisolated var errorDescription: String? {
            switch self {
            case .cannotOpen(let detail): return "The file couldn’t be opened for reading. \(detail)"
            case .readFailed(let detail): return "Reading the file failed partway through. \(detail)"
            }
        }
    }
    
    /// File size in bytes, or nil when it cannot be determined.
    nonisolated static func fileSize(of url: URL) -> Int64? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return Int64(size)
    }
    
    /// Whether this file is big enough to be worth a checksum.
    ///
    /// Directories are excluded outright. A folder has no single stream of
    /// bytes to hash, and hashing its contents would be a different feature
    /// with different rules.
    nonisolated static func isEligible(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        guard values?.isDirectory != true else { return false }
        
        guard let size = fileSize(of: url) else { return false }
        return size > sizeThreshold
    }
    
    /// Hash a file, reporting progress as it goes.
    ///
    /// Runs off the main actor. Progress is delivered on the main actor so the
    /// caller can assign it to published state without hopping itself.
    nonisolated static func sha256(
        of url: URL,
        onProgress: @escaping @Sendable @MainActor (Double) -> Void
    ) async throws -> String {
        let totalBytes = fileSize(of: url) ?? 0
        
        // NOT `Task.detached`.
        //
        // The loop used to run inside a detached task, and detached tasks do
        // not inherit cancellation. So the Stop button cancelled the outer
        // task, the detached one carried on reading to the end of the file,
        // and the disk stayed busy for minutes with nothing on screen to
        // explain it. This function is `nonisolated`, which is already enough
        // to keep it off the main actor; running it in the caller's task is
        // what makes Stop actually stop.
        do {
            guard let handle = try? FileHandle(forReadingFrom: url) else {
                throw HashError.cannotOpen("It may have been moved or deleted.")
            }
            
            // Read without filling the unified buffer cache.
            //
            // Streaming 14 GB through the page cache evicts everything else in
            // it, which is why other files felt slow to open and why the HTML
            // and XML tabs — which make mediainfo re-read the file — stalled
            // until hashing finished. F_NOCACHE tells the kernel this data is
            // read once and never wanted again.
            //
            // The result is discarded deliberately. This is an optimisation,
            // not a requirement: on a filesystem that does not support it the
            // call fails, the read still works, and there is nothing useful to
            // tell the user about it.
            _ = fcntl(handle.fileDescriptor, F_NOCACHE, 1)
            
            // Closed on every exit path, including a thrown error and a
            // cancellation. An open descriptor left behind by a cancelled hash
            // would leak one per attempt.
            defer { try? handle.close() }
            
            var digest = SHA256()
            var bytesRead: Int64 = 0
            
            // Progress is reported at most about forty times over the whole
            // file. Publishing on every 4 MB chunk would put thousands of
            // updates through SwiftUI for a large file, and a progress bar
            // cannot show more than a few hundred distinct positions anyway.
            var lastReported: Double = -1
            
            while true {
                try Task.checkCancellation()
                
                let chunk: Data?
                do {
                    chunk = try handle.read(upToCount: chunkSize)
                } catch {
                    throw HashError.readFailed(error.localizedDescription)
                }
                
                guard let chunk, !chunk.isEmpty else { break }
                
                digest.update(data: chunk)
                bytesRead += Int64(chunk.count)
                
                // A suspension point every chunk. Without one, a multi-minute
                // read holds its thread for the whole time and cancellation
                // can only be noticed between chunks by luck.
                await Task.yield()
                
                if totalBytes > 0 {
                    let fraction = min(Double(bytesRead) / Double(totalBytes), 1.0)
                    if fraction - lastReported >= 0.025 {
                        lastReported = fraction
                        await onProgress(fraction)
                    }
                }
            }
            
            await onProgress(1.0)
            
            return digest.finalize()
                .map { String(format: "%02x", $0) }
                .joined()
        }
    }
}

// MARK: - Cache
//
// Hashing a 50 GB file is minutes of disk reading. Doing that again every time
// the same file is reopened would make the feature feel punitive, so digests
// are remembered between launches.
//
// THE KEY IS IDENTITY, NOT LOCATION
//
// A path alone is not enough: edit a file in place and the path is unchanged
// while every byte after the edit is different, so a path-keyed cache would
// confidently return a digest for content that no longer exists. The key
// includes the size and the modification date, so any edit that changes either
// — which is any edit macOS records — misses the cache and re-hashes.
//
// It can still be wrong in one narrow case: a change that preserves both size
// and timestamp exactly. That takes deliberate effort, and the escape hatch is
// the Clear button in Settings.

enum HashCache {
    
    /// Where the cache lives on disk.
    ///
    /// A file rather than UserDefaults. Defaults would work, but "how much
    /// space is this using" and "show me" have no honest answer when the data
    /// is buried inside a preferences plist shared with every other setting.
    /// A named file in Application Support can be measured and revealed.
    static var fileURL: URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        
        return support
            .appendingPathComponent("SwiftMediaInfo", isDirectory: true)
            .appendingPathComponent("HashCache.json")
    }
    
    /// Beyond this many entries the cache is reset.
    ///
    /// Entries are about 150 bytes each, so two hundred is around 30 KB — far
    /// more files than anyone revisits, and the cost of a miss is a re-hash
    /// rather than an error.
    private static let maximumEntries = 200
    
    /// Identity for one file: path, size, and modification time.
    private static func identity(for url: URL) -> String? {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        
        guard let values = try? url.resourceValues(forKeys: keys),
              let size = values.fileSize,
              let modified = values.contentModificationDate else { return nil }
        
        return "\(url.path(percentEncoded: false))|\(size)|\(Int(modified.timeIntervalSince1970))"
    }
    
    private static func load() -> [String: String] {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        
        return entries
    }
    
    private static func save(_ entries: [String: String]) {
        guard let fileURL else { return }
        
        // The containing folder may not exist on a first run.
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
    
    static func digest(for url: URL) -> String? {
        guard let identity = identity(for: url) else { return nil }
        return load()[identity]
    }
    
    static func store(_ digest: String, for url: URL) {
        guard let identity = identity(for: url) else { return }
        
        var entries = load()
        entries[identity] = digest
        
        // A dictionary has no true "oldest", so past the cap the cache is
        // simply reset down to the new entry. Crude, but the only cost of
        // being wrong is re-hashing a file nobody had opened in a long time.
        if entries.count > maximumEntries {
            entries = [identity: digest]
        }
        
        save(entries)
    }
    
    /// How many digests are remembered.
    static var count: Int { load().count }
    
    /// Size on disk, formatted. Empty when there is no cache file yet.
    static var sizeOnDisk: String {
        guard let fileURL,
              let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0
        else { return "0 bytes" }
        
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
    
    static var exists: Bool {
        guard let fileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false))
    }
    
    /// Show the cache file in Finder.
    static func revealInFinder() {
        guard let fileURL else { return }
        
        if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            // Nothing cached yet. Opening the folder is more useful than doing
            // nothing and leaving the user wondering if the button is broken.
            NSWorkspace.shared.open(fileURL.deletingLastPathComponent())
        }
    }
    
    static func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - Injecting the digest into an existing report
//
// The digest is added to each format in whatever way that format can absorb it
// without becoming invalid. A checksum that breaks the XML it was added to is
// worse than no checksum.

extension FileHasher {
    
    /// A plain, human-readable line used by the text formats.
    nonisolated static func plainLine(_ digest: String) -> String {
        "SHA-256                                  : \(digest)"
    }
    
    nonisolated static func appendToText(_ content: String, digest: String) -> String {
        content.trimmingCharacters(in: .newlines)
        + "\n\n" + plainLine(digest) + "\n"
    }
    
    /// XML gets a comment in the epilogue.
    ///
    /// Adding an element would put the document outside MediaInfo's own
    /// schema, and anything validating against it would start failing. A
    /// comment after the root element is valid XML and breaks nothing.
    nonisolated static func appendToXML(_ content: String, digest: String) -> String {
        content.trimmingCharacters(in: .newlines)
        + "\n<!-- SHA-256: \(digest) -->\n"
    }
    
    /// JSON gets a real top-level key, inserted without reformatting.
    ///
    /// Parsing and re-serialising would produce valid JSON but scramble the
    /// field order, and MediaInfo's ordering is meaningful to anyone reading
    /// it. So the key is spliced in immediately after the document's opening
    /// brace, leaving every original byte untouched. If no opening brace is
    /// found the content is returned unchanged rather than corrupted.
    nonisolated static func appendToJSON(_ content: String, digest: String) -> String {
        guard let brace = content.firstIndex(of: "{") else { return content }
        
        let insertionPoint = content.index(after: brace)
        var result = content
        result.insert(contentsOf: "\n  \"SHA256\": \"\(digest)\",", at: insertionPoint)
        return result
    }
    
    /// HTML gets a visible paragraph, because an HTML report is meant to be
    /// read rather than parsed. Placed inside the body when there is one.
    nonisolated static func appendToHTML(_ content: String, digest: String) -> String {
        let block = "<p style=\"font-family:monospace;margin-top:1em;\"><b>SHA-256:</b> \(digest)</p>"
        
        if let range = content.range(of: "</body>", options: [.caseInsensitive, .backwards]) {
            return content.replacingCharacters(in: range, with: block + "\n</body>")
        }
        
        return content + "\n" + block + "\n"
    }
}
