//
//  ViewMode.swift
//  SwiftMediaInfo
//
//  PHASE 1 — the only change here is that MediaFile can now remember why a
//  format failed to load, instead of just holding nil and leaving the UI to
//  guess whether that meant "not loaded yet", "empty", or "something broke".
//
//  The existing isLoading flags are untouched, so no view needs to change yet.
//  Phase 3 replaces flags + errors with a single explicit state model.
//

import Foundation
import SwiftUI

// MARK: - View Modes

enum ViewMode: String, CaseIterable, Identifiable {
    case easy, text, rawText, html, xml, json
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .easy:    return "Easy"
        case .text:    return "Text"
        case .rawText: return "Raw Text"
        case .html:    return "HTML"
        case .xml:     return "XML"
        case .json:    return "JSON"
        }
    }
    
    var icon: String {
        switch self {
        case .easy:    return "list.bullet.rectangle"
        case .text:    return "doc.text"
        case .rawText: return "text.alignleft"
        case .html:    return "globe"
        case .xml:     return "chevron.left.forwardslash.chevron.right"
        case .json:    return "curlybraces"
        }
    }
    
    var shortcut: KeyEquivalent {
        switch self {
        case .easy:    return "1"
        case .text:    return "2"
        case .rawText: return "3"
        case .html:    return "4"
        case .xml:     return "5"
        case .json:    return "6"
        }
    }
}

// MARK: - Export Format

enum ExportFormat: String, CaseIterable, Identifiable {
    case text, rawText, html, xml, json, csv
    var id: String { rawValue }
    
    var fileExtension: String {
        switch self {
        case .rawText: return "txt"   // raw text is still a .txt file
        default:       return rawValue
        }
    }
    
    var label: String {
        switch self {
        case .text:    return "Text (.txt)"
        case .rawText: return "Raw Text (.txt)"
        case .html:    return "HTML (.html)"
        case .xml:     return "XML (.xml)"
        case .json:    return "JSON (.json)"
        case .csv:     return "CSV (.csv)"
        }
    }
    
    /// System image name for the export popover icon
    var icon: String {
        switch self {
        case .text:    return "doc.text"
        case .rawText: return "text.alignleft"
        case .html:    return "globe"
        case .xml:     return "chevron.left.forwardslash.chevron.right"
        case .json:    return "curlybraces"
        case .csv:     return "tablecells"
        }
    }
}

// MARK: - Track

struct MediaTrack: Identifiable {
    let id = UUID()
    let type: String
    let streamIndex: Int
    var fields: [(key: String, value: String)]
    
    var typeIcon: String {
        switch type {
        case "Video":  return "film"
        case "Audio":  return "waveform"
        case "Text":   return "captions.bubble"
        case "Menu":   return "list.number"
        case "Image":  return "photo"
        default:       return "info.circle"
        }
    }
    
    var displayTitle: String {
        if type == "General" { return "General" }
        let lang  = fields.first(where: { $0.key == "Language/String" })?.value
        ?? fields.first(where: { $0.key == "Language" })?.value ?? ""
        let title = fields.first(where: { $0.key == "Title" })?.value ?? ""
        var parts: [String] = [streamIndex > 0 ? "\(type) #\(streamIndex + 1)" : type]
        if !lang.isEmpty  { parts.append(lang) }
        if !title.isEmpty { parts.append(title) }
        return parts.joined(separator: " · ")
    }
    
    /// Look up a single field's value by its raw MediaInfo key.
    func value(for key: String) -> String? {
        fields.first(where: { $0.key == key })?.value
    }
}

// MARK: - MediaFile
//
// Each format string starts as nil (not yet loaded).
// nil  = not fetched yet  →  show "Load" button
// ""   = fetched but empty (unlikely)
// text = ready to display
//
// Each format now also has a matching error slot. nil error + nil content
// means "not loaded yet"; non-nil error means "we tried and it failed".

struct MediaFile: Identifiable, Equatable {
    let id   = UUID()
    let url  : URL
    
    /// Written explicitly because `parsedTracks` below is private, which makes
    /// the synthesised memberwise initialiser private too — and both call
    /// sites construct a MediaFile from just a URL.
    init(url: URL) {
        self.url = url
    }
    
