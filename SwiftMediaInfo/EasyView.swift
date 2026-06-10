//
//  EasyView.swift
//  SwiftMediaInfo
//

import SwiftUI

struct EasyView: View {
    let file: MediaFile
    
    /// Inject a guaranteed "FileName" field at the top of the General track.
    private var tracksWithInjectedFields: [MediaTrack] {
        file.tracks.map { track in
            guard track.type == "General" else { return track }
            var t = track
            if !t.fields.contains(where: { $0.key == "FileName" }) {
                t.fields.insert((key: "FileName", value: file.url.lastPathComponent), at: 0)
            }
            return t
        }
    }
    
    var body: some View {
        if file.tracks.isEmpty {
            let isDirectory = (try? file.url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            VStack(spacing: 16) {
                Image(systemName: isDirectory ? "folder.badge.questionmark" : "exclamationmark.triangle")
                    .font(.system(size: 52))
                    .foregroundColor(.secondary.opacity(0.4))
                Text(isDirectory ? "Easy View doesn't support folders"
                     : "No media tracks found")
                .font(.title3)
                .foregroundColor(.secondary)
                Text(isDirectory
                     ? "Switch to the Text or JSON tab to see raw mediainfo output,\nor open a media file instead of a folder."
                     : "MediaInfo returned no track data for this file.\nTry the Text tab — it may show raw output, or MediaInfo\nmight not support this format.")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(tracksWithInjectedFields) { track in
                        TrackCard(track: track)
                    }
                }
                .padding(20)
            }
        }
    }
}

// MARK: - TrackCard

struct TrackCard: View {
    let track: MediaTrack
    @EnvironmentObject var store: MediaStore
    @State private var isExpanded = true
    
    // MARK: Field assembly
    //
    // MediaInfo JSON (--Full) uses UNDERSCORE keys like:
    //   Duration_String3, FileSize_String, BitRate_String, etc.
    //
    // The old code used SLASH notation (Duration/String3) which is only valid
    // in mediainfo's custom TEXT template syntax, NOT in JSON output.
    // That's why duration was showing the raw millisecond fallback incorrectly.
    //
    // This version looks up the correct underscore-based JSON keys directly.
    // The Level 2 fallback (strip suffix → use raw key) still works for any
    // key ending in _String[N] that happens to be missing.
    
