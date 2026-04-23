//
//  MainDetailView.swift
//  SwiftMediaInfo
//
//  Created by Undisclosed on 23/4/26.
//


//
//  MainDetailView.swift
//  MediaInfoMac
//

import SwiftUI

struct MainDetailView: View {
    @EnvironmentObject var store: MediaStore

    var body: some View {
        Group {
            if store.files.isEmpty {
                EmptyStateView()
            } else if let file = store.selectedFile {
                if file.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Analysing \(file.fileName)…")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = file.error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                            .foregroundColor(.orange)
                        Text(error).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch store.viewMode {
                    case .easy:  EasyView(file: file)
                    case .sheet: SheetView()
                    case .tree:  TreeView(file: file)
                    case .text:  RawTextView(content: file.rawText)
                    case .html:  HTMLView(htmlString: file.rawHTML)
                    case .xml:   RawTextView(content: file.rawXML)
                    case .json:  RawTextView(content: file.rawJSON)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    @EnvironmentObject var store: MediaStore

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.3))
            Text("No media files open")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Drag & drop files here, or use File > Open")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
            Button("Open File…") { store.openFilePicker() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}