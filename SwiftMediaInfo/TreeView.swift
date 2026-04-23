//
//  TreeView.swift
//  SwiftMediaInfo
//
//  Created by Undisclosed on 23/4/26.
//


//
//  TreeView.swift
//  MediaInfoMac
//

import SwiftUI

struct TreeView: View {
    let file: MediaFile
    @EnvironmentObject var store: MediaStore
    @State private var expandedTracks: Set<UUID> = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(file.tracks) { track in
                    TreeTrackSection(
                        track: track,
                        isExpanded: expandedTracks.contains(track.id)
                    ) {
                        if expandedTracks.contains(track.id) {
                            expandedTracks.remove(track.id)
                        } else {
                            expandedTracks.insert(track.id)
                        }
                    }
                }
            }
            .padding(12)
        }
        .onAppear {
            expandedTracks = Set(file.tracks.map { $0.id })
        }
    }
}

struct TreeTrackSection: View {
    let track: MediaTrack
    let isExpanded: Bool
    let toggle: () -> Void
    @EnvironmentObject var store: MediaStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    Image(systemName: track.typeIcon)
                        .font(.system(size: 12))
                        .foregroundColor(trackColor)
                    Text(track.displayTitle)
                        .font(.system(size: CGFloat(store.fontSize), weight: .semibold))
                    Spacer()
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color(NSColor.selectedContentBackgroundColor).opacity(0.12))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(Array(track.fields.enumerated()), id: \.offset) { idx, field in
                    HStack(alignment: .top, spacing: 0) {
                        Rectangle()
                            .fill(Color(NSColor.separatorColor))
                            .frame(width: 1)
                            .padding(.leading, 15)
                            .padding(.trailing, 8)
                        Text(field.key)
                            .font(.system(size: CGFloat(store.fontSize), design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(minWidth: 220, alignment: .leading)
                            .lineLimit(1)
                        Text(" : ")
                            .font(.system(size: CGFloat(store.fontSize), design: .monospaced))
                            .foregroundColor(Color(NSColor.separatorColor))
                        Text(field.value)
                            .font(.system(size: CGFloat(store.fontSize), design: .monospaced))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .background(
                        idx % 2 == 0
                            ? Color.clear
                            : Color(NSColor.alternatingContentBackgroundColors[1]).opacity(0.5)
                    )
                }
            }
        }
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
}