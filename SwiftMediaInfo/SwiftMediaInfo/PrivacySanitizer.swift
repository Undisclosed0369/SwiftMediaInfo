//
//  PrivacySanitizer.swift
//  SwiftMediaInfo
//
//  PHASE 5 — strips local paths from anything leaving the machine.
//
//  THE PROBLEM
//
//  MediaInfo's General track includes CompleteName — the full absolute path of
//  the file — and FolderName, its containing directory. Every output format
//  carries them: Text, Raw Text, JSON, XML, HTML, and CSV. Before this, Share
//  uploaded those verbatim to a public paste service.
//
//  A path like
//      /Users/username/StreamripDownloads/artist - album/track.flac
//  discloses the account name, the machine's directory layout, and often
//  something about how the file was obtained. None of that is what someone
//  means to share when they share a media report.
//
//  SCOPE — this runs on SHARE ONLY.
//
//  Copy and Export are untouched, deliberately. Those write to the user's own
//  machine, where the path is theirs and frequently the reason they exported.
//  Sanitising them would be destroying information nobody asked to lose. The
//  distinction is "is this leaving the machine", not "is this sensitive".
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
        let folderPath = fileURL.standardizedFileURL
            .deletingLastPathComponent()
            .path(percentEncoded: false)
        let homePath   = FileManager.default.homeDirectoryForCurrentUser
            .standardizedFileURL
            .path(percentEncoded: false)
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

/// Stored privacy preferences.
enum PrivacyPreference {
    static let shareKey = "sharePrivacyMode"
    static let localKey = "localPrivacyMode"
    
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

/// Every temporary file this app writes lives inside a uniquely named,
/// owner-only directory that is removed when the work finishes.
///
/// The previous share path wrote to a predictable name in the shared temp
/// directory (`<basename>_mediainfo.zip`), which any local process could
/// anticipate, read, or pre-create. Uploads are the one place where that
/// matters most, because the contents are about to be made public.
struct SecureTemporaryDirectory {
    
    let url: URL
    
    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftMediaInfo", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        
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
