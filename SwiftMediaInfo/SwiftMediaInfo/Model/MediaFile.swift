//
//  MediaFile.swift
//  SwiftMediaInfo
//
//  An open file and its tracks, as MediaInfo reported them.
//
//  • MediaTrack — one track's fields, in MediaInfo's order, keyed by
//    MediaInfo's internal names ("BitRate_String", "Language", …).
//  • MediaFile — everything known about one open file: each output format,
//    whether it is loading, why it failed, and its checksum's progress.
//
//  Both are values. MediaStore keeps them in tabs and replaces them as
//  results arrive, matching by `id` (the file's session id) so a late result
//  never lands on a different file. Readable labels and values for fields
//  come from FieldFormat and EasyFields (MediaInfoUtilities); the one-glance
//  summary is MediaSummary.
//

import Foundation
import SwiftUI

// MARK: - Track

/// One track: its MediaInfo type ("General", "Video", "Audio", "Text",
/// "Menu", "Image"…), its index among tracks of that type, and its fields.
struct MediaTrack: Identifiable {
    let id = UUID()
    let type: String
    let streamIndex: Int
    var fields: [(key: String, value: String)]
    
    /// The SF Symbol shown beside the track's title.
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
    
    /// "Audio #2 · English · Commentary" — the card title.
    var displayTitle: String {
        if type == "General" { return "General" }
        if type == "Menu" { return streamIndex > 0 ? "Chapters #\(streamIndex + 1)" : "Chapters" }
        // The spelled-out name ("English") where MediaInfo provides one, not
        // the code ("en"). "zxx" (No linguistic content) and "und" say
        // nothing worth a place in the title.
        let code = fields.first(where: { $0.key == "Language" })?.value ?? ""
        let lang = ["zxx", "und"].contains(code.lowercased()) ? ""
        : (fields.first(where: { $0.key == "Language_String" })?.value ?? code)
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
    
    /// The track's length in seconds, read from MediaInfo's fixed
    /// HH:MM:SS.mmm form. The plain Duration field changed units between
    /// MediaInfo versions (milliseconds, then seconds); the clock form didn't.
    var seconds: Double? {
        guard let clock = value(for: "Duration_String3")?.trimmingCharacters(in: .whitespaces),
              !clock.isEmpty else { return nil }
        let parts = clock.split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }
}

// MARK: - MediaFile
//
// Each format's output starts as nil and stays nil until it arrives:
//   nil content, nil error      → not loaded yet (see `isLoading(_:)`)
//   nil content, non-nil error  → it was tried and failed
//   text                        → ready to display
//
// Equality is identity (`id`), so a file whose contents change is still the
// same file to SwiftUI.

struct MediaFile: Identifiable, Equatable {
    let id   = UUID()
    let url  : URL
    
    /// Written explicitly because `parsedTracks` below is private, which makes
    /// the synthesised memberwise initialiser private too — and both call
    /// sites construct a MediaFile from just a URL.
    init(url: URL) {
        self.url = url
    }
    
    // Parsed track data, from the JSON output.
    //
    // Stored separately from what callers read, because the checksum is
    // injected on the way out (see `tracks`). Writing it into the stored array
    // instead would lose it: a cached digest is applied the instant a file
    // opens, and the JSON analysis then replaces the whole array. Injecting on
    // read makes the order irrelevant.
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
    
    /// The failure that best represents "this file could not be analysed":
    /// the first format to land (the current view's), if it failed. Drives
    /// the error screen.
    var loadError: MediaInfoError? = nil
    
    // True until the first format lands; drives the "Analysing…" screen.
    var isLoading: Bool = true
    
    /// Where this file's SHA-256 has got to.
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
        error(for: mode.format)
    }

    // MARK: Per-format access
    //
    // The loader works in formats, not views, and five near-identical switches
    // scattered through it is how one of them ends up out of step. These are
    // the only place a format is mapped to its stored properties.

    func content(for format: MediaFormat) -> String? {
        switch format {
        case .json:    return rawJSON
        case .text:    return rawText
        case .rawText: return rawTextFull
        case .html:    return rawHTML
        case .xml:     return rawXML
        }
    }

    func error(for format: MediaFormat) -> MediaInfoError? {
        switch format {
        case .json:    return jsonError
        case .text:    return textError
        case .rawText: return rawTextError
        case .html:    return htmlError
        case .xml:     return xmlError
        }
    }

    /// True while a format is being fetched or is waiting its turn to be.
    func isLoading(_ format: MediaFormat) -> Bool {
        switch format {
        case .json:    return isLoadingJSON
        case .text:    return isLoadingText
        case .rawText: return isLoadingRawText
        case .html:    return isLoadingHTML
        case .xml:     return isLoadingXML
        }
    }

    /// Whether a view has something to draw. Easy View needs the parsed tracks,
    /// not just the JSON string they came from.
    func hasContent(for mode: ViewMode) -> Bool {
        mode == .easy ? !tracks.isEmpty : content(for: mode.format) != nil
    }

    mutating func setLoading(_ loading: Bool, for format: MediaFormat) {
        switch format {
        case .json:    isLoadingJSON    = loading
        case .text:    isLoadingText    = loading
        case .rawText: isLoadingRawText = loading
        case .html:    isLoadingHTML    = loading
        case .xml:     isLoadingXML     = loading
        }
    }

    mutating func setError(_ error: MediaInfoError?, for format: MediaFormat) {
        switch format {
        case .json:    jsonError    = error
        case .text:    textError    = error
        case .rawText: rawTextError = error
        case .html:    htmlError    = error
        case .xml:     xmlError     = error
        }
    }

    /// Store one finished fetch. `tracks` is only meaningful for JSON, and is
    /// parsed by the caller off the main thread.
    mutating func apply(
        _ result: Result<String, MediaInfoError>,
        tracks parsed: [MediaTrack],
        for format: MediaFormat
    ) {
        let value = result.value

        switch format {
        case .json:
            rawJSON = value
            tracks  = parsed
        case .text:    rawText     = value
        case .rawText: rawTextFull = value
        case .html:    rawHTML     = value
        case .xml:     rawXML      = value
        }

        setError(result.failure, for: format)
        setLoading(false, for: format)
    }
    
    /// The same file with its checksum left out of everything built from
    /// it — the injected track field, and the line exports append.
    func withoutChecksum() -> MediaFile {
        var copy = self
        copy.hashState = .notApplicable
        return copy
    }
    
    var generalTrack: MediaTrack?  { tracks.first(where: { $0.type == "General" }) }
    var videoTracks:  [MediaTrack] { tracks.filter { $0.type == "Video" } }
    var audioTracks:  [MediaTrack] { tracks.filter { $0.type == "Audio" } }
    var textTracks:   [MediaTrack] { tracks.filter { $0.type == "Text"  } }
}
