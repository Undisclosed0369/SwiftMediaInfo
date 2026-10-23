//
//  PrivacySanitizer.swift
//  SwiftMediaInfo
//
//  Privacy: removing local paths from reports, the privacy preferences, and
//  private temporary folders.
//
//  • PrivacySanitizer — strips paths from a report in any output format and
//    records what it removed (the Share review screen lists it).
//  • Preferences — Share (remove paths by default), Copy and Export (leave
//    them by default), HTML (its own setting), and the SHA-256 checksum
//    (left out by default); PrivacyPreference resolves each, asking the user
//    when the setting is Ask.
//  • SecureTemporaryDirectory — an owner-only folder for preview clips and
//    share uploads, removed when the work is done.
//
//  THE PROBLEM
//
//  MediaInfo's General track includes CompleteName — the full absolute path of
//  the file — and FolderName, its containing directory. Every output format
//  carries them: Text, Raw Text, JSON, XML, HTML, and CSV. A path like
//      /Users/username/StreamripDownloads/artist - album/track.flac
//  discloses the account name, the machine's directory layout, and often
//  something about how the file was obtained.
//
//  WHY THE DEFAULTS DIFFER
//
//  Share sends a report off the Mac, so paths go by default. Copy and Export
//  stay on the user's own Mac, where the path is theirs and frequently the
//  reason they exported, so they keep it unless asked. The distinction is "is
//  this leaving the machine", not "is this sensitive". Siri AI always gets
//  sanitised reports.
//
//  APPROACH
//
//  Longest-match-first replacement, applied across raw, XML-escaped, and
//  percent-encoded spellings of each needle — because the same path appears in
//  three different encodings depending on the output format, and catching only
//  the raw form would leave it intact in XML and HTML.
//

import Foundation
import AppKit

// MARK: - Report

/// A record of what sanitisation actually removed, so the user can be shown
/// the truth rather than a reassuring generality.
struct SanitizationReport: Equatable {
    
    struct Removal: Identifiable, Equatable {
        let id = UUID()
        /// Short human label, e.g. "Full file path"
        let label: String
        /// What it was replaced with, e.g. "replaced with the file name"
        let replacement: String
        /// How many times it was found across the document
        let occurrences: Int
        
        static func == (lhs: Removal, rhs: Removal) -> Bool {
            lhs.label == rhs.label && lhs.occurrences == rhs.occurrences
        }
    }
    
    var removals: [Removal] = []
    
    var isEmpty: Bool { removals.isEmpty }
    
    /// Merge reports from several documents (the ZIP case) into one summary.
    static func combining(_ reports: [SanitizationReport]) -> SanitizationReport {
        var merged: [String: Removal] = [:]
        
        for report in reports {
            for removal in report.removals {
                if let existing = merged[removal.label] {
                    merged[removal.label] = Removal(
                        label: removal.label,
                        replacement: removal.replacement,
                        occurrences: existing.occurrences + removal.occurrences
                    )
                } else {
                    merged[removal.label] = removal
                }
            }
        }
        
        // Stable, meaningful order rather than dictionary order.
        let priority = [
            "Full file path",
            "Folder location",
            "Home folder path",
            "Account name"
        ]
        
        let sorted = merged.values.sorted { lhs, rhs in
            let l = priority.firstIndex(of: lhs.label) ?? priority.count
            let r = priority.firstIndex(of: rhs.label) ?? priority.count
            if l != r { return l < r }
            return lhs.label < rhs.label
        }
        
        return SanitizationReport(removals: sorted)
    }
}

// MARK: - Sanitizer

enum PrivacySanitizer {
    
    /// Placeholder left where a directory path used to be. Chosen to be
    /// obviously deliberate — a reader should see that something was removed
    /// on purpose, not wonder whether MediaInfo failed.
    static let folderPlaceholder = "[folder path removed]"
    static let homePlaceholder   = "~"
    static let accountPlaceholder = "[user]"
    