    private var easyFields: [(key: String, value: String)] {
        let keys = easyFieldKeys(for: track.type)
        
        let sourceFields: [(key: String, value: String)]
        if keys.isEmpty {
            sourceFields = Array(track.fields.prefix(20))
        } else {
            var result: [(key: String, value: String)] = []
            for key in keys {
                if let f = track.fields.first(where: { $0.key == key }) {
                    // Level 1 — exact key found in JSON fields
                    result.append(f)
                } else if key.contains("_String") {
                    // Level 2 — strip the _String[N] suffix and format the raw value ourselves
                    let rawKey = stripStringSuffix(key)
                    if let raw = track.fields.first(where: { $0.key == rawKey }) {
                        result.append((key: key, value: formatRawField(key: rawKey, value: raw.value)))
                    }
                }
            }
            sourceFields = result.isEmpty ? Array(track.fields.prefix(20)) : result
        }
        
        // Post-process Hz → kHz for Audio SamplingRate
        if track.type == "Audio" {
            return sourceFields.map { f in
                f.key == "SamplingRate" ? (key: f.key, value: hzToKHz(f.value)) : f
            }
        }
        return sourceFields
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Collapsible header ────
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: track.typeIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(trackColor)
                        .frame(width: 20)
                    Text(track.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(trackColor.opacity(0.08))
            }
            .buttonStyle(.plain)
            
            // ── Field grid ────
            if isExpanded {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 160), spacing: 0),
                        GridItem(.flexible(minimum: 200), spacing: 0)
                    ],
                    alignment: .leading,
                    spacing: 0
                ) {
                    ForEach(Array(easyFields.enumerated()), id: \.offset) { idx, field in
                        FieldCell(
                            key: friendlyLabel(field.key),
                            value: field.value,
                            rowIndex: idx / 2
                        )
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }
    
    // MARK: - Track colour
    
    private var trackColor: Color {
        switch track.type {
        case "General": return .gray
        case "Video":   return .blue
        case "Audio":   return .purple
        case "Text":    return .green
        case "Image":   return .teal
        case "Menu":    return .orange
        default:        return .secondary
        }
    }
    
    // MARK: - Field key lists per track type
    //
    // ALL keys here use the underscore convention that mediainfo JSON actually produces.
    // e.g. "Duration_String3" not "Duration/String3"
    //      "FileSize_String"  not "FileSize/String"
    //      "BitRate_String"   not "BitRate/String"
    
    private func easyFieldKeys(for type: String) -> [String] {
        switch type {
        case "General":
            return [
                "FileName",
                "Format", "Format_Profile", "Format_Commercial_IfAny",
                "FileSize_String",
                "Duration_String3",          // e.g. "1 h 52 min 7 s 488 ms"
                "OverallBitRate_String", "FrameRate",
                "Encoded_Date", "Writing_Application", "Writing_Library",
                "Title", "Movie", "Performer", "Album", "Track"
            ]
            
        case "Video":
            return [
                "Format", "Format_Profile", "Format_Level", "Format_Commercial_IfAny",
                "StreamSize_String",
                "BitRate_String",
                "Duration_String3",          // e.g. "1 h 52 min 7 s 440 ms"
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
                "Channel_s__String",         // MediaInfo JSON key for "Channel(s)/String"
                "ChannelPositions_String2",
                "SamplingRate",
                "BitDepth",
                "Compression_Mode", "Language", "Title", "Encoded_Library"
            ]
            
        case "Text":
            // No duration for subtitle tracks
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
    
    // MARK: - Strip _String[N] suffix helper
    
    /// Strips the `_String` portion (plus any trailing digits) from a key.
    /// e.g. "Duration_String3" → "Duration", "BitRate_String" → "BitRate"
    private func stripStringSuffix(_ key: String) -> String {
        guard let underRange = key.range(of: "_String") else { return key }
        var end = underRange.upperBound
        while end < key.endIndex && key[end].isNumber {
            end = key.index(after: end)
        }
        return String(key[key.startIndex..<underRange.lowerBound])
    }
    
    // MARK: - Raw field formatter (fallback when _String variant is missing)
    
    private func formatRawField(key: String, value: String) -> String {
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
            // MediaInfo stores Duration as milliseconds (may have decimal)
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
            
        case "DisplayAspectRatio":
            if let r = Double(value) {
                if abs(r - 16.0 / 9.0) < 0.01  { return "16:9" }
                if abs(r - 4.0  / 3.0) < 0.01  { return "4:3"  }
                if abs(r - 21.0 / 9.0) < 0.01  { return "21:9" }
                return String(format: "%.3f", r)
            }
            
        default:
            break
        }
        return value
    }
    
    // MARK: - Hz → kHz
    
    private func hzToKHz(_ raw: String) -> String {
        let digits = raw.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ").first ?? raw
        if let hz = Double(digits) {
            let khz = hz / 1000.0
            return khz.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(khz)) kHz"
            : String(format: "%.1f kHz", khz)
        }
        return raw
    }
    
    // MARK: - Friendly label
    
    private func friendlyLabel(_ key: String) -> String {
        if key == "FileName"          { return "File Name" }
        if key == "SamplingRate"      { return "Sampling Rate (kHz)" }
        if key == "Channel_s__String" { return "Channels" }
        
        // Strip _String + any trailing digits
        let k = stripStringSuffix(key)
        
        // Convert CamelCase + underscores to spaced words
        var result = ""
        for char in k {
            if char == "_"                              { result += " " }
            else if char.isUppercase && !result.isEmpty { result += " \(char)" }
            else                                        { result.append(char) }
        }
        return result
    }
}

// MARK: - FieldCell

struct FieldCell: View {
    let key: String
    let value: String
    let rowIndex: Int
    @EnvironmentObject var store: MediaStore
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(key)
                .font(.system(size: CGFloat(store.fontSize), weight: .medium))
                .foregroundColor(.secondary)
                .frame(minWidth: 110, alignment: .leading)
                .lineLimit(2)
            Text(value)
                .font(.system(size: CGFloat(store.fontSize)))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(
            rowIndex % 2 == 0
            ? Color(NSColor.controlBackgroundColor)
            : Color(NSColor.alternatingContentBackgroundColors[1])
        )
    }
}
