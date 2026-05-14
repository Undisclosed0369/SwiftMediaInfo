//
//  MainDetailView.swift
//  SwiftMediaInfo
//
//  Created by Undisclosed on 23/4/26.
//

//
//  MainDetailView.swift
//  SwiftMediaInfo
//

import SwiftUI

struct MainDetailView: View {
    @EnvironmentObject var store: MediaStore
    
    var body: some View {
        Group {
            if store.isCompareMode {
                CompareView()
            } else if let file = store.currentFile {
                if file.isLoading {
                    loadingView(name: file.fileName)
                } else if let error = file.error {
                    errorView(message: error)
                } else {
                    fileContentView(file: file)
                }
            } else {
                EmptyStateView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Whenever the user switches tabs, trigger loading for that format
        .onChange(of: store.viewMode) { _, newMode in
            store.loadFormatIfNeeded(newMode, isCompare: false)
        }
    }
    
    // MARK: - Content router
    
    @ViewBuilder
    private func fileContentView(file: MediaFile) -> some View {
        switch store.viewMode {
            
        case .easy:
            // JSON powers Easy; it's loaded in the initial pass, so it's always ready
            EasyView(file: file)
            
        case .text:
            // Text is loaded in the initial pass, always ready
            if let content = file.rawText {
                RawTextView(content: content)
            } else {
                onDemandPlaceholder(label: "Text", isLoading: file.isLoadingText) {
                    store.loadFormatIfNeeded(.text)
                }
            }
            
        case .rawText:
            if let content = file.rawTextFull {
                RawTextView(content: content)
            } else {
                onDemandPlaceholder(label: "Raw Text", isLoading: file.isLoadingRawText) {
                    store.loadFormatIfNeeded(.rawText)
                }
            }
            
        case .html:
            if let content = file.rawHTML {
                HTMLView(htmlString: content)
            } else {
                onDemandPlaceholder(label: "HTML", isLoading: file.isLoadingHTML) {
                    store.loadFormatIfNeeded(.html)
                }
            }
            
        case .xml:
            if let content = file.rawXML {
                RawTextView(content: content)
            } else {
                onDemandPlaceholder(label: "XML", isLoading: file.isLoadingXML) {
                    store.loadFormatIfNeeded(.xml)
                }
            }
            
        case .json:
            if let content = file.rawJSON {
                RawTextView(content: content)
            } else {
                onDemandPlaceholder(label: "JSON", isLoading: file.isLoadingJSON) {
                    store.loadFormatIfNeeded(.json)
                }
            }
        }
    }
    
    // MARK: - Placeholder shown for unloaded on-demand formats
    //
    // If the format is already being fetched (isLoading = true) we show a
    // spinner. Otherwise we show a "Load" button so the user can kick it off.
    
    private func onDemandPlaceholder(label: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            if isLoading {
                ProgressView()
                Text("Loading \(label)…")
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary.opacity(0.4))
                Text("\(label) not loaded yet")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("This format is loaded on demand to keep things fast.")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                Button("Load \(label)") { action() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Loading / error states
    
    private func loadingView(name: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Analysing \(name)…")
                .foregroundColor(.secondary)
            Text("Loading Text and Easy view first. Other formats load when you click their tab.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(.orange)
            Text(message).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    @EnvironmentObject var store: MediaStore
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.3))
            Text("No media file open")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Drag & drop a file here, or use File > Open")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
            Button("Open File…") { store.openFilePicker() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

