//
//  StatusBar.swift
//  SwiftMediaInfo
//
//  Created by Undisclosed on 23/4/26.
//


//
//  StatusBar.swift
//  MediaInfoMac
//

import SwiftUI

struct StatusBar: View {
    @EnvironmentObject var store: MediaStore

    var body: some View {
        HStack(spacing: 16) {
            if let file = store.selectedFile, !file.isLoading {
                if let general = file.generalTrack {
                    statusItem(icon: "doc",
                               text: general.fields.first(where: { $0.key == "Format" })?.value ?? "")
                    if let dur = general.fields.first(where: { $0.key == "Duration/String" })?.value {
                        statusItem(icon: "clock", text: dur)
                    }
                    if let br = general.fields.first(where: { $0.key == "OverallBitRate/String" })?.value {
                        statusItem(icon: "waveform.path", text: br)
                    }
                }
                if let v = file.videoTracks.first {
                    Divider().frame(height: 12)
                    let w = v.fields.first(where: { $0.key == "Width" })?.value  ?? ""
                    let h = v.fields.first(where: { $0.key == "Height" })?.value ?? ""
                    if !w.isEmpty { statusItem(icon: "film", text: "\(w)×\(h)") }
                    if let fps = v.fields.first(where: { $0.key == "FrameRate" })?.value {
                        statusItem(icon: "speedometer", text: fps + " fps")
                    }
                }
                if !file.audioTracks.isEmpty {
                    Divider().frame(height: 12)
                    statusItem(icon: "waveform",
                               text: "\(file.audioTracks.count) audio stream\(file.audioTracks.count == 1 ? "" : "s")")
                }
                if !file.textTracks.isEmpty {
                    statusItem(icon: "captions.bubble",
                               text: "\(file.textTracks.count) subtitle\(file.textTracks.count == 1 ? "" : "s")")
                }
                Spacer()
                statusItem(icon: "internaldrive", text: file.fileSizeString)
            } else if store.files.isEmpty {
                Text("No file open").font(.caption).foregroundColor(.secondary)
                Spacer()
            } else {
                Text("Loading…").font(.caption).foregroundColor(.secondary)
                Spacer()
            }

            if store.files.count > 1 {
                Text("\(store.files.count) files")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func statusItem(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10)).foregroundColor(.secondary)
            Text(text).font(.system(size: 11)).foregroundColor(.secondary)
        }
    }
}