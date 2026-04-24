//
//  EasyView.swift
//  SwiftMediaInfo
//
//  Created by Undisclosed on 23/4/26.
//


//
//  EasyView.swift
//  MediaInfoMac
//

import SwiftUI

struct EasyView: View {
    let file: MediaFile
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(file.tracks) { track in
                    TrackCard(track: track)
                }
            }
            .padding(20)
        }
    }
}

struct TrackCard: View {
    let track: MediaTrack
    @EnvironmentObject var store: MediaStore
    @State private var isExpanded = true
    
    private var easyFields: [(key: String, value: String)] {
        let keys = easyFieldKeys(for: track.type)
        if keys.isEmpty { return Array(track.fields.prefix(20)) }
        var result: [(key: String, value: String)] = []
        for key in keys {
            if let f = track.fields.first(where: { $0.key == key }) {
                result.append(f)
            }
        }
        return result.isEmpty ? Array(track.fields.prefix(20)) : result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
    
    private var trackColor: Color {
        switch track.type {
        case "General": return .gray
        case "Video":   return .blue
        case "Audio":   return .purple
        case "Text":    return .green
        case "Menu":    return .orange
        default:        return .secondary
        }
    }
    
    private func easyFieldKeys(for type: String) -> [String] {
        switch type {
        case "General":
            return ["Format","Format_Profile","Format_Commercial_IfAny","FileSize/String",
                    "Duration/String","OverallBitRate/String","FrameRate",
                    "Encoded_Date","Writing_Application","Writing_Library",
                    "Title","Movie","Performer","Album","Track"]
        case "Video":
            return ["Format","Format_Profile","Format_Level","Format_Commercial_IfAny",
                    "BitRate/String","Width","Height","DisplayAspectRatio/String",
                    "FrameRate_Mode/String","FrameRate","ColorSpace",
                    "ChromaSubsampling","BitDepth","ScanType",
                    "HDR_Format","HDR_Format_Compatibility",
                    "Encoded_Library","Language"]
        case "Audio":
            return ["Format","Format_Profile","Format_Commercial_IfAny",
                    "BitRate/String","BitRate_Mode/String",
                    "Channel(s)/String","ChannelPositions/String2",
                    "SamplingRate/String","BitDepth",
                    "Compression_Mode","Language","Title","Encoded_Library"]
        case "Text":
            return ["Format","Format_Profile","Language","Title",
                    "Forced","Default","Duration/String"]
        case "Menu":
            return ["Duration/String","Language"]
        default:
            return []
        }
    }
    
    private func friendlyLabel(_ key: String) -> String {
        var k = key
        for suffix in ["/String3","/String2","/String"] {
            k = k.replacingOccurrences(of: suffix, with: "")
        }
        var result = ""
        for char in k {
            if char == "_" { result += " " }
            else if char.isUppercase && !result.isEmpty { result += " \(char)" }
            else { result.append(char) }
        }
        return result
    }
}

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
