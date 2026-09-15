//
//  MainDetailView.swift
//  SwiftMediaInfo
//
//  PHASE 3 — every pane now routes through ContentState.
//
//  The old version had a nested if/else per tab that inferred meaning from nil
//  strings. That's gone: one call to ContentState.resolve decides what to show,
//  and anything that isn't `.ready` is drawn by ContentStateView. Adding a new
//  state later means changing one enum, not six branches.
//
//  Empty-state and recent-file chips are unchanged in behaviour but now read
//  from the design tokens.
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
                paneContent(file: file)
            } else {
                EmptyStateView()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .smiAnimation(SMI.Motion.smooth, value: store.currentFile?.id)
        .smiAnimation(SMI.Motion.smooth, value: store.isCompareMode)
        .onChange(of: store.viewMode) { _, newMode in
            store.loadFormatIfNeeded(newMode, isCompare: false)
        }
        // Opening a file while already sitting on a lazy tab used to leave the
        // "Load HTML" button showing, because no tab change occurred to trigger
        // the fetch. Lazy loading still applies — a format is only fetched when
        // its tab is actually on screen — it just no longer needs a manual nudge.
        .onChange(of: store.currentFile?.id) { _, _ in
            store.loadFormatIfNeeded(store.viewMode, isCompare: false)
        }
        .onChange(of: store.currentFile?.isLoading) { _, isLoading in
            // The initial parallel analysis has to finish before an on-demand
            // format can be requested, so retry once it completes.
            if isLoading == false {
                store.loadFormatIfNeeded(store.viewMode, isCompare: false)
            }
        }
    }
    
    // MARK: - Pane router
    
    @ViewBuilder
    private func paneContent(file: MediaFile) -> some View {
        let state = ContentState.resolve(file: file, mode: store.viewMode)
        
        Group {
            if state.isReady {
                readyContent(file: file)
                    .transition(.opacity)
            } else {
                ContentStateView(state: state, isCompare: false)
                    .transition(.opacity)
            }
        }
        .smiAnimation(SMI.Motion.fade, value: state)
    }
    
    private var isSearchActive: Bool {
        store.showSearchBar && !store.searchQuery.isEmpty
    }
    
    @ViewBuilder
    private func readyContent(file: MediaFile) -> some View {
        VStack(spacing: 0) {
            // PHASE 10. Above the tab content rather than inside Easy View, so
            // it survives the switch to the search and diff variants and stays
            // visible on the text tabs too. A checksum that vanishes when you
            // change tab is one you cannot watch finish.
            //
            // Renders nothing once the digest is ready — at that point the
            // store has injected it into the General track, where it behaves
            // like any other field.
            ChecksumCard(isCompare: false)
                .padding(.horizontal, SMI.Spacing.xLarge)
                .padding(.top, SMI.Spacing.large)
            
            tabContent(file: file)
        }
    }
    
    @ViewBuilder
    private func tabContent(file: MediaFile) -> some View {
        switch store.viewMode {
            
        case .easy:
            if isSearchActive {
                FilterableEasyView(file: file)
            } else {
                EasyView(file: file)
            }
            
        case .text:
            textualContent(file.rawText)
            
        case .rawText:
            textualContent(file.rawTextFull)
            
        case .xml:
            textualContent(file.rawXML)
            
        case .json:
            textualContent(file.rawJSON)
            
        case .html:
            if let content = file.rawHTML {
                HTMLView(htmlString: content)
            }
        }
    }
    
    @ViewBuilder
    private func textualContent(_ content: String?) -> some View {
        if let content {
            if isSearchActive {
                FilterableRawTextView(content: content)
            } else {
                RawTextView(content: content)
            }
        }
    }
}

// MARK: - Reusable glass placeholder
//
// Retained for any caller outside the state system. New code should prefer
// ContentStateView so states stay consistent.

// MARK: - Empty state

struct EmptyStateView: View {
    @EnvironmentObject var store: MediaStore
    @State private var hovered = false
    
    var body: some View {
        VStack(spacing: SMI.Spacing.xxLarge) {
            
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.brandViolet.opacity(0.18),
                                Color.brandBlue.opacity(0.06)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 64
                        )
                    )
                    .frame(width: 128, height: 128)
                    .scaleEffect(hovered ? 1.06 : 1.0)
                