    // Parsed track data (from JSON). Populated automatically with Easy view.
    //
    // PHASE 10 — stored separately from what callers read, because the
    // checksum is injected on the way out.
    //
    // The digest used to be written into the stored array when hashing
    // finished. That worked for about a second: a cached digest is applied the
    // instant a file opens, and the JSON analysis then finishes and replaces
    // the whole array, taking the injected field with it. Injecting on read
    // makes the order irrelevant.
    private var parsedTracks: [MediaTrack] = []
    
    var tracks: [MediaTrack] {
        get {
            // The overwhelmingly common case — no digest — returns the stored
            // array untouched, so this costs nothing for files that are not
            // hashed.
            guard let digest = hashState.digest else { return parsedTracks }
            
            return parsedTracks.map { track in
                guard track.type == "General" else { return track }
                
                var updated = track
                let entry = (key: FileHasher.fieldKey, value: digest)
                
                // Appended rather than inserted: the fields before it are what
                // MediaInfo actually reported, and a value the app calculated
                // itself should not push them down the list.
                if let index = updated.fields.firstIndex(where: { $0.key == FileHasher.fieldKey }) {
                    updated.fields[index] = entry
                } else {
                    updated.fields.append(entry)
                }
                
                return updated
            }
        }
        set { parsedTracks = newValue }
    }
    
    // Per-format raw strings. nil means "not loaded yet".
    var rawText:     String? = nil   // normal mediainfo output
    var rawTextFull: String? = nil   // --Full output  (Raw Text view)
    var rawHTML:     String? = nil
    var rawXML:      String? = nil
    var rawJSON:     String? = nil   // also drives the Easy view
    
    // Per-format loading flags (true while the background task is running)
    var isLoadingText:     Bool = false
    var isLoadingRawText:  Bool = false
    var isLoadingHTML:     Bool = false
    var isLoadingXML:      Bool = false
    var isLoadingJSON:     Bool = false
    
    // Per-format failure reasons. nil means "no failure recorded".
    var textError:    MediaInfoError? = nil
    var rawTextError: MediaInfoError? = nil
    var htmlError:    MediaInfoError? = nil
    var xmlError:     MediaInfoError? = nil
    var jsonError:    MediaInfoError? = nil
    
    /// The failure that best represents "this file could not be analysed".
    /// Set when the initial parallel load fails; drives the primary error state.
    var loadError: MediaInfoError? = nil
    
    // Overall "first load in progress" flag shown in MainDetailView
    var isLoading: Bool = true
    
    /// PHASE 10 — where this file's SHA-256 has got to.
    ///
    /// The finished digest is also injected into the General track as a normal
    /// field, so Easy View, Compare Mode's diff, search, CSV export and the
    /// copy actions all pick it up without knowing hashing exists. This
    /// property carries the states a plain field cannot: waiting, running,
    /// cancelled, failed.
    var hashState: HashState = .notApplicable
    
    static func == (lhs: MediaFile, rhs: MediaFile) -> Bool { lhs.id == rhs.id }
    
    var fileName:       String { url.lastPathComponent }
    
    var fileSizeString: String {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
    
    /// Whether this "file" is actually a directory. Folders are valid input —
    /// mediainfo describes their contents — but they have no track structure,
    /// so Easy View needs to say something more useful than "no tracks found".
    var isDirectory: Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
    
    /// The error for a specific view mode, if that format failed.
    func error(for mode: ViewMode) -> MediaInfoError? {
        switch mode {
        case .easy, .json: return jsonError
        case .text:        return textError
        case .rawText:     return rawTextError
        case .html:        return htmlError
        case .xml:         return xmlError
        }
    }
    
    var generalTrack: MediaTrack?  { tracks.first(where: { $0.type == "General" }) }
    var videoTracks:  [MediaTrack] { tracks.filter { $0.type == "Video" } }
    var audioTracks:  [MediaTrack] { tracks.filter { $0.type == "Audio" } }
    var textTracks:   [MediaTrack] { tracks.filter { $0.type == "Text"  } }
    var menuTracks:   [MediaTrack] { tracks.filter { $0.type == "Menu"  } }
}
