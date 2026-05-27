//
//  CompareView.swift
//  SwiftMediaInfo
//

import SwiftUI
import UniformTypeIdentifiers

/// Shows two files side-by-side so you can compare their media information.
/// Each pane has its own drag-and-drop target and a swap button in the header.
struct CompareView: View {
    @EnvironmentObject var store: MediaStore
    
    // Separate targeted states so only the hovered pane highlights
    @State private var isTargetedLeft  = false
    @State private var isTargetedRight = false
    
    var body: some View {
        HStack(spacing: 0) {
            
            // ── Left pane: File A ─────────────────────────────────────────
            ZStack {
                VStack(spacing: 0) {
                    paneHeader(file: store.currentFile, label: "File A", isLeft: true)
                    Divider()
                    paneContent(file: store.currentFile, isCompare: false)
                }
                
                // Drop-highlight overlay — only shown while a file is hovering
                if isTargetedLeft {
                    dropOverlay(color: .blue)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargetedLeft) { providers in
                handleDrop(providers: providers, isLeft: true)
            }
            
            Divider()
            
            // ── Right pane: File B ────────────────────────────────────────
            ZStack {
                VStack(spacing: 0) {
                    paneHeader(file: store.compareFile, label: "File B", isLeft: false)
                    Divider()
                    paneContent(file: store.compareFile, isCompare: true)
                }
                
                if isTargetedRight {
                    dropOverlay(color: .purple)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargetedRight) { providers in
                handleDrop(providers: providers, isLeft: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: store.viewMode) { _, newMode in
            store.loadFormatIfNeeded(newMode, isCompare: false)
            store.loadFormatIfNeeded(newMode, isCompare: true)
        }
    }
    
    // MARK: - Drop handler
    
    private func handleDrop(providers: [NSItemProvider], isLeft: Bool) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard
                let data = item as? Data,
                let url  = URL(dataRepresentation: data, relativeTo: nil)
            else { return }
            DispatchQueue.main.async {
                if isLeft { store.openURL(url) }
                else      { store.openCompareURL(url) }
            }
        }
        return true
    }
    
    // MARK: - Drop highlight overlay
    
    private func dropOverlay(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(color, lineWidth: 3)
            .background(color.opacity(0.07).cornerRadius(10))
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(color)
                    Text("Drop to open here")
                        .font(.headline)
                        .foregroundColor(color)
                }
            )
            .padding(8)
            .allowsHitTesting(false)
    }
    
    // MARK: - Pane header
    
    @ViewBuilder
    private func paneHeader(file: MediaFile?, label: String, isLeft: Bool) -> some View {
        HStack(spacing: 8) {
            // Coloured "File A" / "File B" badge
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
                // No file yet — show an Open button
                Button(isLeft ? "Open File A…" : "Open File B…") {
                    if isLeft { store.openFilePicker() }
                    else      { store.openCompareFilePicker() }
                }
                .buttonStyle(.bordered)
                .font(.system(size: 12))
            }
            
            Spacer()
            
            // ── Swap / replace button — shown for BOTH panes once a file is loaded ──
            // Previously only File B had this. Now File A has one too (change #3).
            if file != nil {
                Button {
                    if isLeft { store.openFilePicker() }
                    else      { store.openCompareFilePicker() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help(isLeft ? "Choose a different File A" : "Choose a different File B")
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
            // No file chosen yet — invite the user to drop or click
            VStack(spacing: 16) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary.opacity(0.3))
                Text("No file selected")
                    .foregroundColor(.secondary)
                Text("Drop a file here or click Open above")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Route to the right view
    
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
    
    // MARK: - Lazy-load placeholder
    
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