    /// Remove local path information from one document.
    ///
    /// - Parameters:
    ///   - content: the document text, in any of MediaInfo's output formats
    ///   - fileURL: the file the document describes
    /// - Returns: the sanitised text plus a record of what was removed
    static func sanitize(_ content: String, fileURL: URL) -> (text: String, report: SanitizationReport) {
        guard !content.isEmpty else {
            return (content, SanitizationReport())
        }
        
        let fullPath   = fileURL.standardizedFileURL.path(percentEncoded: false)
        let fileName   = fileURL.lastPathComponent
        // Without their trailing slash. A directory URL's path ends in "/",
        // but MediaInfo writes FolderName without one — so with it, the
        // folder rule never matched, and "/Volumes/Drive/Movies" went out
        // untouched in every format that carries the folder name.
        let folderPath = Self.withoutTrailingSlash(fileURL.standardizedFileURL
            .deletingLastPathComponent()
            .path(percentEncoded: false))
        let homePath   = Self.withoutTrailingSlash(FileManager.default.homeDirectoryForCurrentUser
            .standardizedFileURL
            .path(percentEncoded: false))
        let account    = NSUserName()
        
        // Order matters. The full path contains the folder path, which contains
        // the home path, which contains the account name. Replacing the longest
        // needle first means each shorter one only matches where it stands
        // alone — otherwise the full path would be shredded into fragments.
        var rules: [Rule] = []
        
        rules.append(Rule(
            needle: fullPath,
            replacement: fileName,
            label: "Full file path",
            describedAs: "replaced with just the file name"
        ))
        
        if folderPath.count > 1 {
            rules.append(Rule(
                needle: folderPath,
                replacement: folderPlaceholder,
                label: "Folder location",
                describedAs: "replaced with a placeholder"
            ))
        }
        
        if homePath.count > 1 {
            rules.append(Rule(
                needle: homePath,
                replacement: homePlaceholder,
                label: "Home folder path",
                describedAs: "shortened to ~"
            ))
        }
        
        if account.count >= 3 {
            rules.append(Rule(
                needle: account,
                replacement: accountPlaceholder,
                label: "Account name",
                describedAs: "replaced with a placeholder"
            ))
        }
        
        var text = content
        var removals: [SanitizationReport.Removal] = []
        
        for rule in rules {
            var count = 0
            
            // Each needle can appear in three spellings depending on format:
            //   raw            — Text, Raw Text, CSV
            //   XML-escaped    — XML, HTML  (& becomes &amp;)
            //   percent-encoded — HTML links, JSON with encoded URLs
            for variant in rule.variants {
                guard !variant.needle.isEmpty,
                      text.contains(variant.needle) else { continue }
                
                count += text.components(separatedBy: variant.needle).count - 1
                text = text.replacingOccurrences(of: variant.needle, with: variant.replacement)
            }
            
            if count > 0 {
                removals.append(SanitizationReport.Removal(
                    label: rule.label,
                    replacement: rule.describedAs,
                    occurrences: count
                ))
            }
        }
        
        return (text, SanitizationReport(removals: removals))
    }
    
    private static func withoutTrailingSlash(_ path: String) -> String {
        var path = path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
    
    // MARK: - Rule
    
    private struct Rule {
        let needle: String
        let replacement: String
        let label: String
        let describedAs: String
        
        struct Variant {
            let needle: String
            let replacement: String
        }
        
        /// Raw, XML-escaped, and percent-encoded spellings of the same needle.
        var variants: [Variant] {
            var result = [Variant(needle: needle, replacement: replacement)]
            
            let escaped = Self.xmlEscape(needle)
            if escaped != needle {
                result.append(Variant(
                    needle: escaped,
                    replacement: Self.xmlEscape(replacement)
                ))
            }
            
            if let encoded = needle.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics
            ), encoded != needle {
                result.append(Variant(needle: encoded, replacement: replacement))
            }
            
            return result
        }
        
        private static func xmlEscape(_ value: String) -> String {
            value
                .replacingOccurrences(of: "&",  with: "&amp;")
                .replacingOccurrences(of: "<",  with: "&lt;")
                .replacingOccurrences(of: ">",  with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'",  with: "&#39;")
        }
    }
}


// MARK: - Preferences

/// What Share does about local paths.
enum SharePrivacyMode: String, CaseIterable, Identifiable {
    /// Strip paths every time. The default, and the safe choice.
    case always
    /// Decide on the review screen, per upload.
    case ask
    /// Upload exactly what MediaInfo reported.
    case never
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .always: return "Always"
        case .ask:    return "Ask"
        case .never:  return "Never"
        }
    }
}

