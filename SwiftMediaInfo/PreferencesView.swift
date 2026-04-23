//
//  PreferencesView.swift
//  SwiftMediaInfo
//
//  Created by Undisclosed on 23/4/26.
//


//
//  PreferencesView.swift
//  MediaInfoMac
//

import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var store: MediaStore
    @AppStorage("defaultViewMode") var defaultViewMode: String = ViewMode.easy.rawValue

    var body: some View {
        Form {
            Section("Appearance") {
                HStack {
                    Text("Font Size")
                    Slider(value: $store.fontSize, in: 8...22, step: 1)
                        .frame(width: 160)
                    Text("\(Int(store.fontSize)) pt")
                        .frame(width: 36)
                        .foregroundColor(.secondary)
                }
                Picker("Default View", selection: $defaultViewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
            }

            Section("MediaInfo Binary") {
                HStack {
                    Text("Path:").foregroundColor(.secondary)
                    Text(MediaEngine.binaryPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(
                            FileManager.default.fileExists(atPath: MediaEngine.binaryPath)
                                ? .green : .red
                        )
                    Spacer()
                    if !FileManager.default.fileExists(atPath: MediaEngine.binaryPath) {
                        Link("Install via Homebrew",
                             destination: URL(string: "https://formulae.brew.sh/formula/media-info")!)
                    }
                }
                Text("brew install media-info")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}