                Image(systemName: "film.stack")
                    .font(.system(size: 52, weight: .thin))
                    .foregroundStyle(LinearGradient.brandBlueViolet)
                    .scaleEffect(hovered ? 1.04 : 1.0)
            }
            .smiAnimation(SMI.Motion.flourish, value: hovered)
            // Illustration. It repeats what the headline underneath already
            // says, so it stays silent.
            .smiDecorativeChrome()
            
            VStack(spacing: SMI.Spacing.small) {
                Text("Drop a media file to get started")
                    .font(SMI.Typo.display)
                    .foregroundStyle(.primary)
                
                Text("Or press ⌘O, or use the Open button above.")
                    .font(SMI.Typo.body)
                    .foregroundStyle(.secondary)
            }
            
            Button("Open File…") { store.openFilePicker() }
                .buttonStyle(.borderedProminent)
                .tint(.brandViolet)
                .controlSize(.large)
            
            // ── Recent files ───────────────────────────────────────────────
            if !store.recentFileURLs.isEmpty {
                VStack(spacing: SMI.Spacing.medium) {
                    GlassSectionHeader(title: "Recent Files", icon: "clock.arrow.circlepath")
                        .frame(maxWidth: 600)
                    
                    let columns = [
                        GridItem(.adaptive(minimum: 170, maximum: 260), spacing: SMI.Spacing.small)
                    ]
                    
                    LazyVGrid(columns: columns, spacing: SMI.Spacing.small) {
                        ForEach(store.recentFileURLs, id: \.self) { url in
                            RecentFileChip(url: url, store: store) {
                                store.openURL(url)
                            }
                        }
                    }
                    .frame(maxWidth: 600)
                    
                    Button(role: .destructive) {
                        store.clearRecentFiles()
                    } label: {
                        Label("Clear Recents", systemImage: "trash")
                            .font(SMI.Typo.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.top, SMI.Spacing.tight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(SMI.Spacing.huge)
        .onHover { hovered = $0 }
        .contentShape(Rectangle())
        .onTapGesture { store.openFilePicker() }
        // PHASE 11. `onTapGesture` on a bare view is invisible to VoiceOver and
        // unreachable from the keyboard — clicking anywhere in the empty state
        // opens the picker, and there was no way to discover or trigger that
        // without a pointer. The explicit action exposes the same behaviour in
        // the rotor. The Open File… button above remains the obvious route;
        // this just stops the larger target being a pointer-only secret.
        .accessibilityAction(named: "Open a file") {
            store.openFilePicker()
        }
    }
}

// MARK: - Recent file chip

struct RecentFileChip: View {
    let url: URL
    /// Passed in rather than read from the environment: `contextMenu` builds
    /// its content in a detached presentation context, and an environment
    /// object does not reliably survive the trip.
    let store: MediaStore
    let action: () -> Void
    
    @State private var hovered = false
    
    private var fileIcon: String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp4", "mov", "mkv", "avi", "m4v", "wmv", "webm": return "film"
        case "mp3", "aac", "flac", "wav", "m4a", "ogg":        return "waveform"
        case "jpg", "jpeg", "png", "gif", "tiff", "heic":      return "photo"
        default:                                               return "doc"
        }
    }
    
    /// Recents can point at files that have since moved or been deleted.
    /// Marking them rather than hiding them keeps the list stable — a file on
    /// an unmounted drive shouldn't silently vanish from history.
    private var isReachable: Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: SMI.Spacing.small) {
                Image(systemName: isReachable ? fileIcon : "questionmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(
                        isReachable
                        ? Color.brandViolet.opacity(0.8)
                        : Color.secondary.opacity(0.5)
                    )
                    .frame(width: 18)
                
                Text(url.lastPathComponent)
                    .font(SMI.Typo.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isReachable ? .primary : .secondary)
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SMI.Spacing.medium - 2)
            .padding(.vertical, SMI.Spacing.snug + 1)
            .background(
                RoundedRectangle(cornerRadius: SMI.Radius.control, style: .continuous)
                    .fill(
                        hovered
                        ? Color.brandViolet.opacity(0.12)
                        : Color.primary.opacity(0.05)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: SMI.Radius.control, style: .continuous)
                            .strokeBorder(
                                Color.brandViolet.opacity(hovered ? 0.30 : 0.10),
                                lineWidth: 0.7
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle(scale: 0.98))
        .onHover { hovered = $0 }
        .smiAnimation(SMI.Motion.fade, value: hovered)
        .help(isReachable ? url.lastPathComponent : "\(url.lastPathComponent) — not currently available")
        // PHASE 11. A missing file is currently marked by a question-mark glyph
        // and grey text, and neither of those is audible. The state goes into
        // the spoken value instead, so the chip says why it will not open.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(url.lastPathComponent)
        .accessibilityValue(isReachable ? "" : "Not currently available")
        .accessibilityHint(isReachable ? "Opens this file" : "This file has moved or been deleted")
        .accessibilityAddTraits(.isButton)
        // Phase 8b. Rename and Move to Trash are deliberately absent: a chip
        // points at a file that is usually *not* the one on screen, and a
        // destructive action two rows below "Open" in a list of history is a
        // mis-click waiting to happen. Removing the entry is offered instead,
        // which affects the list and not the disk.
        .contextMenu {
            FileActionsMenuItems(
                store: store,
                url: url,
                isCompare: false,
                excluding: [.rename, .trash]
            )
            
            Divider()
            
            Button(role: .destructive) {
                store.removeFromRecents(url)
            } label: {
                Label("Remove from Recents", systemImage: "xmark.circle")
            }
        }
    }
}
