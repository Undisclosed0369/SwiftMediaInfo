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
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if let file = store.currentFile {
                if file.isLoading {
                    loadingView(name: file.fileName, progress: file.analysisProgress)
                        .transition(.opacity)
                } else if let error = file.error {
                    errorView(message: error)
                        .transition(.opacity)
                } else {
                    fileContentView(file: file)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            } else {
                EmptyStateView()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: store.currentFile?.id)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: store.isCompareMode)
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
                noOutputPlaceholder
            } else {
                onDemandPlaceholder(label: "Text", isLoading: file.isLoadingText, color: .brandViolet) {
                    store.loadFormatIfNeeded(.text)
                }
            }
            
        case .rawText:
            if let content = file.rawTextFull, !content.isEmpty {
                RawTextView(content: content)
            } else if file.rawTextFull != nil {
                noOutputPlaceholder
            } else {
                onDemandPlaceholder(label: "Raw Text", isLoading: file.isLoadingRawText, color: .brandPink) {
                    store.loadFormatIfNeeded(.rawText)
                }
            }
            
        case .html:
            if let content = file.rawHTML, !content.isEmpty {
                HTMLView(htmlString: content)
            } else if file.rawHTML != nil {
                noOutputPlaceholder
            } else {
                onDemandPlaceholder(label: "HTML", isLoading: file.isLoadingHTML, color: .brandGreen) {
                    store.loadFormatIfNeeded(.html)
                }
            }
            
        case .xml:
            if let content = file.rawXML, !content.isEmpty {
                RawTextView(content: content)
            } else if file.rawXML != nil {
                noOutputPlaceholder
            } else {
                onDemandPlaceholder(label: "XML", isLoading: file.isLoadingXML, color: .brandBlue) {
                    store.loadFormatIfNeeded(.xml)
                }
            }
            
        case .json:
            if let content = file.rawJSON, !content.isEmpty {
                RawTextView(content: content)
            } else if file.rawJSON != nil {
                noOutputPlaceholder
            } else {
                onDemandPlaceholder(label: "JSON", isLoading: file.isLoadingJSON, color: .brandViolet) {
                    store.loadFormatIfNeeded(.json)
                }
            }
        }
    }
    
    // MARK: - No output placeholder
    
    private var noOutputPlaceholder: some View {
        GlassPlaceholder(
            icon: "doc.questionmark",
            title: "No output from MediaInfo",
            subtitle: "MediaInfo ran but returned nothing for this file.\nThe file might be unsupported or MediaInfo may not be installed.",
            accentColor: .brandPink
        )
    }
    
    // MARK: - On-demand placeholder
    
    private func onDemandPlaceholder(
        label: String,
        isLoading: Bool,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 20) {
            if isLoading {
                ProgressView()
                    .tint(color)
                    .scaleEffect(1.2)
                Text("Loading \(label)…")
                    .font(.headline)
                    .foregroundStyle(color)
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(color.opacity(0.5))
                    .symbolEffect(.pulse)
                Text("\(label) not loaded yet")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("This format loads on demand to keep things fast.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Load \(label)") { action() }
                    .buttonStyle(.borderedProminent)
                    .tint(color)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Loading / error
    
    // Fix #7: loadingView now accepts an optional progress value and shows a
    // real progress bar instead of a spinner when a value is available.
    private func loadingView(name: String, progress: Double?) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.brandViolet.opacity(0.12))
                    .frame(width: 72, height: 72)
                if let pct = progress {
                    // Real progress ring for large files
                    Circle()
                        .trim(from: 0, to: pct)
                        .stroke(Color.brandViolet, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 52, height: 52)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.3), value: pct)
                    Text("\(Int(pct * 100))%")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.brandViolet)
                } else {
                    ProgressView()
                        .tint(.brandViolet)
                        .scaleEffect(1.3)
                }
            }
            Text("Analysing \(name)…")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text(progress != nil ? "Reading a large file — this may take a moment." : "Fetching all formats in parallel.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(message: String) -> some View {
        GlassPlaceholder(
            icon: "exclamationmark.triangle",
            title: "Something went wrong",
            subtitle: message,
            accentColor: .orange
        )
    }
}

// MARK: - Reusable glass placeholder

struct GlassPlaceholder: View {
    let icon: String
    let title: String
    let subtitle: String
    var accentColor: Color = .brandViolet
    
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(accentColor.opacity(0.75))
            }
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Empty state
// Fix #5: Shows recent file chips so users can quickly reopen past files.

struct EmptyStateView: View {
    @EnvironmentObject var store: MediaStore
    @State private var hovered = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.brandViolet.opacity(0.18), Color.brandBlue.opacity(0.08)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                    .scaleEffect(hovered ? 1.08 : 1.0)
                
                Image(systemName: "film.stack")
                    .font(.system(size: 52, weight: .thin))
                    .foregroundStyle(
                        LinearGradient.brandBlueViolet
                    )
                    .scaleEffect(hovered ? 1.05 : 1.0)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.6), value: hovered)
            
            VStack(spacing: 8) {
                Text("Drop a media file to get started")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                
                Text("Or use File › Open, or the Open button above.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Button("Open File…") { store.openFilePicker() }
                .buttonStyle(.borderedProminent)
                .tint(.brandViolet)
                .controlSize(.large)
            
            // ── Recent files chips ─────────────────────────────────────────
            if !store.recentFileURLs.isEmpty {
                VStack(spacing: 10) {
                    Text("Recent Files")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    // Wrap chips in a flow-like grid (fixed columns, up to 10 items)
                    let columns = [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: 8)]
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(store.recentFileURLs, id: \.self) { url in
                            RecentFileChip(url: url) {
                                store.openURL(url)
                            }
                        }
                    }
                    .frame(maxWidth: 600)
                    
                    // Clear Recents button
                    Button(role: .destructive) {
                        store.clearRecentFiles()
                    } label: {
                        Label("Clear Recents", systemImage: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { hovered = $0 }
        .contentShape(Rectangle())
        .onTapGesture { store.openFilePicker() }
    }
}

// MARK: - Recent file chip

struct RecentFileChip: View {
    let url: URL
    let action: () -> Void
    @State private var hovered = false
    
    private var fileIcon: String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp4", "mov", "mkv", "avi", "m4v", "wmv", "webm": return "film"
        case "mp3", "aac", "flac", "wav", "m4a", "ogg":        return "waveform"
        case "jpg", "jpeg", "png", "gif", "tiff", "heic":      return "photo"
        default:                                                 return "doc"
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: fileIcon)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.brandViolet.opacity(0.8))
                    .frame(width: 18)
                Text(url.lastPathComponent)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovered
                          ? Color.brandViolet.opacity(0.12)
                          : Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.brandViolet.opacity(hovered ? 0.3 : 0.1),
                                          lineWidth: 0.7)
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(url.path)
    }
}
