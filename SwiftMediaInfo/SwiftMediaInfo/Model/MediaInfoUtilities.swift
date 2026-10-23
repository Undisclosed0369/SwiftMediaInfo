//
//  MediaInfoUtilities.swift
//  SwiftMediaInfo
//
//  How MediaInfo's fields are chosen, named and compared — the one place
//  every view, search, copy and export agrees on:
//
//  • EasyFields — which fields Easy View shows for each track type, and
//    their values (with fallbacks for older MediaInfo spellings).
//  • FieldFormat — readable names for MediaInfo's keys ("OverallBitRate_String"
//    → "Overall Bit Rate"), value formatting, and the forgiving text matching
//    search uses ("bitrate" finds "Bit Rate").
//  • TextDiff — Compare Mode's line-by-line classification of the Text and
//    Raw Text reports.
//  • HDRDescription — one line for everything a track says about HDR.
//  • `trimmingTrailingWhitespace` — so copied and exported text ends where
//    its last line does.
//

import Foundation

// MARK: - Easy Field Keys

/// The curated subset of fields shown in Easy View for each track type.
/// Used by TrackCard, DiffEasyView, FilterableEasyView, and DiffTrackCard.
enum EasyFields {
    
    static func keys(for trackType: String) -> [String] {
        switch trackType {
        case "General":
            return [
                "FileName",
                "Format", "Format_Profile", "Format_Commercial_IfAny",
                "FileSize_String",
                "Duration_String3",
                "OverallBitRate_String", "FrameRate",
                "Encoded_Date", "Writing_Application", "Writing_Library",
                "Title", "Movie", "Performer", "Album", "Track"
            ]
        case "Video":
            return [
                "Format", "Format_Profile", "Format_Level", "Format_Commercial_IfAny",
                "StreamSize_String",
                "BitRate_String",
                "Duration_String3",
                "Width", "Height", "DisplayAspectRatio_String",
                "FrameRate_Mode_String", "FrameRate",
                "ColorSpace", "ChromaSubsampling", "BitDepth", "ScanType",
                "HDR_Format",
                "Encoded_Library", "Language_String"
            ]
        case "Audio":
            return [
                "Format", "Format_Profile", "Format_Commercial_IfAny",
                "StreamSize_String",
                "BitRate_String", "BitRate_Mode_String",
                "Channels_String",
                "ChannelPositions_String2",
                "SamplingRate",
                "BitDepth",
                "Compression_Mode", "Language_String", "Title", "Encoded_Library"
            ]
        case "Text":
            return [
                "Format", "Format_Profile",
                "StreamSize_String",
                "Language_String", "Title",
                "Forced", "Default"
            ]
        case "Image":
            return [
                "Format", "Format_Profile", "Format_Commercial_IfAny",
                "Width", "Height", "DisplayAspectRatio_String",
                "ColorSpace", "ChromaSubsampling", "BitDepth",
                "StreamSize_String",
                "Compression_Mode", "Encoded_Library"
            ]
        case "Menu":
            return ["Duration_String3", "Language_String"]
        default:
            return []
        }
    }
    
    /// Resolve the easy fields for a track, falling back to raw keys when _String variants are missing.
    static func resolve(for track: MediaTrack) -> [(key: String, value: String)] {
        // A Menu track is a chapter list. MediaInfo names each chapter by its
        // start time ("_00_02_09_379") alongside a dozen bookkeeping fields;
        // the chapters are the only part worth reading.
        if track.type == "Menu" {
            let chapters = track.fields.filter { isChapterKey($0.key) }
            if !chapters.isEmpty {
                return chapters.map { (key: $0.key, value: chapterTitle($0.value)) }
            }
        }
        
        let fieldKeys = keys(for: track.type)
        
        if fieldKeys.isEmpty {
            return Array(track.fields.prefix(20))
        }
        
        var result: [(key: String, value: String)] = []
        for key in fieldKeys {
            if let value = lookup(key, in: track) {
                result.append((key: key, value: polish(key: key, value: value, track: track)))
            }
        }
        
        return result.isEmpty ? Array(track.fields.prefix(20)) : result
    }
    
