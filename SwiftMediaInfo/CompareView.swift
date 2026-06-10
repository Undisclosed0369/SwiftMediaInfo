//
//  CompareView.swift
//  SwiftMediaInfo
//

import SwiftUI
import UniformTypeIdentifiers

struct CompareView: View {
    @EnvironmentObject var store: MediaStore
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
                if isTargetedLeft {
                    GlassDropOverlay(color: .brandBlue)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargetedLeft) { providers in
                handleDrop(providers: providers, isLeft: true)
            }
            .animation(.spring(response: 0.25), value: isTargetedLeft)
            
            Divider()
            
            // ── Right pane: File B ────────────────────────────────────────
            ZStack {
                VStack(spacing: 0) {
                    paneHeader(file: store.compareFile, label: "File B", isLeft: false)
                    Divider()
                    paneContent(file: store.compareFile, isCompare: true)
                }
                if isTargetedRight {
                    GlassDropOverlay(color: .brandPink)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargetedRight) { providers in
                handleDrop(providers: providers, isLeft: false)
            }
            .animation(.spring(response: 0.25), value: isTargetedRight)
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
    
    // MARK: - Pane header
    
    @ViewBuilder
    private func paneHeader(file: MediaFile?, label: String, isLeft: Bool) -> some View {
        let accent: Color = isLeft ? .brandBlue : .brandPink
        
        HStack(spacing: 8) {
            // Badge
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(accent)
                )
            
            if let file = file {
                Text(file.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !file.isLoading {
                    Text(file.fileSizeString)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(isLeft ? "Open File A…" : "Open File B…") {
                    if isLeft { store.openFilePicker() }
                    else      { store.openCompareFilePicker() }
                }
                .buttonStyle(.bordered)
                .tint(accent)
                .font(.system(size: 12))
            }
            
            Spacer()
            
            if file != nil {
                Button {
                    if isLeft { store.openFilePicker() }
                    else      { store.openCompareFilePicker() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .help(isLeft ? "Choose a different File A" : "Choose a different File B")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Pane content
    
    @ViewBuilder
    private func paneContent(file: MediaFile?, isCompare: Bool) -> some View {
        if let file = file {
            if file.isLoading {
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(isCompare ? .brandPink : .brandBlue)
                    Text("Analysing \(file.fileName)…")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
            } else if let error = file.error {
                GlassPlaceholder(
                    icon: "exclamationmark.triangle",
                    title: "Error",
                    subtitle: error,
                    accentColor: .orange
                )
                
            } else {
                resolvedContent(file: file, isCompare: isCompare)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        (isCompare ? Color.brandPink : Color.brandBlue).opacity(0.35)
                    )
                    .symbolEffect(.pulse)
                Text("No file selected")
                    .foregroundStyle(.secondary)
                Text("Drop a file here or click Open above")
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.6))
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
                lazyPlaceholder(label: "Text", isLoading: file.isLoadingText, color: .brandViolet) {
                    store.loadFormatIfNeeded(.text, isCompare: isCompare)
                }
            }
            
        case .rawText:
            if let content = file.rawTextFull {
                RawTextView(content: content)
            } else {
                lazyPlaceholder(label: "Raw Text", isLoading: file.isLoadingRawText, color: .brandPink) {
                    store.loadFormatIfNeeded(.rawText, isCompare: isCompare)
                }
            }
            
        case .html:
            if let content = file.rawHTML {
                HTMLView(htmlString: content)
            } else {
                lazyPlaceholder(label: "HTML", isLoading: file.isLoadingHTML, color: .brandGreen) {
                    store.loadFormatIfNeeded(.html, isCompare: isCompare)
                }
            }
            
        case .xml:
            if let content = file.rawXML {
                RawTextView(content: content)
            } else {
                lazyPlaceholder(label: "XML", isLoading: file.isLoadingXML, color: .brandBlue) {
                    store.loadFormatIfNeeded(.xml, isCompare: isCompare)
                }
            }
            
        case .json:
            if let content = file.rawJSON {
                RawTextView(content: content)
            } else {
                lazyPlaceholder(label: "JSON", isLoading: file.isLoadingJSON, color: .brandViolet) {
                    store.loadFormatIfNeeded(.json, isCompare: isCompare)
                }
            }
        }
    }
    
    // MARK: - Lazy-load placeholder
    
    private func lazyPlaceholder(
        label: String,
        isLoading: Bool,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 14) {
            if isLoading {
                ProgressView().tint(color)
                Text("Loading \(label)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(color.opacity(0.4))
                    .symbolEffect(.pulse)
                Text("\(label) not loaded")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Load \(label)") { action() }
                    .buttonStyle(.borderedProminent)
                    .tint(color)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
