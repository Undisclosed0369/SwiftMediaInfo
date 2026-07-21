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
    var highlightQuery: String = ""
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
        var fields = EasyFields.resolve(for: track)
        
        // Post-process Hz → kHz for Audio SamplingRate
        if track.type == "Audio" {
            fields = fields.map { f in
                f.key == "SamplingRate" ? (key: f.key, value: hzToKHz(f.value)) : f
            }
        }
        return fields
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
                            key: FieldFormat.friendlyLabel(field.key),
                            value: field.value,
                            rowIndex: idx / 2,
                            highlightQuery: highlightQuery
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
}

// MARK: - FieldCell

struct FieldCell: View {
    let key: String
    let value: String
    let rowIndex: Int
    var highlightQuery: String = ""
    var diffState: DiffState = .unchanged
    @EnvironmentObject var store: MediaStore
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            highlightedText(key, isKey: true)
                .font(.system(size: CGFloat(store.fontSize), weight: .medium))
                .foregroundColor(diffState == .unchanged ? .secondary : diffForeground)
                .frame(minWidth: 110, alignment: .leading)
                .lineLimit(2)
            highlightedText(value, isKey: false)
                .font(.system(size: CGFloat(store.fontSize)))
                .foregroundColor(diffState == .unchanged ? .primary : diffForeground)
                .textSelection(.enabled)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(diffBackground ?? alternatingBackground)
    }
    
    // MARK: - Search highlighting
    
    @ViewBuilder
    private func highlightedText(_ text: String, isKey: Bool) -> some View {
        if highlightQuery.isEmpty {
            Text(text)
        } else {
            Text(buildHighlightedAttributedString(text))
        }
    }
    
    private func buildHighlightedAttributedString(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        let ranges = FieldFormat.highlightRanges(of: highlightQuery, in: text)
        
        for range in ranges {
            if let attrRange = Range(range, in: result) {
                result[attrRange].backgroundColor = Color.brandGreen.opacity(0.35)
            }
        }
        
        return result
    }
    
    // MARK: - Diff colours
    
    private var alternatingBackground: Color {
        rowIndex % 2 == 0
        ? Color(NSColor.controlBackgroundColor)
        : Color(NSColor.alternatingContentBackgroundColors[1])
    }
    
    private var diffBackground: Color? {
        switch diffState {
        case .unchanged: return nil
        case .added:     return Color.green.opacity(0.08)
        case .removed:   return Color.red.opacity(0.08)
        case .modified:  return Color.orange.opacity(0.08)
        case .onlyInA:   return Color.brandBlue.opacity(0.06)
        case .onlyInB:   return Color.brandPink.opacity(0.06)
        }
    }
    
    private var diffForeground: Color {
        switch diffState {
        case .unchanged: return .primary
        case .added:     return Color(red: 0.15, green: 0.68, blue: 0.38)
        case .removed:   return Color(red: 0.85, green: 0.25, blue: 0.25)
        case .modified:  return Color(red: 0.90, green: 0.58, blue: 0.15)
        case .onlyInA:   return .brandBlue
        case .onlyInB:   return .brandPink
        }
    }
}

// MARK: - Diff state

enum DiffState {
    case unchanged, added, removed, modified, onlyInA, onlyInB
}
