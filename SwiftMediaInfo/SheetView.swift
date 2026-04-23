//
//  SheetView.swift
//  SwiftMediaInfo
//
//  Created by Undisclosed on 23/4/26.
//


//
//  SheetView.swift
//  MediaInfoMac
//

import SwiftUI

struct SheetView: View {
    @EnvironmentObject var store: MediaStore

    private let columns: [(label: String, keyPath: (MediaFile) -> String)] = [
        ("File Name",        { $0.fileName }),
        ("Format",           { $0.generalTrack?.fields.first(where: { $0.key == "Format" })?.value ?? "" }),
        ("Duration",         { $0.generalTrack?.fields.first(where: { $0.key == "Duration/String" })?.value ?? "" }),
        ("File Size",        { $0.fileSizeString }),
        ("Overall Bit Rate", { $0.generalTrack?.fields.first(where: { $0.key == "OverallBitRate/String" })?.value ?? "" }),
        ("Video Format",     { $0.videoTracks.first?.fields.first(where: { $0.key == "Format" })?.value ?? "" }),
        ("Video Codec",      { $0.videoTracks.first?.fields.first(where: { $0.key == "Format_Commercial_IfAny" })?.value ?? "" }),
        ("Resolution", { f in
            let v = f.videoTracks.first
            let w = v?.fields.first(where: { $0.key == "Width" })?.value  ?? ""
            let h = v?.fields.first(where: { $0.key == "Height" })?.value ?? ""
            return w.isEmpty ? "" : "\(w)×\(h)"
        }),
        ("Frame Rate", { f in
            guard let v = f.videoTracks.first?.fields.first(where: { $0.key == "FrameRate" })?.value else { return "" }
            return v + " fps"
        }),
        ("Bit Depth",        { $0.videoTracks.first?.fields.first(where: { $0.key == "BitDepth" })?.value ?? "" }),
        ("Color Space",      { $0.videoTracks.first?.fields.first(where: { $0.key == "ColorSpace" })?.value ?? "" }),
        ("HDR",              { $0.videoTracks.first?.fields.first(where: { $0.key == "HDR_Format" })?.value ?? "" }),
        ("Audio Format",     { $0.audioTracks.first?.fields.first(where: { $0.key == "Format" })?.value ?? "" }),
        ("Audio Ch.",        { $0.audioTracks.first?.fields.first(where: { $0.key == "Channel(s)/String" })?.value ?? "" }),
        ("Sample Rate",      { $0.audioTracks.first?.fields.first(where: { $0.key == "SamplingRate/String" })?.value ?? "" }),
        ("Audio BitRate",    { $0.audioTracks.first?.fields.first(where: { $0.key == "BitRate/String" })?.value ?? "" }),
        ("Subtitles",        { f in f.textTracks.isEmpty ? "" : "\(f.textTracks.count)" }),
    ]

    var body: some View {
        if store.files.isEmpty {
            Text("Open files to compare them in Sheet view")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView([.horizontal, .vertical]) {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(columns, id: \.label) { col in
                            Text(col.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(minWidth: 120, alignment: .leading)
                                .background(Color(NSColor.controlBackgroundColor))
                                .border(Color(NSColor.separatorColor).opacity(0.5), width: 0.5)
                        }
                    }
                    ForEach(Array(store.files.enumerated()), id: \.element.id) { rowIdx, file in
                        GridRow {
                            ForEach(columns, id: \.label) { col in
                                let value = col.keyPath(file)
                                Text(value.isEmpty ? "—" : value)
                                    .font(.system(size: 11))
                                    .foregroundColor(value.isEmpty ? .secondary : .primary)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .frame(minWidth: 120, alignment: .leading)
                                    .background(
                                        file.id == store.selectedID
                                            ? Color.accentColor.opacity(0.1)
                                            : (rowIdx % 2 == 0
                                               ? Color(NSColor.controlBackgroundColor)
                                               : Color(NSColor.alternatingContentBackgroundColors[1]))
                                    )
                                    .border(Color(NSColor.separatorColor).opacity(0.3), width: 0.5)
                            }
                        }
                        .onTapGesture { store.selectedID = file.id }
                    }
                }
            }
        }
    }
}