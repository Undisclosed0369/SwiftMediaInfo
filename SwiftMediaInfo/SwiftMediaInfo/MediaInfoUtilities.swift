//
//  MediaInfoUtilities.swift
//  SwiftMediaInfo
//
//  Single source of truth for field formatting, easy field keys,
//  and other helpers used across EasyView, DiffEasyView, FilterableEasyView, etc.
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
                "HDR_Format", "HDR_Format_Compatibility",
                "Encoded_Library", "Language"
            ]
        case "Audio":
            return [
                "Format", "Format_Profile", "Format_Commercial_IfAny",
                "StreamSize_String",
                "BitRate_String", "BitRate_Mode_String",
                "Channel_s__String",
                "ChannelPositions_String2",
                "SamplingRate",
                "BitDepth",
                "Compression_Mode", "Language", "Title", "Encoded_Library"
            ]
        case "Text":
            return [
                "Format", "Format_Profile",
                "StreamSize_String",
                "Language", "Title",
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
            return ["Duration_String3", "Language"]
        default:
            return []
        }
    }
    
    /// Resolve the easy fields for a track, falling back to raw keys when _String variants are missing.
    static func resolve(for track: MediaTrack) -> [(key: String, value: String)] {
        let fieldKeys = keys(for: track.type)
        
        if fieldKeys.isEmpty {
            return Array(track.fields.prefix(20))
        }
        
        var result: [(key: String, value: String)] = []
        for key in fieldKeys {
            if let f = track.fields.first(where: { $0.key == key }) {
                result.append(f)
            } else if key.contains("_String") {
                let rawKey = FieldFormat.stripStringSuffix(key)
                if let raw = track.fields.first(where: { $0.key == rawKey }) {
                    result.append((key: key, value: FieldFormat.formatRaw(key: rawKey, value: raw.value)))
                }
            }
        }
        
        return result.isEmpty ? Array(track.fields.prefix(20)) : result
    }
}

// MARK: - Field Formatting

enum FieldFormat {
    
    /// Convert a raw JSON key into a human-readable label.
    ///   "Duration_String3" → "Duration"
    ///   "Channel_s__String" → "Channels"
    ///   "OverallBitRate" → "Overall Bit Rate"
    static func friendlyLabel(_ key: String) -> String {
        if key == "FileName"          { return "File Name" }
        if key == "SamplingRate"      { return "Sampling Rate (kHz)" }
        if key == "Channel_s__String" { return "Channels" }
        
        let stripped = stripStringSuffix(key)
        var result = ""
        for char in stripped {
            if char == "_"                              { result += " " }
            else if char.isUppercase && !result.isEmpty { result += " \(char)" }
            else                                        { result.append(char) }
        }
        return result
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

// MARK: - Diff line comparison helper

enum DiffHelper {
    /// Check if two lines share the same "key" (text before first colon or tab).
    static func sameKey(_ a: String, _ b: String) -> Bool {
        func extractKey(_ s: String) -> String {
            for sep: Character in [":", "\t"] {
                if let idx = s.firstIndex(of: sep) {
                    return String(s[s.startIndex..<idx]).trimmingCharacters(in: .whitespaces)
                }
            }
            return ""
        }
        let ka = extractKey(a)
        let kb = extractKey(b)
        return !ka.isEmpty && ka == kb
    }
}