/// What Copy and Export do about local paths.
///
/// Defaults to leaving them alone: these stay on the user's own machine, where
/// the path is theirs and frequently the reason they exported in the first
/// place. Removing it by default would be destroying information nobody asked
/// to lose.
enum LocalPrivacyMode: String, CaseIterable, Identifiable {
    case unmodified
    case ask
    case always
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .unmodified: return "Unmodified"
        case .ask:        return "Ask"
        case .always:     return "Remove"
        }
    }
}

/// Whether a calculated SHA-256 checksum goes out with copies,
/// exports and shares. Only matters for a file that has one (files over
/// 10 GB, once calculated).
enum ChecksumPrivacyMode: String, CaseIterable, Identifiable {
    /// Include it.
    case always
    /// Ask at each copy, export or share.
    case ask
    /// Leave it out. The default: a checksum identifies the exact file, so
    /// it goes out only when you choose to send it.
    case never
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .always: return "Always"
        case .ask:    return "Ask"
        case .never:  return "Never"
        }
    }
}

/// Whether HTML exports and shares keep file paths.
enum HTMLPathsMode: String, CaseIterable, Identifiable {
    case always, ask, never
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .always: return "Always"
        case .ask:    return "Ask"
        case .never:  return "Never"
        }
    }
}

/// Stored privacy preferences.
enum PrivacyPreference {
    static let shareKey = "sharePrivacyMode"
    static let localKey = "localPrivacyMode"
    static let checksumKey = "checksumPrivacyMode"
    /// Paths in HTML exports and shares. HTML follows this alone, not
    /// the two general path settings.
    static let htmlPathsKey = "htmlPathsMode"
    
    @MainActor
    static var checksum: ChecksumPrivacyMode {
        let raw = UserDefaults.standard.string(forKey: checksumKey) ?? ChecksumPrivacyMode.never.rawValue
        return ChecksumPrivacyMode(rawValue: raw) ?? .never
    }
    
    @MainActor
    static var htmlPaths: HTMLPathsMode {
        let raw = UserDefaults.standard.string(forKey: htmlPathsKey) ?? HTMLPathsMode.never.rawValue
        return HTMLPathsMode(rawValue: raw) ?? .never
    }
    