    /// "_00_02_09_379" — a chapter's start time, as MediaInfo's JSON names it.
    static func isChapterKey(_ key: String) -> Bool {
        key.range(of: #"^_\d{2}_\d{2}_\d{2}_\d{3}$"#, options: .regularExpression) != nil
    }
    
    /// "en:Ground Zero" → "Ground Zero". The language prefix repeats the
    /// track's own language on every line.
    static func chapterTitle(_ value: String) -> String {
        guard let range = value.range(of: #"^[a-z]{2,3}(-[A-Za-z]{2,4})?:"#, options: .regularExpression) else { return value }
        let title = value[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? value : title
    }
    
    /// Older MediaInfo releases spell some keys differently. "Channel(s)"
    /// became "Channels", and the JSON key followed — so a file analysed by
    /// either version still finds its channel count.
    private static let aliases: [String: [String]] = [
        "Channels_String": ["Channel_s__String"],
        "Channels": ["Channel_s_"]
    ]
    
    /// A key's value, trying its older spellings and then its raw, unformatted
    /// counterpart (formatted here) when the `_String` variant is missing.
    private static func lookup(_ key: String, in track: MediaTrack) -> String? {
        for candidate in [key] + (aliases[key] ?? []) {
            if let value = track.value(for: candidate) { return value }
        }
        guard key.contains("_String") else { return nil }
        
        let rawKey = FieldFormat.stripStringSuffix(key)
        for candidate in [rawKey] + (aliases[rawKey] ?? []) {
            if let raw = track.value(for: candidate) {
                return FieldFormat.formatRaw(key: rawKey, value: raw)
            }
        }
        return nil
    }
    
    /// Display tweaks applied everywhere a curated field is shown, searched,
    /// compared or copied, so all of them agree on the same text.
    private static func polish(key: String, value: String, track: MediaTrack) -> String {
        if key == "SamplingRate", track.type == "Audio" {
            return FieldFormat.kilohertz(value)
        }
        // One row for all of it — layers, profile and compatibility — rather
        // than a Format row and a Compatibility row that don't say which
        // compatibility goes with which layer.
        if key == "HDR_Format", track.type == "Video" {
            return HDRDescription.full(for: track) ?? value
        }
        return value
    }
}

// MARK: - Trailing whitespace

extension String {
    /// The text without the blank lines and spaces MediaInfo leaves at the
    /// end of its reports. Copied, exported or shared text should end where
    /// its last line does — trailing blank lines turn up as stray empty lines
    /// wherever it is pasted.
    nonisolated var trimmingTrailingWhitespace: String {
        guard let last = lastIndex(where: { !$0.isWhitespace }) else { return "" }
        return String(self[...last])
    }
}

// MARK: - Field Formatting

enum FieldFormat {
    
    /// Convert a raw JSON key into the readable name shown and copied.
    ///   "Duration_String3"      → "Duration"
    ///   "OverallBitRate_String" → "Overall Bit Rate"
    ///   "HDR_Format"            → "HDR Format"
    ///   "colour_primaries"      → "Colour Primaries"
    ///
    /// MediaInfo's own names never leave the app through a copy: everything
    /// copied from Easy View goes through here first.
    static func friendlyLabel(_ key: String) -> String {
        // Chapter start times: "_00_02_09_379" → "00:02:09.379".
        if EasyFields.isChapterKey(key) {
            let parts = key.dropFirst().split(separator: "_")
            return "\(parts[0]):\(parts[1]):\(parts[2]).\(parts[3])"
        }
        let stripped = stripStringSuffix(key)
        if let override = labelOverrides[stripped] { return override }
        return humanize(stripped)
    }
    
    /// Names the generic splitting gets wrong or makes awkward.
    private static let labelOverrides: [String: String] = [
        "FileName": "File Name",
        "Channel_s_": "Channels",
        "Format_Commercial_IfAny": "Commercial Name",
        "Format_Commercial": "Commercial Name",
        "HDR_Format_Compatibility": "HDR Compatibility",
        "DisplayAspectRatio": "Display Aspect Ratio",
        "SHA256": "SHA-256",
        "Movie": "Movie Name",
        "Track": "Track Name"
    ]
    
    /// Splits on underscores and case changes, keeping acronyms whole:
    /// "MaxCLL" → "Max CLL", "UniqueID" → "Unique ID".
    static func humanize(_ key: String) -> String {
        let chars = Array(key)
        var words: [String] = []
        var current = ""
        
        func flush() {
            if !current.isEmpty { words.append(current) }
            current = ""
        }
        
        for (i, char) in chars.enumerated() {
            if char == "_" || char == " " || char == "/" {
                flush()
                continue
            }
            if char.isUppercase, !current.isEmpty {
                let previous = chars[i - 1]
                let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
                let startsWord = previous.isLowercase
                || previous.isNumber
                || (previous.isUppercase && (next?.isLowercase ?? false))
                if startsWord { flush() }
            }
            current.append(char)
        }
        flush()
        
        return words.map { word in
            guard let first = word.first, first.isLowercase else { return word }
            return first.uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
    
    /// "48000" or "48.0 kHz" → "48 kHz"; "44100" → "44.1 kHz".
    static func kilohertz(_ raw: String) -> String {
        let number = raw.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ").first ?? raw
        guard var value = Double(number) else { return raw }
        if !raw.lowercased().contains("khz") { value /= 1000 }
        return value.truncatingRemainder(dividingBy: 1) == 0
        ? "\(Int(value)) kHz"
        : String(format: "%.1f kHz", value)
    }
    
    /// Strip `_String`, `_String3`, etc. from a key.
    ///   "Duration_String3" → "Duration"
    ///   "BitRate_String" → "BitRate"
    static func stripStringSuffix(_ key: String) -> String {
        guard let underRange = key.range(of: "_String") else { return key }
        var end = underRange.upperBound
        while end < key.endIndex && key[end].isNumber {
            end = key.index(after: end)
        }
        return String(key[key.startIndex..<underRange.lowerBound])
    }
    
    /// Format a raw numeric value when the _String variant is missing.
    static func formatRaw(key: String, value: String) -> String {
        switch key {
            
        case "FileSize", "StreamSize":
            if let bytes = Int64(value) {
                return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            }
            
        case "BitRate", "OverallBitRate":
            if let bps = Double(value) {
                if bps >= 1_000_000 { return String(format: "%.2f Mb/s", bps / 1_000_000) }
                if bps >= 1_000     { return String(format: "%.0f kb/s", bps / 1_000) }
                return "\(Int(bps)) b/s"
            }
            
        case "Duration":
            if let ms = Double(value) {
                let totalMs  = Int(ms)
                let totalSec = totalMs / 1000
                let h  = totalSec / 3600
                let m  = (totalSec % 3600) / 60
                let s  = totalSec % 60
                let remainder = totalMs % 1000
                if h > 0 { return String(format: "%d h %02d min %02d s %d ms", h, m, s, remainder) }
                if m > 0 { return String(format: "%d min %02d s", m, s) }
                if s > 0 { return String(format: "%d s %d ms", s, remainder) }
                return "\(remainder) ms"
            }
            
        case "FrameRate":
            if let fps = Double(value) {
                return String(format: "%.3f", fps)
            }
            
        case "Channels", "Channel_s_":
            if let count = Int(value) {
                return count == 1 ? "1 channel" : "\(count) channels"
            }
            
        case "SamplingRate":
            if let hz = Double(value) {
                if hz >= 1_000 { return String(format: "%.1f kHz", hz / 1_000) }
                return "\(Int(hz)) Hz"
            }
            
        default:
            break
        }
        
        return value
    }
    
    /// Count text occurrences of a query within a string (case-insensitive).
    /// Also tries space-normalized matching so "bitrate" finds "Bit Rate".
    static func occurrences(of query: String, in text: String) -> Int {
        let q = query.lowercased()
        let lower = text.lowercased()
        
        // Try exact match first
        let exact = countSubstring(q, in: lower)
        if exact > 0 { return exact }
        
        // Try normalized match (strip spaces from both)
        let qNorm = q.replacingOccurrences(of: " ", with: "")
        let tNorm = lower.replacingOccurrences(of: " ", with: "")
        return countSubstring(qNorm, in: tNorm)
    }
    
    /// Check if text contains query (case-insensitive, space-normalized fallback).
    static func fuzzyContains(query: String, in text: String) -> Bool {
        let q = query.lowercased()
        let lower = text.lowercased()
        if lower.contains(q) { return true }
        
        // Normalized fallback
        let qNorm = q.replacingOccurrences(of: " ", with: "")
        let tNorm = lower.replacingOccurrences(of: " ", with: "")
        return tNorm.contains(qNorm)
    }
    
    /// Find all ranges of query in text for highlighting (case-insensitive, space-normalized fallback).
    /// Returns ranges in the ORIGINAL text (not normalized).
    static func highlightRanges(of query: String, in text: String) -> [Range<String.Index>] {
        let q = query.lowercased()
        let lower = text.lowercased()
        
        // Try exact match first
        let exact = findRanges(of: q, in: lower)
        if !exact.isEmpty { return exact }
        
        // For normalized matching, we need to map back to original positions.
        // Build a mapping from normalized index to original index.
        let qNorm = q.replacingOccurrences(of: " ", with: "")
        guard !qNorm.isEmpty else { return [] }
        
        // Build index map: normalizedIndex -> originalIndex
        var indexMap: [String.Index] = []
        for idx in lower.indices {
            if lower[idx] != " " {
                indexMap.append(idx)
            }
        }
        
        let normalized = lower.replacingOccurrences(of: " ", with: "")
        var ranges: [Range<String.Index>] = []
        var searchStart = normalized.startIndex
        
        while let range = normalized.range(of: qNorm, range: searchStart..<normalized.endIndex) {
            let startOffset = normalized.distance(from: normalized.startIndex, to: range.lowerBound)
            let endOffset   = normalized.distance(from: normalized.startIndex, to: range.upperBound) - 1
            
            if startOffset < indexMap.count && endOffset < indexMap.count {
                let origStart = indexMap[startOffset]
                let origEnd   = text.index(after: indexMap[endOffset])
                ranges.append(origStart..<origEnd)
            }
            searchStart = range.upperBound
        }
        
        return ranges
    }
    
    private static func countSubstring(_ query: String, in text: String) -> Int {
        var count = 0
        var searchStart = text.startIndex
        while let range = text.range(of: query, range: searchStart..<text.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }
    
    private static func findRanges(of query: String, in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while let range = text.range(of: query, range: searchStart..<text.endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }
}

// MARK: - Text diff
//
// Classifies each line of a Text or Raw Text report against the other file's
// report (DiffRawTextView draws the result).
//
// WHY NOT MATCH LINES BY TEXT OR POSITION
//
//   • By position: one extra field near the top shifts every line below it,
//     so fields that are merely different look as if they exist in one file
//     only.
//   • By text anywhere: "Format : AAC" in File A's Audio section would match
//     the same line in File B's Audio #2, hiding real differences.
//
// HOW IT MATCHES
//
// Both reports are read as sections (the header lines — "General", "Video",
// "Audio #2") holding "Field : Value" lines. A line is matched to the same
// field in the same section of the other report, counting repeats, since
// mediainfo prints some fields twice in one section ("Frame rate" as a number
// and as text). Then:
//
//   • field missing from that section on the other side → only in this file
//   • present with a different value                     → modified
//   • present with the same value                        → unchanged
//
// A section header is "only in this file" when the other report has no such
// section at all ("Audio" and "Audio #1" count as the same section). Position
// in the report no longer matters.

enum TextDiff {
    
    enum LineKind: Equatable {
        case unchanged
        case modified
        case onlyInThis
    }
    
    /// One kind per line of `lines`, in order.
    static func classify(_ lines: [String], against otherLines: [String]) -> [LineKind] {
        let other = index(otherLines)
        var section = ""
        var seen: [String: Int] = [:]
        
        return lines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return .unchanged }
            
            guard let (key, value) = split(line) else {
                // A section header.
                section = canonicalSection(trimmed)
                seen = [:]
                return other.sections.contains(section) ? .unchanged : .onlyInThis
            }
            
            let occurrence = seen[key, default: 0]
            seen[key] = occurrence + 1
            
            guard let otherValue = other.values[Field(section: section, key: key, occurrence: occurrence)] else {
                return .onlyInThis
            }
            return otherValue == value ? .unchanged : .modified
        }
    }
    
    // MARK: Parsing
    
    private struct Field: Hashable {
        let section: String
        let key: String
        let occurrence: Int
    }
    
    private struct Index {
        var sections: Set<String> = []
        var values: [Field: String] = [:]
    }
    
    private static func index(_ lines: [String]) -> Index {
        var result = Index()
        var section = ""
        var seen: [String: Int] = [:]
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            if let (key, value) = split(line) {
                let occurrence = seen[key, default: 0]
                seen[key] = occurrence + 1
                result.values[Field(section: section, key: key, occurrence: occurrence)] = value
            } else {
                section = canonicalSection(trimmed)
                seen = [:]
                result.sections.insert(section)
            }
        }
        return result
    }
    
    /// mediainfo numbers a stream type only when there is more than one of
    /// it: a file with one audio track says "Audio", a file with two says
    /// "Audio #1" and "Audio #2". The first track is the same track either
    /// way, so both spellings are read as "Audio #1".
    private static func canonicalSection(_ header: String) -> String {
        header.contains(" #") ? header : header + " #1"
    }
    
    /// "Field name      : value" → ("Field name", "value"). Split at the first
    /// " : " rather than the first colon, because values contain colons —
    /// durations, timecodes, paths.
    private static func split(_ line: String) -> (key: String, value: String)? {
        guard let range = line.range(of: " : ") else { return nil }
        let key = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        let value = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        return (key, value)
    }
}

// MARK: - HDR description

/// Everything MediaInfo knows about a video track's HDR, in one line.
///
/// MediaInfo spreads it across several fields, each with one entry per HDR
/// layer separated by " / " — a Dolby Vision file with an HDR10+ layer reports
/// `HDR_Format` "Dolby Vision / SMPTE ST 2094 App 4" and
/// `HDR_Format_Compatibility` "HDR10 / HDR10+ Profile B". Read separately the
/// two rows don't say which compatibility belongs to which layer. Combined:
///
///     Dolby Vision Profile 8.1 / HDR10+ Profile B, HDR10 Compatible
///     SMPTE ST 2086, HDR10 Compatible
enum HDRDescription {
    
    /// Nil for SDR video.
    static func full(for track: MediaTrack) -> String? {
        let layers = parts(track.value(for: "HDR_Format"))
        guard !layers.isEmpty else { return nil }
        
        let compatibility = parts(track.value(for: "HDR_Format_Compatibility"))
        let detail = parts(track.value(for: "HDR_Format_String"))
        
        var names: [String] = []
        var compatibleWith: [String] = []
        
        for (index, layer) in layers.enumerated() {
            let compatible = compatibility.indices.contains(index) ? compatibility[index] : ""
            
            if layer.contains("2094 App 4") {
                // An HDR10+ layer: its "compatibility" is really its name and
                // profile ("HDR10+ Profile B"), which says more than the
                // SMPTE number.
                names.append(compatible.hasPrefix("HDR10+") ? compatible : "HDR10+ (SMPTE ST 2094 App 4)")
                continue
            }
            
            var name = layer
            if layer.contains("Dolby Vision"),
               index < detail.count,
               let profile = detail[index].range(of: #"Profile \d+(\.\d+)?"#, options: .regularExpression) {
                name += " " + detail[index][profile]
            }
            names.append(name)
            
            if !compatible.isEmpty, !compatibleWith.contains(compatible) {
                compatibleWith.append(compatible)
            }
        }
        
        return ([names.joined(separator: " / ")] + compatibleWith.map { "\($0) Compatible" })
            .joined(separator: ", ")
    }
    
    /// The everyday name for a chip: "Dolby Vision / HDR10+", "HDR10", "HLG".
    static func short(for track: MediaTrack) -> String? {
        let layers = parts(track.value(for: "HDR_Format"))
        if layers.isEmpty {
            let transfer = track.value(for: "transfer_characteristics") ?? ""
            if transfer.contains("HLG") { return "HLG" }
            if transfer.contains("PQ") { return "PQ" }
            return nil
        }
        var names: [String] = []
        for layer in layers {
            let name: String
            if layer.contains("Dolby Vision") { name = "Dolby Vision" }
            else if layer.contains("2094 App 4") { name = "HDR10+" }
            else if layer.contains("2086") { name = "HDR10" }
            else if layer.contains("HLG") { name = "HLG" }
            else { name = layer }
            if !names.contains(name) { names.append(name) }
        }
        return names.joined(separator: " / ")
    }
    
    private static func parts(_ value: String?) -> [String] {
        guard let value, !value.isEmpty else { return [] }
        return value.components(separatedBy: " / ").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
