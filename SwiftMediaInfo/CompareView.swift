//
//  CompareView.swift
//  SwiftMediaInfo
//
//  Created by Undisclosed on 14/5/26.
//

//
//  CompareView.swift
//  SwiftMediaInfo
//

import SwiftUI

/// Shows two files side-by-side so you can compare their media information.
/// Each pane respects lazy loading — on-demand formats show a Load button
/// just like the single-file view does.
struct CompareView: View {
    @EnvironmentObject var store: MediaStore
    
    var body: some View {
        HStack(spacing: 0) {
            // ── Left pane: primary file ───────────────────────────────────
            VStack(spacing: 0) {
                paneHeader(file: store.currentFile, label: "File A", isLeft: true)
                Divider()
                paneContent(file: store.currentFile, isCompare: false)
            }
            
            Divider()
            
            // ── Right pane: compare file ──────────────────────────────────
            VStack(spacing: 0) {
                paneHeader(file: store.compareFile, label: "File B", isLeft: false)
                Divider()
                paneContent(file: store.compareFile, isCompare: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: store.viewMode) { _, newMode in
            // Trigger on-demand loading for both panes when the tab changes
            store.loadFormatIfNeeded(newMode, isCompare: false)
            store.loadFormatIfNeeded(newMode, isCompare: true)
        }
    }
    
    // MARK: - Pane header
    
    @ViewBuilder
    private func paneHeader(file: MediaFile?, label: String, isLeft: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(isLeft ? Color.blue : Color.purple)
                .cornerRadius(5)
            
            if let file = file {
                Text(file.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !file.isLoading {
                    Text(file.fileSizeString)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else {
                Button(isLeft ? "Open File A…" : "Open File B…") {
                    if isLeft { store.openFilePicker() }
                    else      { store.openCompareFilePicker() }
                }
                .buttonStyle(.bordered)
                .font(.system(size: 12))
            }
            
            Spacer()
            
            if file != nil && !isLeft {
                Button { store.openCompareFilePicker() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Choose a different file to compare")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Pane content
    
    @ViewBuilder
    private func paneContent(file: MediaFile?, isCompare: Bool) -> some View {
        if let file = file {
            if file.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Analysing \(file.fileName)…")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("Large files may take a moment.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
            } else if let error = file.error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
            } else {
                resolvedContent(file: file, isCompare: isCompare)
            }
            
        } else {
            // No file chosen yet
            VStack(spacing: 16) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary.opacity(0.3))
                Text("No file selected")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Route to the right view (with lazy-load placeholders)
    
    @ViewBuilder
    private func resolvedContent(file: MediaFile, isCompare: Bool) -> some View {
        switch store.viewMode {
            
        case .easy:
            EasyView(file: file)
            
        case .text:
            if let content = file.rawText {
                RawTextView(content: content)
            } else {
                lazyPlaceholder(label: "Text", isLoading: file.isLoadingText) {
                    store.loadFormatIfNeeded(.text, isCompare: isCompare)
                }
            }
            
        case .rawText:
            if let content = file.rawTextFull {
                RawTextView(content: content)
            } else {
                lazyPlaceholder(label: "Raw Text", isLoading: file.isLoadingRawText) {
                    store.loadFormatIfNeeded(.rawText, isCompare: isCompare)
                }
            }
            
        case .html:
            if let content = file.rawHTML {
                HTMLView(htmlString: content)
            } else {
                lazyPlaceholder(label: "HTML", isLoading: file.isLoadingHTML) {
                    store.loadFormatIfNeeded(.html, isCompare: isCompare)
                }
            }
            
        case .xml:
            if let content = file.rawXML {
                RawTextView(content: content)
            } else {
                lazyPlaceholder(label: "XML", isLoading: file.isLoadingXML) {
                    store.loadFormatIfNeeded(.xml, isCompare: isCompare)
                }
            }
            
        case .json:
            if let content = file.rawJSON {
                RawTextView(content: content)
            } else {
                lazyPlaceholder(label: "JSON", isLoading: file.isLoadingJSON) {
                    store.loadFormatIfNeeded(.json, isCompare: isCompare)
                }
            }
        }
    }
    
    // MARK: - Lazy-load placeholder (compact version for split panes)
    
    private func lazyPlaceholder(label: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            if isLoading {
                ProgressView()
                Text("Loading \(label)…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary.opacity(0.4))
                Text("\(label) not loaded")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Button("Load \(label)") { action() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