    /// Whether HTML going out now should have its paths removed. Returns nil
    /// if the user cancelled.
    @MainActor
    static func resolveHTMLPathsDecision(actionName: String) -> Bool? {
        switch htmlPaths {
        case .always: return false
        case .never:  return true
        case .ask:
            let alert = NSAlert()
            alert.messageText = "Include file paths in the HTML?"
            alert.informativeText = "MediaInfo reports the full path of each file, which includes your account name and folder layout. " + actionName + " can keep it in the HTML or replace it with just the file name."
            alert.addButton(withTitle: "Include Paths")
            alert.addButton(withTitle: "Remove Paths")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:  return false
            case .alertSecondButtonReturn: return true
            default:                       return nil
            }
        }
    }
    
    /// Whether a copy, export or share of these files should carry their
    /// SHA-256 checksums, asking when the preference says to.
    ///
    /// Files without a checksum need no decision, so the question is only
    /// ever asked when there is a checksum to include. Returns nil if the
    /// user cancelled.
    @MainActor
    static func resolveChecksumDecision(actionName: String, files: [MediaFile?]) -> Bool? {
        let withDigest = files.compactMap { $0 }.filter { $0.hashState.digest != nil }
        guard !withDigest.isEmpty else { return true }
        
        switch checksum {
        case .always: return true
        case .never:  return false
        case .ask:
            let alert = NSAlert()
            alert.messageText = "Include the SHA-256 checksum?"
            let subject = withDigest.count == 1
            ? "The report for “\(withDigest[0].url.lastPathComponent)” includes"
            : "These reports include"
            alert.informativeText = subject + " the SHA-256 checksum you calculated. It identifies the exact file, so anyone with it can tell whether they have the same copy. " + actionName + " can include it or leave it out."
            alert.addButton(withTitle: "Include Checksum")
            alert.addButton(withTitle: "Leave It Out")
            alert.addButton(withTitle: "Cancel")
            
            switch alert.runModal() {
            case .alertFirstButtonReturn:  return true
            case .alertSecondButtonReturn: return false
            default:                       return nil
            }
        }
    }
    
    /// The three answers an export of every format needs: local paths, the
    /// checksum, and paths in HTML.
    struct ExportDecisions {
        let removePaths: Bool
        let includeChecksum: Bool
        let htmlRemovePaths: Bool
    }

    /// Asks the three questions of a multi-format export, always in the same
    /// order, stopping at the first Cancel. Returns nil if the user cancelled.
    @MainActor
    static func resolveExportDecisions(actionName: String, files: [MediaFile?]) -> ExportDecisions? {
        guard let removePaths = resolveLocalDecision(actionName: actionName),
              let includeChecksum = resolveChecksumDecision(actionName: actionName, files: files),
              let htmlRemovePaths = resolveHTMLPathsDecision(actionName: actionName)
        else { return nil }
        return ExportDecisions(removePaths: removePaths, includeChecksum: includeChecksum,
                               htmlRemovePaths: htmlRemovePaths)
    }
    
    @MainActor
    static var share: SharePrivacyMode {
        let raw = UserDefaults.standard.string(forKey: shareKey) ?? SharePrivacyMode.always.rawValue
        return SharePrivacyMode(rawValue: raw) ?? .always
    }
    
    @MainActor
    static var local: LocalPrivacyMode {
        let raw = UserDefaults.standard.string(forKey: localKey) ?? LocalPrivacyMode.unmodified.rawValue
        return LocalPrivacyMode(rawValue: raw) ?? .unmodified
    }
    
    /// Resolves what Copy/Export should do right now, asking the user when the
    /// preference says to.
    ///
    /// A modal alert rather than a sheet: copy and export are immediate,
    /// synchronous actions, and threading an async decision through six export
    /// paths would add far more surface area than the question deserves.
    ///
    /// Returns nil if the user cancelled.
    @MainActor
    static func resolveLocalDecision(actionName: String) -> Bool? {
        switch local {
        case .unmodified: return false
        case .always:     return true
        case .ask:
            let alert = NSAlert()
            alert.messageText = "Include local file paths?"
            alert.informativeText = "MediaInfo reports the full path of the file, which includes your account name and folder layout. " + actionName + " can leave it in, or replace it with just the file name."
            alert.addButton(withTitle: "Include Paths")
            alert.addButton(withTitle: "Remove Paths")
            alert.addButton(withTitle: "Cancel")
            
            switch alert.runModal() {
            case .alertFirstButtonReturn:  return false
            case .alertSecondButtonReturn: return true
            default:                       return nil
            }
        }
    }
}

// MARK: - Secure temporary directories

/// A uniquely named, owner-only folder under $TMPDIR/SwiftMediaInfo, removed
/// when the work finishes. Used for share uploads and for the preview's clips
/// (prefix "Preview"). Export's ZIP staging and PDF rendering use short-lived
/// files of their own, deleted as soon as they're done.
///
/// A predictable name in the shared temp folder could be anticipated, read
/// or pre-created by any local process — which matters most for uploads,
/// whose contents are about to be made public.
struct SecureTemporaryDirectory {
    
    let url: URL
    
    /// The folder every temporary directory of the app lives in.
    static var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SwiftMediaInfo", isDirectory: true)
    }
    
    /// `prefix` names what the folder is for, with the app's process ID, so
    /// one left behind by a copy that crashed can be told apart from one in
    /// use by a copy still running (see PreviewLeftovers).
    init(prefix: String? = nil) throws {
        let name = prefix.map { "\($0)-\(getpid())-\(UUID().uuidString)" } ?? UUID().uuidString
        let base = Self.root.appendingPathComponent(name, isDirectory: true)
        
        try FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        
        self.url = base
    }
    
    func file(named name: String) -> URL {
        url.appendingPathComponent(name)
    }
    
    /// Safe to call more than once, and safe to call on a failure path.
    func cleanUp() {
        try? FileManager.default.removeItem(at: url)
    }
}
