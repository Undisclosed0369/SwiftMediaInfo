//
//  CompareView.swift
//  SwiftMediaInfo
//
//  Compare Mode: the summary panel and checksum verdict on top, then File A
//  and File B side by side — each pane with its header (the file name with
//  a menu to pick another, reload, close), checksum card and the current
//  view — and the chooser an empty side offers.
//
//  File A is the selected tab and File B another tab (MediaStore); the
//  comparison is MediaComparison, rebuilt by the store. The rest of Compare
//  Mode has files of its own: DiffEasyView and DiffRawTextView (the panes
//  with differences highlighted), ComparisonSummaryPanel, SwapFilesButton
//  and CompareDrop.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct CompareView: View {
    @EnvironmentObject var store: MediaStore
    /// 0 at rest, 1 at the midpoint of a swap. Both panes read it, which is
    /// what guarantees they move together.
    @State private var swapProgress: CGFloat = 0
    
    // One stable delegate per pane, created once and reused for the lifetime
    // of the view. See PaneDropCoordinator for why identity matters here.
    @State private var leftDrop  = PaneDropCoordinator(paneTarget: .fileA)
    @State private var rightDrop = PaneDropCoordinator(paneTarget: .fileB)
    
    // Highlights come from two sources: SwiftUI's own drag tracking for the
    // pure-SwiftUI panes (Easy View), and the AppKit panes — text views and the
    // web view — which intercept drags before SwiftUI sees them and report the
    // resolved zone through the store.
    // Every highlight is gated on an active drag session as well as the
    // target. Without that gate a highlight could outlive the drop that set
    // it — which it did: dropping into File B left the pink outline showing
    // afterwards.
    private var showLeftHighlight: Bool {
        store.isDragSessionActive && store.externalDropTarget == .fileA
    }
    
    private var showRightHighlight: Bool {
        store.isDragSessionActive && store.externalDropTarget == .fileB
    }
    
    private var showCentreHighlight: Bool {
        store.isDragSessionActive && store.externalDropTarget == .newFile
    }
    
    /// The centre card is shown for the whole drag, not only when the cursor
    /// nears the middle — an interaction nobody can see is one nobody uses.
    private var showCentreCard: Bool {
        store.isDragSessionActive && store.isCentreDropAvailable
    }
    
    /// Diff is only supported in easy, text, rawText
    private var diffSupported: Bool {
        [.easy, .text, .rawText].contains(store.viewMode)
    }

    private func bothSidesHave(_ condition: (MediaFile) -> Bool) -> Bool {
        guard let fileA = store.currentFile, let fileB = store.compareFile else { return false }
        return condition(fileA) && condition(fileB)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ── Diff toggle bar (only when both files loaded & mode supports diff) ──
            //
            // Gated on content rather than on the files' loading flags:
            // formats arrive one at a time, so "finished analysing" no longer
            // means "this tab can be diffed".
            if diffSupported && bothSidesHave({ $0.hasContent(for: store.viewMode) }) {
                diffToggleBar
            }

            // ── Comparison summary ────────────────────────────────
            // Built from tracks, so it waits for both JSON results whichever
            // tab is showing.
            if diffSupported && bothSidesHave({ !$0.tracks.isEmpty }) {
                ComparisonSummaryPanel()
            }
            
            // ── Checksum verdict ───────────────────────────────────
            //
            // Above the panes rather than beside the hashes, because "are
            // these the same file?" is the question a checksum exists to
            // answer, and a 64-character string in each pane makes the reader
            // do the comparison by eye. Only shown once both sides have a
            // digest — a verdict from one hash would be a guess.
            checksumVerdict
            
            HStack(spacing: 0) {
                
                // ── Left pane: File A ─────────────────────────────────
                ZStack {
                    VStack(spacing: 0) {
                        paneHeader(file: store.currentFile, label: "File A", isLeft: true)
                        Divider()
                        paneContent(file: store.currentFile, isCompare: false)
                    }
                    if showLeftHighlight {
                        GlassDropOverlay(
                            color: FileDropTarget.fileA.tint,
                            message: FileDropTarget.fileA.message
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { leftDrop.paneSize = proxy.size }
                            .onChange(of: proxy.size) { _, new in
                                leftDrop.paneSize = new
                            }
                    }
                )
                .opacity(showCentreHighlight ? 0.4 : 1)
                .modifier(SwapMotion(progress: swapProgress, isLeftPane: true))
                .onDrop(of: [.fileURL], delegate: leftDrop)
                .smiAnimation(SMI.Motion.snap, value: showLeftHighlight)
                .smiAnimation(SMI.Motion.fade, value: showCentreHighlight)
                
                Divider()
                
                // ── Right pane: File B ────────────────────────────────
                ZStack {
                    VStack(spacing: 0) {
                        paneHeader(file: store.compareFile, label: "File B", isLeft: false)
                        Divider()
                        paneContent(file: store.compareFile, isCompare: true)
                    }
                    if showRightHighlight {
                        GlassDropOverlay(
                            color: FileDropTarget.fileB.tint,
                            message: FileDropTarget.fileB.message
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { rightDrop.paneSize = proxy.size }
                            .onChange(of: proxy.size) { _, new in
                                rightDrop.paneSize = new
                            }
                    }
                )
                .opacity(showCentreHighlight ? 0.4 : 1)
                .modifier(SwapMotion(progress: swapProgress, isLeftPane: false))
                .onDrop(of: [.fileURL], delegate: rightDrop)
                .smiAnimation(SMI.Motion.snap, value: showRightHighlight)
                .smiAnimation(SMI.Motion.fade, value: showCentreHighlight)
            }
            // Purely decorative — hit testing is disabled so the panes
            // underneath keep resolving the drag themselves. The card's size
            // comes from the same constants the panes use to classify a point,
            // so what you see and what you hit are the same rectangle.
            .overlay {
                if showCentreCard {
                    CentreDropCard(isHighlighted: showCentreHighlight)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                } else if store.currentFile != nil && store.compareFile != nil {
                    // Sits on the divider, belonging to neither pane — the same
                    // logic as the centre drop card, which is why the two share
                    // the position and never appear together.
                    SwapFilesButton()
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .smiAnimation(SMI.Motion.flourish, value: showCentreCard)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            leftDrop.store  = store
            rightDrop.store = store
        }
        // Both panes dip and cross, then settle. Driven from the store's swap
        // token rather than from the file values, so neither pane can be left
        // out because SwiftUI happened to rebuild it.
        .onChange(of: store.swapToken) { _, _ in
            withAnimation(.easeIn(duration: 0.13)) {
                swapProgress = 1
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 130_000_000)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    swapProgress = 0
                }
            }
        }
        .onDisappear {
            // Leaving Compare Mode with a highlight still set would carry it
            // into a layout where it means nothing.
            store.resetDropState()
        }
        .onChange(of: store.viewMode) { _, newMode in
            store.loadFormatIfNeeded(newMode, isCompare: false)
            store.loadFormatIfNeeded(newMode, isCompare: true)
        }
        // Replacing a file while already sitting on a lazy tab produced no tab
        // change, so nothing triggered the fetch and the pane sat on its Load
        // button. Watching the file identities covers dropping, re-picking, and
        // the Finder handoff alike.
        .onChange(of: store.currentFile?.id) { _, _ in
            store.loadFormatIfNeeded(store.viewMode, isCompare: false)
        }
        .onChange(of: store.compareFile?.id) { _, _ in
            store.loadFormatIfNeeded(store.viewMode, isCompare: true)
        }
        // An on-demand format can only be requested once the initial parallel
        // analysis has finished, so retry when each side completes.
        .onChange(of: store.currentFile?.isLoading) { _, isLoading in
            if isLoading == false {
                store.loadFormatIfNeeded(store.viewMode, isCompare: false)
            }
        }
        .onChange(of: store.compareFile?.isLoading) { _, isLoading in
            if isLoading == false {
                store.loadFormatIfNeeded(store.viewMode, isCompare: true)
            }
        }
    }
    
    // MARK: - Diff toggle bar
    
    // MARK: - Checksum verdict
    
    @ViewBuilder
    private var checksumVerdict: some View {
        if let a = store.currentFile?.hashState.digest,
           let b = store.compareFile?.hashState.digest {
            
            let identical = a == b
            let tint: Color = identical ? SMI.Palette.success : SMI.Palette.danger
            
            HStack(spacing: SMI.Spacing.medium) {
                Image(systemName: identical ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(tint)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(identical ? "Identical files" : "Different files")
                        .font(SMI.Typo.callout.weight(.semibold))
                        .foregroundStyle(tint)
                    
                    Text(identical
                         ? "Both files have the same SHA-256 checksum, so they are byte-for-byte the same."
                         : "The SHA-256 checksums differ, so the contents are not the same — even if every field above matches.")
                    .font(SMI.Typo.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.10))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(tint.opacity(0.30))
                    .frame(height: 0.8)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
    
    private var diffToggleBar: some View {
        HStack(spacing: 10) {
            Spacer()
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    store.showDiffHighlight.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: store.showDiffHighlight
                          ? "square.split.2x1.fill"
                          : "square.split.2x1")
                    .font(.system(size: 12, weight: .medium))
                    Text(store.showDiffHighlight ? "Highlighting Differences" : "Highlight Differences")
                        .font(.system(size: 11, weight: .semibold))
                    Text("⌘D")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(store.showDiffHighlight ? Color.brandViolet : Color.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(store.showDiffHighlight
                              ? Color.brandViolet.opacity(0.12)
                              : Color.primary.opacity(0.04))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(store.showDiffHighlight
                                      ? Color.brandViolet.opacity(0.3)
                                      : Color.primary.opacity(0.08),
                                      lineWidth: 0.7)
                )
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: store.showDiffHighlight)
            
            // Legend (only when diff is active)
            if store.showDiffHighlight {
                HStack(spacing: 12) {
                    diffLegendItem(color: SMI.Palette.diffModified, label: "Modified")
                    diffLegendItem(color: SMI.Palette.diffOnlyInA, label: "Only in A")
                    diffLegendItem(color: SMI.Palette.diffOnlyInB, label: "Only in B")
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
    
    private func diffLegendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
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
                MarqueeText(text: file.fileName, size: 12, weight: .medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !file.isLoading {
                    Text(file.fileSizeString)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            } else {
                // The pane below lists what can fill this side.
                Text("Not chosen yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if file != nil {
                // Replace this side: an open tab, a recent file, or any file.
                Menu {
                    sideChoices(isLeft: isLeft)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                        .foregroundStyle(accent)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(isLeft ? "Choose a different File A" : "Choose a different File B")
                
                // Close this side. Its tab closes; the other side stays
                // and the empty pane waits for a replacement.
                PaneCloseButton(accent: accent, label: label) {
                    smiWithAnimation(SMI.Motion.smooth) {
                        if isLeft, let id = store.selectedTabID {
                            store.closeTab(id)
                        } else if !isLeft, let id = store.compareTabID {
                            store.closeTab(id)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        // The header is where the file's identity lives in this
        // layout, so it is the obvious thing to right-click. `isCompare` is
        // the pane, not the mode: the right-hand pane is File B.
        .contextMenu {
            if let file = file {
                FileActionsMenuItems(
                    store: store,
                    url: file.url,
                    isCompare: !isLeft
                )
            }
        }
    }
    
    /// Open tabs that could fill a side: anything not already on screen.
    private func candidates(isLeft: Bool) -> [DocumentTab] {
        store.tabs.filter { $0.id != store.selectedTabID && $0.id != store.compareTabID }
    }
    
    /// The same sources the tab menu's Compare With offers, routed to
    /// whichever side this is.
    private func sideChoices(isLeft: Bool) -> some View {
        CompareChoices(
            store: store,
            tabs: candidates(isLeft: isLeft),
            onTab: { id in
                if isLeft { store.selectTab(id) } else { store.compare(withTab: id) }
            },
            onFile: { url in
                if isLeft { store.openURL(url) } else { store.openCompareURL(url) }
            },
            onChooseFile: {
                if isLeft { store.openFilePicker() } else { store.openCompareFilePicker() }
            }
        )
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
                
            } else {
                resolvedContent(file: file, isCompare: isCompare)
            }
        } else {
            // An empty side offers what could fill it, rather than
            // just saying it is empty.
            CompareSlotChooser(isFileB: isCompare)
        }
    }
    
    // MARK: - Route to the right view
    
    @ViewBuilder
    private func resolvedContent(file: MediaFile, isCompare: Bool) -> some View {
        VStack(spacing: 0) {
            // Per pane, so each side reports its own checksum.
            ChecksumCard(isCompare: isCompare)
                .padding(.horizontal, 12)
                .padding(.top, 12)
            
            resolvedTabContent(file: file, isCompare: isCompare)
        }
    }
    
    @ViewBuilder
    private func resolvedTabContent(file: MediaFile, isCompare: Bool) -> some View {
        let isSearchActive = store.showSearchBar && !store.searchQuery.isEmpty
        let isDiffActive = store.showDiffHighlight && store.currentFile != nil && store.compareFile != nil
        
        switch store.viewMode {
            
        case .easy:
            if file.tracks.isEmpty && file.isLoadingJSON {
                lazyPlaceholder(label: "Easy", isLoading: true, color: .brandBlue) {}
            } else if isDiffActive,
                      // A side whose tracks have not arrived would make every
                      // field look "only in" the other file.
                      !((isCompare ? store.currentFile : store.compareFile)?.tracks.isEmpty ?? true) {
                // Diff view — search highlights overlay via FieldCell's highlightQuery
                DiffEasyView(file: file, isFileB: isCompare)
            } else if isSearchActive {
                FilterableEasyView(file: file)
            } else {
                EasyView(file: file)
            }
            
        case .text:
            if let content = file.rawText {
                if isDiffActive,
                   let otherContent = (isCompare ? store.currentFile : store.compareFile)?.rawText {
                    // Diff view — search highlights overlay on top of diff colors
                    DiffRawTextView(content: content, otherContent: otherContent, isFileB: isCompare)
                } else if isSearchActive {
                    FilterableRawTextView(content: content, dropTarget: isCompare ? .fileB : .fileA)
                } else {
                    RawTextView(content: content, dropTarget: isCompare ? .fileB : .fileA)
                }
            } else {
                lazyPlaceholder(label: "Text", isLoading: file.isLoadingText, color: .brandViolet) {
                    store.loadFormatIfNeeded(.text, isCompare: isCompare)
                }
            }
            
        case .rawText:
            if let content = file.rawTextFull {
                if isDiffActive,
                   let otherContent = (isCompare ? store.currentFile : store.compareFile)?.rawTextFull {
                    DiffRawTextView(content: content, otherContent: otherContent, isFileB: isCompare)
                } else if isSearchActive {
                    FilterableRawTextView(content: content, dropTarget: isCompare ? .fileB : .fileA)
                } else {
                    RawTextView(content: content, dropTarget: isCompare ? .fileB : .fileA)
                }
            } else {
                lazyPlaceholder(label: "Raw Text", isLoading: file.isLoadingRawText, color: .brandPink) {
                    store.loadFormatIfNeeded(.rawText, isCompare: isCompare)
                }
            }
            
        case .html:
            if let content = file.rawHTML {
                HTMLView(htmlString: content, dropTarget: isCompare ? .fileB : .fileA)
            } else {
                lazyPlaceholder(label: "HTML", isLoading: file.isLoadingHTML, color: .brandGreen) {
                    store.loadFormatIfNeeded(.html, isCompare: isCompare)
                }
            }
            
        case .xml:
            if let content = file.rawXML {
                if isSearchActive {
                    FilterableRawTextView(content: content, dropTarget: isCompare ? .fileB : .fileA, language: .xml)
                } else {
                    RawTextView(content: content, dropTarget: isCompare ? .fileB : .fileA, language: .xml)
                }
            } else {
                lazyPlaceholder(label: "XML", isLoading: file.isLoadingXML, color: .brandBlue) {
                    store.loadFormatIfNeeded(.xml, isCompare: isCompare)
                }
            }
            
        case .json:
            if let content = file.rawJSON {
                if isSearchActive {
                    FilterableRawTextView(content: content, dropTarget: isCompare ? .fileB : .fileA, language: .json)
                } else {
                    RawTextView(content: content, dropTarget: isCompare ? .fileB : .fileA, language: .json)
                }
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

// MARK: - Empty side

/// What an empty File A or File B pane shows: the open tabs, favorites and
/// recent files that could fill it, a file picker, and the reminder that
/// dropping works.
private struct CompareSlotChooser: View {
    let isFileB: Bool
    @EnvironmentObject var store: MediaStore
    
    private var accent: Color { isFileB ? .brandPink : .brandBlue }
    private var side: String { isFileB ? "File B" : "File A" }
    
    /// Anything not already on screen.
    private var openTabs: [DocumentTab] {
        store.tabs.filter { $0.id != store.selectedTabID && $0.id != store.compareTabID }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: SMI.Spacing.xLarge) {
                VStack(spacing: SMI.Spacing.small) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(accent.opacity(0.6))
                    Text("Choose \(side)")
                        .font(SMI.Typo.title)
                    Text("Pick an open tab, a favorite or a recent file, or drop a file here.")
                        .font(SMI.Typo.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                if !openTabs.isEmpty {
                    section("Open Tabs", icon: "rectangle.stack") {
                        ForEach(openTabs) { tab in
                            SlotChip(
                                icon: FileTabBar.symbol(for: tab.file.url),
                                title: tab.file.fileName,
                                accent: accent
                            ) {
                                if isFileB { store.compare(withTab: tab.id) } else { store.selectTab(tab.id) }
                            }
                        }
                    }
                }
                
                let favorites = store.favoriteCompareCandidates
                if !favorites.isEmpty {
                    section("Favorites", icon: "star") {
                        FoldingSlotChips(urls: favorites, icon: { _ in "star.fill" }, accent: accent, action: open)
                    }
                }
                
                let recents = store.recentCompareCandidates
                if !recents.isEmpty {
                    section("Recent Files", icon: "clock.arrow.circlepath") {
                        FoldingSlotChips(urls: recents, icon: { FileTabBar.symbol(for: $0) }, accent: accent, action: open)
                    }
                }
                
                Button(isFileB ? "Choose File B…" : "Choose File A…") {
                    if isFileB { store.openCompareFilePicker() } else { store.openFilePicker() }
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.large)
            }
            .padding(SMI.Spacing.xLarge)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }
    
    /// A favorite or recent file, into this side.
    private func open(_ url: URL) {
        if isFileB { store.openCompareURL(url) } else { store.openURL(url) }
    }
    
    private func section<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SMI.Spacing.small) {
            GlassSectionHeader(title: title, icon: icon)
            VStack(spacing: SMI.Spacing.tight) {
                content()
            }
        }
    }
}

/// A list's first few files, then "N More", which shows the rest as soon
/// as the pointer reaches it (or on a click).
private struct FoldingSlotChips: View {
    let urls: [URL]
    let icon: (URL) -> String
    let accent: Color
    let action: (URL) -> Void
    @State private var isExpanded = false

    var body: some View {
        let shown = isExpanded ? urls : Array(urls.prefix(ListFolding.shownCount))
        ForEach(shown, id: \.self) { url in
            SlotChip(icon: icon(url), title: url.lastPathComponent, accent: accent) { action(url) }
        }
        if !isExpanded, urls.count > ListFolding.shownCount {
            SlotChip(
                icon: "chevron.down",
                title: "\(urls.count - ListFolding.shownCount) More",
                accent: accent,
                action: expand,
                onHoverStart: expand
            )
        }
    }

    private func expand() {
        smiWithAnimation(SMI.Motion.smooth) { isExpanded = true }
    }
}

/// One choice in an empty pane: icon, name, the side's colour on hover.
private struct SlotChip: View {
    let icon: String
    let title: String
    let accent: Color
    let action: () -> Void
    /// For a chip that acts as soon as the pointer reaches it.
    var onHoverStart: (() -> Void)? = nil
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: SMI.Spacing.small) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(accent.opacity(0.85))
                    .frame(width: 18)
                Text(title)
                    .font(SMI.Typo.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SMI.Spacing.medium - 2)
            .padding(.vertical, SMI.Spacing.snug + 1)
            .background(
                RoundedRectangle(cornerRadius: SMI.Radius.control, style: .continuous)
                    .fill(isHovering ? accent.opacity(0.14) : Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: SMI.Radius.control, style: .continuous)
                            .strokeBorder(accent.opacity(isHovering ? 0.35 : 0.12), lineWidth: 0.7)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle(scale: 0.98))
        .onHover { hovering in
            isHovering = hovering
            if hovering { onHoverStart?() }
        }
        .smiAnimation(SMI.Motion.fade, value: isHovering)
        .help(title)
    }
}

// MARK: - Pane close button

/// A small × in a pane header, in that side's colour.
private struct PaneCloseButton: View {
    let accent: Color
    let label: String
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isHovering ? accent : accent.opacity(0.75))
                .frame(width: 20, height: 20)
                .background(Circle().fill(isHovering ? accent.opacity(0.15) : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .smiAnimation(SMI.Motion.fade, value: isHovering)
        .help("Close \(label)")
        .accessibilityLabel("Close \(label)")
    }
}
