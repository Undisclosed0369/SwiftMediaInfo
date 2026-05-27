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
        .onChange(of: store.viewMode) { _, newMode in
            store.loadFormatIfNeeded(newMode, isCompare: false)
        }
    }
    
    // MARK: - Content router
    
    @ViewBuilder
    private func fileContentView(file: MediaFile) -> some View {
        switch store.viewMode {
            
        case .easy:
            EasyView(file: file)
            
        case .text:
            if let content = file.rawText, !content.isEmpty {
                RawTextView(content: content)
            } else if file.rawText != nil {
                // rawText was loaded but came back empty — MediaInfo produced no output
                noOutputPlaceholder
            } else {
                onDemandPlaceholder(label: "Text", isLoading: file.isLoadingText) {
                    store.loadFormatIfNeeded(.text)
                }
            }
            
        case .rawText:
            if let content = file.rawTextFull, !content.isEmpty {
                RawTextView(content: content)
            } else if file.rawTextFull != nil {
                noOutputPlaceholder
            } else {
                onDemandPlaceholder(label: "Raw Text", isLoading: file.isLoadingRawText) {
                    store.loadFormatIfNeeded(.rawText)
                }
            }
            
        case .html:
            if let content = file.rawHTML, !content.isEmpty {
                HTMLView(htmlString: content)
            } else if file.rawHTML != nil {
                noOutputPlaceholder
            } else {
                onDemandPlaceholder(label: "HTML", isLoading: file.isLoadingHTML) {
                    store.loadFormatIfNeeded(.html)
                }
            }
            
        case .xml:
            if let content = file.rawXML, !content.isEmpty {
                RawTextView(content: content)
            } else if file.rawXML != nil {
                noOutputPlaceholder
            } else {
                onDemandPlaceholder(label: "XML", isLoading: file.isLoadingXML) {
                    store.loadFormatIfNeeded(.xml)
                }
            }
            
        case .json:
            if let content = file.rawJSON, !content.isEmpty {
                RawTextView(content: content)
            } else if file.rawJSON != nil {
                noOutputPlaceholder
            } else {
                onDemandPlaceholder(label: "JSON", isLoading: file.isLoadingJSON) {
                    store.loadFormatIfNeeded(.json)
                }
            }
        }
    }
    
    // MARK: - "No output" placeholder
    //
    // Shown when a format was fetched successfully but MediaInfo returned an
    // empty string — instead of showing a blank white box.
    
    private var noOutputPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.35))
            Text("No output from MediaInfo")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("MediaInfo ran but returned nothing for this file.\nThe file might be unsupported, or MediaInfo may not be\ninstalled at the expected path.")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - On-demand placeholder
    
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
            Text("Fetching all formats in parallel. HTML and XML load when you click their tab.")
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
