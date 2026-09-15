//
//  CompareView.swift
//  SwiftMediaInfo
//
//  PHASE 3b — targeted refinement only.
//
//  DiffTrackCard now uses GlassCard, so turning on Highlight Differences no
//  longer drops Compare Mode out of the glass treatment. Track colours and
//  legend swatches read from SMI.Palette, and card headers scale with zoom.
//
//  The comparison logic itself is untouched — that is Phase 7's job.
//
//  PHASE 5 — MarqueeText rewritten; see the notes above that type.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct CompareView: View {
    @EnvironmentObject var store: MediaStore
    /// 0 at rest, 1 at the midpoint of a swap. Both panes read it, which is
    /// what guarantees they move together.
    @State private var swapProgress: CGFloat = 0
    
    @State private var leftPaneSize:  CGSize = .zero
    @State private var rightPaneSize: CGSize = .zero
    
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
    
    var body: some View {
        VStack(spacing: 0) {
            // ── Diff toggle bar (only when both files loaded & mode supports diff) ──
            if diffSupported &&
                store.currentFile != nil && store.compareFile != nil &&
                !(store.currentFile?.isLoading ?? true) &&
                !(store.compareFile?.isLoading ?? true) {
                diffToggleBar
            }
            
            // ── Comparison summary ────────────────────────────────
            if diffSupported,
               store.currentFile != nil, store.compareFile != nil,
               !(store.currentFile?.isLoading ?? true),
               !(store.compareFile?.isLoading ?? true) {
                ComparisonSummaryPanel()
            }
            
            // ── Checksum verdict (Phase 10) ───────────────────────
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
                            .onAppear { leftPaneSize = proxy.size; leftDrop.paneSize = proxy.size }
                            .onChange(of: proxy.size) { _, new in
                                leftPaneSize = new
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
                            .onAppear { rightPaneSize = proxy.size; rightDrop.paneSize = proxy.size }
                            .onChange(of: proxy.size) { _, new in
                                rightPaneSize = new
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
        // Phase 8b. The header is where the file's identity lives in this
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
        VStack(spacing: 0) {
            // PHASE 10 — per pane, so each side reports its own checksum.
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
            if isDiffActive {
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
                    FilterableRawTextView(content: content, dropTarget: isCompare ? .fileB : .fileA)
                } else {
                    RawTextView(content: content, dropTarget: isCompare ? .fileB : .fileA)
                }
            } else {
                lazyPlaceholder(label: "XML", isLoading: file.isLoadingXML, color: .brandBlue) {
                    store.loadFormatIfNeeded(.xml, isCompare: isCompare)
                }
            }
            
        case .json:
            if let content = file.rawJSON {
                if isSearchActive {
                    FilterableRawTextView(content: content, dropTarget: isCompare ? .fileB : .fileA)
                } else {
                    RawTextView(content: content, dropTarget: isCompare ? .fileB : .fileA)
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

// MARK: - Diff Easy View (colour-coded field comparison — easy fields only)

struct DiffEasyView: View {
    let file: MediaFile
    let isFileB: Bool
    @EnvironmentObject var store: MediaStore
    
    /// Build diff-annotated fields using ONLY the easy field keys (same subset EasyView shows)
    /// Reads the shared comparison rather than computing its own.
    ///
    /// Both panes now render the same union of fields in the same order, so a
    /// row in the left pane lines up with the same row on the right. That is
    /// what makes side-by-side scrolling actually comparable, and it is also
    /// how a field missing from one file becomes visible on the side that
    /// lacks it — previously there was simply no row there to mark.
    private var trackComparisons: [MediaComparison.TrackComparison] {
        store.comparison.tracks
    }
    
    /// Matches across both panes, counted the same way FilterableEasyView does
    /// so the search bar's figure means the same thing in every mode.
    ///
    /// Both sides are counted because both are on screen. Only the left pane
    /// publishes the result — otherwise the two panes would each write it and
    /// the last one to render would win, which is a race rather than a total.
    private var searchMatchTotal: Int {
        let query = store.searchQuery.lowercased()
        guard !query.isEmpty else { return 0 }
        
        var count = 0
        for track in store.comparison.tracks {
            for field in track.fields {
                let label = FieldFormat.friendlyLabel(field.key)
                count += FieldFormat.occurrences(of: query, in: label) * 2
                count += FieldFormat.occurrences(of: query, in: field.valueA ?? "")
                count += FieldFormat.occurrences(of: query, in: field.valueB ?? "")
            }
        }
        return count
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SMI.Spacing.large) {
                    ForEach(trackComparisons) { comparison in
                        DiffTrackCard(
                            comparison: comparison,
                            isFileB: isFileB,
                            isFocused: store.focusedComparisonTrackID == comparison.id
                        )
                        .id(comparison.id)
                    }
                }
                .padding(SMI.Spacing.xLarge)
            }
            // Both panes watch the same id, so picking a track in the summary
            // brings it into view on both sides at once — which is the only way
            // a side-by-side comparison is useful.
            .onChange(of: store.focusedComparisonTrackID) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(id, anchor: .top)
                }
            }
            // The search bar's counter is fed by FilterableEasyView, which
            // isn't on screen in Compare Mode with diffing on — so searching
            // here reported "no matches" while visibly highlighting them.
            .onAppear {
                guard !isFileB else { return }
                store.searchMatchCount = searchMatchTotal
            }
            .onChange(of: searchMatchTotal) { _, newValue in
                guard !isFileB else { return }
                store.searchMatchCount = newValue
                if newValue > 0 && store.searchMatchIndex >= newValue {
                    store.searchMatchIndex = 0
                }
            }
        }
    }
}

// MARK: - Diff Track Card

struct DiffTrackCard: View {
    let comparison: MediaComparison.TrackComparison
    let isFileB: Bool
    /// Briefly true after the card is chosen in the summary.
    var isFocused: Bool = false
    
    @EnvironmentObject var store: MediaStore
    @State private var isExpanded = true
    @State private var isHeaderHovered = false
    
    private var trackColor: Color { SMI.Palette.track(comparison.type) }
    
    var body: some View {
        GlassCard(tint: trackColor, isExpanded: isExpanded) {
            header
        } content: {
            fieldGrid
        }
        // A brief ring rather than a permanent selection: scrolling to a card
        // answers "where is it", and a highlight that stayed would then have to
        // be dismissed, which is a second job the user didn't ask for.
        .overlay(
            RoundedRectangle(cornerRadius: SMI.Radius.card, style: .continuous)
                .strokeBorder(Color.brandViolet.opacity(isFocused ? 0.85 : 0), lineWidth: 2)
        )
        .smiAnimation(SMI.Motion.fade, value: isFocused)
    }
    
    // MARK: Header
    
    private var header: some View {
        Button {
            smiWithAnimation(SMI.Motion.smooth) { isExpanded.toggle() }
        } label: {
            HStack(spacing: SMI.Spacing.medium - 2) {
                Image(systemName: comparison.icon)
                    .font(.system(size: CGFloat(store.fontSize) + 2, weight: .semibold))
                    .foregroundStyle(trackColor)
                    .frame(width: CGFloat(store.fontSize) + 8)
                
                Text(comparison.displayTitle)
                    .font(.system(size: CGFloat(store.fontSize) + 2, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                if comparison.changeCount > 0 {
                    GlassBadge(
                        text: "\(comparison.changeCount) diff\(comparison.changeCount == 1 ? "" : "s")",
                        tint: SMI.Palette.diffModified,
                        filled: true,
                        scale: store.fontSize
                    )
                }
                
                // A track missing entirely from one side is worth saying out
                // loud, rather than leaving the reader to notice every row is
                // a placeholder.
                if comparison.trackA == nil || comparison.trackB == nil {
                    GlassBadge(
                        text: comparison.trackA == nil ? "B only" : "A only",
                        tint: comparison.trackA == nil
                        ? SMI.Palette.diffOnlyInB
                        : SMI.Palette.diffOnlyInA,
                        filled: false,
                        scale: store.fontSize
                    )
                }
                
                Spacer(minLength: SMI.Spacing.small)
                
                Image(systemName: "chevron.down")
                    .font(.system(size: CGFloat(store.fontSize) - 2, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .smiAnimation(SMI.Motion.snap, value: isExpanded)
            }
            .padding(.horizontal, SMI.Spacing.large)
            .padding(.vertical, SMI.Spacing.medium)
            .background(isHeaderHovered ? SMI.Palette.hoverWash : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHeaderHovered = $0 }
        .smiAnimation(SMI.Motion.fade, value: isHeaderHovered)
        .contextMenu {
            if let track = isFileB ? comparison.trackB : comparison.trackA {
                Button("Copy Track") {
                    store.copyTrack(
                        track,
                        from: (isFileB ? store.compareFile : store.currentFile)?.url
                    )
                }
            }
        }
    }
    
    // MARK: Field grid
    
    private var fieldGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 160), spacing: 0),
                GridItem(.flexible(minimum: 200), spacing: 0)
            ],
            alignment: .leading,
            spacing: 0
        ) {
            ForEach(Array(comparison.fields.enumerated()), id: \.element.id) { index, field in
                FieldCell(
                    key: FieldFormat.friendlyLabel(field.key),
                    // An em dash rather than an empty cell: a blank row is
                    // ambiguous between "absent" and "empty value", and the
                    // difference matters when comparing encodes.
                    value: field.value(isFileB: isFileB) ?? "—",
                    rowIndex: index / 2,
                    highlightQuery: store.showSearchBar ? store.searchQuery : "",
                    diffState: field.displayState,
                    rawKey: field.key,
                    fileURL: (isFileB ? store.compareFile : store.currentFile)?.url
                )
            }
        }
        .padding(.bottom, SMI.Spacing.hair)
    }
}

// MARK: - Diff Raw Text View (line-by-line diff for text/rawText modes)

struct DiffRawTextView: NSViewRepresentable {
    let content: String
    let otherContent: String
    let isFileB: Bool
    @EnvironmentObject var store: MediaStore
    
    private var dropTarget: FileDropTarget { isFileB ? .fileB : .fileA }
    
    class Coordinator {
        var lastContent: String = ""
        var lastOtherContent: String = ""
        var lastFontSize: Double = 0
        var lastQuery: String = ""
        var lastIndex: Int = -1
        /// The track this pane has already scrolled to, so a focus request is
        /// acted on once rather than on every subsequent update.
        var lastFocusedID: String? = nil
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = FileDropScrollView.make(richText: true)
        scrollView.configureDrop(target: dropTarget, store: store)
        return scrollView
    }
    
    /// Scrolls a track's heading into view and flashes it.
    ///
    /// The heading is placed near the top rather than merely made visible: a
    /// section scrolled to the bottom edge is technically on screen and useless,
    /// since everything belonging to it is still below the fold.
    ///
    /// `showFindIndicator` is AppKit's own highlight — the same animated badge
    /// Find uses. Native, self-dismissing, and nothing to clean up afterwards.
    private static func reveal(trackID: String, in textView: NSTextView, text: String) {
        guard let range = MediaComparison.range(ofTrackID: trackID, in: text),
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }
        
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: range,
            actualCharacterRange: nil
        )
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        rect.origin.y -= textView.textContainerInset.height
        
        // Leave a little room above so the heading isn't flush against the edge.
        let target = NSRect(
            x: 0,
            y: max(rect.minY - 12, 0),
            width: 1,
            height: textView.enclosingScrollView?.contentSize.height ?? rect.height
        )
        
        textView.scrollToVisible(target)
        textView.showFindIndicator(for: range)
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = FileDropScrollView.textView(in: scrollView) else { return }
        
        (scrollView as? FileDropScrollView)?.configureDrop(target: dropTarget, store: store)
        
        let coord = context.coordinator
        let query = store.showSearchBar ? store.searchQuery : ""
        let fontSize = store.fontSize
        
        // Handled before the change guard below, because a focus request on its
        // own changes none of the values that guard tests — the text is already
        // correct, it just isn't on screen.
        if let focusID = store.focusedComparisonTrackID {
            if coord.lastFocusedID != focusID {
                coord.lastFocusedID = focusID
                let text = content
                DispatchQueue.main.async {
                    Self.reveal(trackID: focusID, in: textView, text: text)
                }
            }
        } else {
            coord.lastFocusedID = nil
        }
        
        let contentChanged = coord.lastContent != content || coord.lastOtherContent != otherContent
        let fontChanged = coord.lastFontSize != fontSize
        let queryChanged = coord.lastQuery != query
        let indexChanged = coord.lastIndex != store.searchMatchIndex
        
        guard contentChanged || fontChanged || queryChanged || indexChanged else { return }
        
        let needsFullRebuild = contentChanged || fontChanged || queryChanged
        
        if needsFullRebuild {
            coord.lastContent = content
            coord.lastOtherContent = otherContent
            coord.lastFontSize = fontSize
            coord.lastQuery = query
        }
        
        let font = NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        
        let myLines    = content.components(separatedBy: "\n")
        let otherLines = otherContent.components(separatedBy: "\n")
        let otherLineSet = Set(otherLines)
        
        let attrStr = NSMutableAttributedString()
        
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        
        let modifiedBg    = NSColor(Color.orange.opacity(0.12))
        let modifiedFg    = NSColor(Color(red: 0.85, green: 0.50, blue: 0.10))
        let onlyInThisBg  = NSColor((isFileB ? Color.brandPink : Color.brandBlue).opacity(0.10))
        let onlyInThisFg  = NSColor(isFileB ? Color.brandPink : Color.brandBlue)
        
        for (i, line) in myLines.enumerated() {
            let lineText = line + (i < myLines.count - 1 ? "\n" : "")
            
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                attrStr.append(NSAttributedString(string: lineText, attributes: normalAttrs))
            } else if !otherLineSet.contains(line) {
                let isModified = i < otherLines.count && DiffHelper.sameKey(line, otherLines[i])
                
                if isModified {
                    var attrs = normalAttrs
                    attrs[.backgroundColor] = modifiedBg
                    attrs[.foregroundColor] = modifiedFg
                    attrStr.append(NSAttributedString(string: lineText, attributes: attrs))
                } else {
                    var attrs = normalAttrs
                    attrs[.backgroundColor] = onlyInThisBg
                    attrs[.foregroundColor] = onlyInThisFg
                    attrStr.append(NSAttributedString(string: lineText, attributes: attrs))
                }
            } else {
                attrStr.append(NSAttributedString(string: lineText, attributes: normalAttrs))
            }
        }
        
        // Overlay search highlights on top of diff colors
        var searchRanges: [NSRange] = []
        if !query.isEmpty {
            let fullText = attrStr.string
            
            // Try exact match first
            searchRanges = findNSRangesInContent(of: query, in: fullText)
            
            // If no exact matches, try space-normalized
            if searchRanges.isEmpty {
                let qNorm = query.lowercased().replacingOccurrences(of: " ", with: "")
                let lower = fullText.lowercased()
                var indexMap: [Int] = []
                for (i, char) in lower.enumerated() {
                    if char != " " { indexMap.append(i) }
                }
                let normalized = lower.replacingOccurrences(of: " ", with: "")
                let nsNorm = normalized as NSString
                var sr = NSRange(location: 0, length: nsNorm.length)
                
                while sr.location < nsNorm.length {
                    let found = nsNorm.range(of: qNorm, options: [], range: sr)
                    if found.location == NSNotFound { break }
                    let origStart = found.location < indexMap.count ? indexMap[found.location] : found.location
                    let origEndIdx = found.location + found.length - 1
                    let origEnd = origEndIdx < indexMap.count ? indexMap[origEndIdx] + 1 : origStart + found.length
                    searchRanges.append(NSRange(location: origStart, length: origEnd - origStart))
                    sr.location = found.location + found.length
                    sr.length = nsNorm.length - sr.location
                }
            }
            
            let highlightBg = NSColor(Color.brandGreen.opacity(0.3))
            let activeBg    = NSColor(Color.brandGreen.opacity(0.6))
            
            for (idx, range) in searchRanges.enumerated() {
                if idx == store.searchMatchIndex {
                    attrStr.addAttribute(.backgroundColor, value: activeBg, range: range)
                } else {
                    attrStr.addAttribute(.backgroundColor, value: highlightBg, range: range)
                }
            }
            
            if queryChanged {
                DispatchQueue.main.async {
                    self.store.searchMatchCount = searchRanges.count
                }
            }
        }
        
        textView.textStorage?.setAttributedString(attrStr)
        
        // Only scroll when index actually changed
        if indexChanged {
            coord.lastIndex = store.searchMatchIndex
            if !searchRanges.isEmpty && store.searchMatchIndex < searchRanges.count {
                textView.scrollRangeToVisible(searchRanges[store.searchMatchIndex])
            }
        }
    }
}


// MARK: - Comparison summary
//
// Answers the first question anyone opens Compare Mode to ask — "do these
// differ, and where?" — without making them scroll both panes hunting for
// coloured rows.
//
// Collapsed by default: the one-line verdict is what most comparisons need, and
// a list that is always open would push the actual content down the window
// every time. The expanded state is remembered, because how much detail someone
// wants is a standing preference rather than a per-session accident.

struct ComparisonSummaryPanel: View {
    @EnvironmentObject var store: MediaStore
    @State private var hoveredTrackID: String? = nil
    @State private var expandedGroups: Set<String> = []
    
    /// How many tracks an opened group shows before it starts scrolling.
    private let visibleRowLimit = 5
    
    /// Height of the opened list, sized to whole rows so a partially visible
    /// row never sits cut off at the bottom edge.
    ///
    /// Derived from the zoom level rather than fixed, since these rows grow
    /// with the app's text size like everything else. The constant matches the
    /// vertical padding `trackRow` applies, plus its line height.
    private func expandedListHeight(for count: Int) -> CGFloat {
        let rowHeight = CGFloat(store.fontSize) + (SMI.Spacing.small + 1) * 2 + 6
        return rowHeight * CGFloat(min(count, visibleRowLimit))
    }
    
    /// Says plainly that there is more below.
    ///
    /// A scroll bar appears only once the pointer is over the list on most
    /// Macs, so without this the cut-off looks like the whole list.
    private func scrollHint(remaining: Int) -> some View {
        HStack(spacing: SMI.Spacing.snug) {
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
            Text("Scroll for \(remaining) more")
                .font(SMI.Typo.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, SMI.Spacing.tight + 1)
        .background(Color.primary.opacity(0.04))
    }
    
    private var comparison: MediaComparison { store.comparison }
    
    var body: some View {
        VStack(spacing: 0) {
            summaryBar
            // Drawn above the list, so a list retracting upward passes
            // behind the header instead of sliding across it.
                .zIndex(1)
            
            if store.isSummaryExpanded && !comparison.isIdentical {
                trackList
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(0)
            }
        }
        // Clipped to the panel's own bounds. Without this the retracting list
        // travelled up out of the panel and vanished over the header — the
        // motion was right, but nothing was hiding it once it left the box.
        .clipped()
        .padding(.horizontal, SMI.Spacing.large)
        .padding(.vertical, SMI.Spacing.small)
        .smiAnimation(SMI.Motion.smooth, value: store.isSummaryExpanded)
        .smiAnimation(SMI.Motion.fade, value: comparison)
    }
    
    // MARK: Bar
    
    private var summaryBar: some View {
        Button {
            guard !comparison.isIdentical else { return }
            smiWithAnimation(SMI.Motion.smooth) {
                store.isSummaryExpanded.toggle()
            }
        } label: {
            HStack(spacing: SMI.Spacing.medium) {
                Image(systemName: comparison.isIdentical
                      ? "checkmark.seal.fill"
                      : "arrow.triangle.branch")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(comparison.isIdentical
                                 ? SMI.Palette.success
                                 : SMI.Palette.diffModified)
                
                Text(headline)
                    .font(SMI.Typo.label)
                    .foregroundStyle(.primary)
                
                if !comparison.isIdentical {
                    HStack(spacing: SMI.Spacing.snug) {
                        if comparison.modifiedCount > 0 {
                            countChip(comparison.modifiedCount, "changed", SMI.Palette.diffModified)
                        }
                        if comparison.onlyInACount > 0 {
                            countChip(comparison.onlyInACount, "only in A", SMI.Palette.diffOnlyInA)
                        }
                        if comparison.onlyInBCount > 0 {
                            countChip(comparison.onlyInBCount, "only in B", SMI.Palette.diffOnlyInB)
                        }
                    }
                }
                
                Spacer(minLength: SMI.Spacing.small)
                
                if !comparison.isIdentical {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(store.isSummaryExpanded ? 0 : -90))
                        .smiAnimation(SMI.Motion.snap, value: store.isSummaryExpanded)
                }
            }
            .padding(.horizontal, SMI.Spacing.large)
            .padding(.vertical, SMI.Spacing.medium - 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(comparison.isIdentical)
        .liquidGlass(
            cornerRadius: SMI.Radius.button,
            tint: comparison.isIdentical ? SMI.Palette.success : .brandViolet,
            borderOpacity: 0.20
        )
    }
    
    private var headline: String {
        if comparison.isIdentical {
            return "These files report identical metadata"
        }
        let total = comparison.totalDifferences
        return "\(total) difference\(total == 1 ? "" : "s")"
    }
    
    private func countChip(_ count: Int, _ label: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text("\(count) \(label)")
                .font(SMI.Typo.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: Track list
    
    private var trackList: some View {
        VStack(spacing: 0) {
            ForEach(comparison.summaryGroups) { group in
                if group.isCollapsible {
                    groupRow(group)
                    
                    if expandedGroups.contains(group.id) {
                        // Capped and scrollable. A release with twelve subtitle
                        // tracks would otherwise push the panes off the bottom
                        // of the window the moment the group was opened —
                        // trading one wall of rows for a taller one.
                        VStack(spacing: 0) {
                            ScrollView(.vertical, showsIndicators: true) {
                                VStack(spacing: 0) {
                                    ForEach(group.tracks) { track in
                                        trackRow(track, indented: true)
                                    }
                                }
                            }
                            // An exact height, not a maximum.
                            //
                            // `maxHeight:` only permits a size, it doesn't ask
                            // for one — and inside a stack that was handing out
                            // less, the scroll view happily collapsed to a
                            // single row. Stating the height makes the parent
                            // reserve it.
                            .frame(height: expandedListHeight(for: group.tracks.count))
                            
                            if group.tracks.count > visibleRowLimit {
                                scrollHint(remaining: group.tracks.count - visibleRowLimit)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                } else if let track = group.tracks.first {
                    trackRow(track, indented: false)
                }
            }
        }
        .padding(.vertical, SMI.Spacing.tight)
        .liquidGlass(
            cornerRadius: SMI.Radius.button,
            tint: .brandViolet,
            borderOpacity: 0.14
        )
        .padding(.top, SMI.Spacing.snug)
        .smiAnimation(SMI.Motion.fade, value: hoveredTrackID)
        .smiAnimation(SMI.Motion.smooth, value: expandedGroups)
    }
    
    /// A folded type — "Audio · 5 tracks". Opens rather than navigating: with
    /// this many tracks there is no single sensible destination to jump to.
    private func groupRow(_ group: MediaComparison.SummaryGroup) -> some View {
        Button {
            smiWithAnimation(SMI.Motion.smooth) {
                if expandedGroups.contains(group.id) {
                    expandedGroups.remove(group.id)
                } else {
                    expandedGroups.insert(group.id)
                }
            }
        } label: {
            HStack(spacing: SMI.Spacing.medium - 2) {
                Image(systemName: group.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SMI.Palette.track(group.type))
                    .frame(width: 18)
                
                Text(group.title)
                    .font(SMI.Typo.callout)
                    .foregroundStyle(.primary)
                
                if let subtitle = group.subtitle {
                    Text(subtitle)
                        .font(SMI.Typo.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer(minLength: SMI.Spacing.small)
                
                Text("\(group.totalChanges)")
                    .font(SMI.Typo.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expandedGroups.contains(group.id) ? 0 : -90))
            }
            .padding(.horizontal, SMI.Spacing.large)
            .padding(.vertical, SMI.Spacing.small + 1)
            .background(
                hoveredTrackID == group.id ? SMI.Palette.hoverWash : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredTrackID = $0 ? group.id : nil }
    }
    
    private func trackRow(
        _ track: MediaComparison.TrackComparison,
        indented: Bool
    ) -> some View {
        Button {
            store.focusComparisonTrack(track.id)
        } label: {
            HStack(spacing: SMI.Spacing.medium - 2) {
                Image(systemName: track.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SMI.Palette.track(track.type))
                    .frame(width: 18)
                    .opacity(indented ? 0 : 1)
                
                Text(track.displayTitle)
                    .font(SMI.Typo.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                if track.trackA == nil || track.trackB == nil {
                    GlassBadge(
                        text: track.trackA == nil ? "B only" : "A only",
                        tint: track.trackA == nil
                        ? SMI.Palette.diffOnlyInB
                        : SMI.Palette.diffOnlyInA,
                        filled: false
                    )
                }
                
                Spacer(minLength: SMI.Spacing.small)
                
                Text("\(track.changeCount)")
                    .font(SMI.Typo.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        hoveredTrackID == track.id
                        ? Color.brandViolet
                        : Color.secondary.opacity(0.5)
                    )
            }
            .padding(.leading, indented ? SMI.Spacing.large + SMI.Spacing.xLarge : SMI.Spacing.large)
            .padding(.trailing, SMI.Spacing.large)
            .padding(.vertical, SMI.Spacing.small + 1)
            .background(
                hoveredTrackID == track.id ? SMI.Palette.hoverWash : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredTrackID = $0 ? track.id : nil }
    }
    
}

// MARK: - Swap motion
//
// The visual half of a swap: both panes fade back and slide toward each other,
// then settle. Mirrored by `isLeftPane`, so the two genuinely cross rather than
// drifting the same way.
//
// Applied as a modifier driven by a shared progress value rather than left to
// SwiftUI's implicit animation. Implicitly, only the pane that kept its view
// identity through the swap animated at all — and which pane that was
// alternated with every press.

struct SwapMotion: ViewModifier {
    let progress: CGFloat
    let isLeftPane: Bool
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private var travel: CGFloat {
        // No spatial movement under Reduce Motion — the fade alone still
        // signals that something changed.
        guard !reduceMotion else { return 0 }
        return isLeftPane ? 22 : -22
    }
    
    func body(content: Content) -> some View {
        content
            .offset(x: progress * travel)
            .opacity(1 - progress * 0.55)
            .blur(radius: reduceMotion ? 0 : progress * 1.5)
    }
}

// MARK: - Swap control
//
// Exchanges File A and File B without re-reading either from disk: the loaded
// files trade places wholesale, cached formats and all.
//
// Placed on the divider rather than in the toolbar because that is where the
// thing it acts on lives. A toolbar button would be more discoverable and less
// connected to its effect; the ⌘⇧S shortcut and the tooltip cover discovery.

struct SwapFilesButton: View {
    @EnvironmentObject var store: MediaStore
    
    @State private var isHovering = false
    @State private var rotation: Double = 0
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private var size: CGFloat { CGFloat(store.fontSize) * 2.9 }
    
    var body: some View {
        Button(action: swap) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.brandBlue.opacity(isHovering ? 0.30 : 0.16),
                                Color.brandPink.opacity(isHovering ? 0.30 : 0.16)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.brandBlue.opacity(isHovering ? 0.9 : 0.45),
                                Color.brandPink.opacity(isHovering ? 0.9 : 0.45)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: isHovering ? 1.6 : 1
                    )
                
                // Left-and-right arrows: the gesture the button performs,
                // stated as plainly as a glyph can.
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: size * 0.40, weight: .semibold))
                    .foregroundStyle(.primary)
                    .rotationEffect(.degrees(rotation))
            }
            .frame(width: size, height: size)
            .smiShadow(
                isHovering
                ? SMI.Elevation.floating(.brandViolet)
                : SMI.Elevation.raised(.brandViolet)
            )
            .scaleEffect(isHovering ? 1.08 : 1.0)
            .contentShape(Circle())
        }
        .buttonStyle(GlassPressStyle(scale: 0.90))
        .onHover { isHovering = $0 }
        .smiAnimation(SMI.Motion.snap, value: isHovering)
        .keyboardShortcut("s", modifiers: [.command, .shift])
        .help("Swap File A and File B (⌘⇧S)")
        .accessibilityLabel("Swap File A and File B")
    }
    
    private func swap() {
        store.swapCompareFiles()
        
        // A half turn per press, accumulating rather than resetting, so a
        // second swap continues the rotation instead of snapping back — the
        // motion reads as the panes changing places rather than as an icon
        // twitching.
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.68)) {
            rotation += 180
        }
    }
}

// MARK: - Compare-mode drop delegate
//
// SwiftUI's plain `.onDrop(of:isTargeted:)` reports only *whether* a drag is
// over the pane, never where — which isn't enough once a pane holds more than
// one destination. DropDelegate exposes the location on every update, so the
// same zone rules the AppKit panes use can be applied here.
//
// WHY THIS IS A CLASS, NOT A STRUCT
//
// The first version was a struct built inline in `body`. Its `dropEntered`
// mutates store state that `body` observes, so the sequence was: drag enters →
// state changes → body re-renders → `.onDrop` is handed a brand-new delegate
// instance mid-drag → SwiftUI treats the drop session as changed and can tear
// it down. A self-invalidating loop, which is why the highlight appeared
// sometimes and not others rather than never.
//
// Holding one instance in @State and mutating its properties keeps the
// delegate's identity stable across re-renders, so the drag session survives
// its own side effects.

@MainActor
final class PaneDropCoordinator: DropDelegate {
    
    let paneTarget: FileDropTarget
    var paneSize: CGSize = .zero
    weak var store: MediaStore?
    
    init(paneTarget: FileDropTarget) {
        self.paneTarget = paneTarget
    }
    
    private func resolved(_ info: DropInfo) -> FileDropTarget? {
        guard let store else { return paneTarget }
        return FileDropSupport.resolveTarget(
            paneTarget: paneTarget,
            localPoint: info.location,
            paneSize: paneSize,
            centreAvailable: store.isCentreDropAvailable
        )
    }
    
    /// Whether this coordinator's pane still exists.
    private var isLive: Bool {
        store?.isCompareMode == true
    }
    
    /// The destination this drag should actually go to.
    ///
    /// A stale coordinator — one whose pane has gone but whose drop region is
    /// still mounted — resolves to `.main` rather than refusing the drag.
    ///
    /// Refusing was the previous behaviour and it broke Easy View: SwiftUI does
    /// not pass a declined drop up to an ancestor handler, so the stale region
    /// swallowed the drag and the window-wide target never saw it. Tabs backed
    /// by AppKit views were unaffected because they handle drops themselves,
    /// which is why only Easy View stopped accepting files.
    ///
    /// Behaving as the window-wide target is both correct and self-healing: it
    /// works whether or not the region is stale, with no dependency on when
    /// SwiftUI gets around to tearing the pane down.
    private func destination(for info: DropInfo) -> FileDropTarget? {
        guard isLive else { return .main }
        return resolved(info)
    }
    
    /// Who owns the highlight for this drag — the pane, or the window.
    private var owner: FileDropTarget {
        isLive ? paneTarget : .main
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }
    
    func dropEntered(info: DropInfo) {
        store?.beginDragSession()
        store?.reportDropTarget(destination(for: info), from: owner)
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        let target = destination(for: info)
        store?.reportDropTarget(target, from: owner)
        // Refusing in the dead zone makes the cursor show "no" there, which is
        // the honest signal: a drop at that point would do nothing.
        return DropProposal(operation: target == nil ? .cancel : .copy)
    }
    
    func dropExited(info: DropInfo) {
        store?.reportDropTarget(nil, from: owner)
        store?.endDragSession(from: owner)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        guard let store else { return false }
        
        guard let target = destination(for: info) else {
            store.reportDropTarget(nil, from: owner)
            store.endDragSession(from: owner)
            return false
        }
        
        guard let provider = info.itemProviders(for: [.fileURL]).first else {
            return false
        }
        
        store.reportDropTarget(nil, from: owner)
        store.endDragSession(from: owner)
        
        Task { @MainActor in
            guard let item = try? await provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier
            ),
                  let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            
            FileDropSupport.deliver(url, to: target, store: store)
        }
        
        return true
    }
}

// MARK: - Centre drop card
//
// Straddles the divider, which is the whole point: it belongs to neither pane,
// and its position says so before any label does.

struct CentreDropCard: View {
    let isHighlighted: Bool
    
    private var tint: Color { FileDropTarget.newFile.tint }
    
    var body: some View {
        VStack(spacing: SMI.Spacing.small) {
            Image(systemName: "film.stack")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(LinearGradient.brandSweep(tint))
            
            VStack(spacing: 2) {
                Text("Open on its own")
                    .font(SMI.Typo.bodyStrong)
                    .foregroundStyle(.primary)
                
                // States the consequence up front. A file dropped here closes
                // a mode, and that shouldn't be a surprise discovered after.
                Text("Leaves Compare Mode")
                    .font(SMI.Typo.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(
            width: CompareDropGeometry.cardWidth,
            height: CompareDropGeometry.cardHeight
        )
        .background(
            RoundedRectangle(cornerRadius: SMI.Radius.panel, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: SMI.Radius.panel, style: .continuous)
                        .fill(tint.opacity(isHighlighted ? 0.20 : 0.08))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: SMI.Radius.panel, style: .continuous)
                .strokeBorder(
                    tint.opacity(isHighlighted ? 0.9 : 0.35),
                    lineWidth: isHighlighted ? 2.5 : 1
                )
        )
        .smiShadow(
            isHighlighted
            ? SMI.Elevation.floating(tint)
            : SMI.Elevation.raised(tint)
        )
        .scaleEffect(isHighlighted ? 1.04 : 1.0)
        .smiAnimation(SMI.Motion.snap, value: isHighlighted)
    }
}

// MARK: - Marquee scrolling text for overflowing filenames
//
// PHASE 5 — three problems fixed in sequence, so the history is worth stating.
//
// 1. Short names in the File A header scrolled, because the container width
//    was cached in `onAppear` — which fires before the split view has settled
//    its pane widths. File B escaped it only because its pane is laid out
//    after the divider position is already known.
//
// 2. The scroll speed was uneven, because `.repeatForever` re-applies `.delay`
//    on every repetition and interacts badly with autoreversal.
//
// 3. Then nothing scrolled at all. Measuring the text with a hidden copy in a
//    `.background` broke once that background sat *inside* the width-limited
//    frame: the hidden copy was constrained to the container, so its measured
//    width always equalled the container width and nothing ever looked like it
//    overflowed.
//
// Measurement no longer depends on layout at all. The text is measured
// directly against the same NSFont AppKit will render it with, which is
// deterministic and available before the first layout pass.

struct MarqueeText: View {
    let text: String
    var size: CGFloat = 12
    var weight: Font.Weight = .medium
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    /// Slack before scrolling kicks in, so a name that only just fits stays put.
    private let tolerance: CGFloat = 6
    /// Extra travel past the end so the tail clears the edge cleanly.
    private let tail: CGFloat = 24
    /// Points per second — slow enough to read while it moves.
    private let speed: CGFloat = 26
    /// How long the text rests at each end before moving again.
    private let pause: Double = 1.6
    
    /// Natural width of the text, measured against the font AppKit will use.
    /// No hidden views, no layout dependency, correct on the first frame.
    private var textWidth: CGFloat {
        let nsFont = NSFont.systemFont(ofSize: size, weight: weight.nsWeight)
        let bounds = (text as NSString).size(withAttributes: [.font: nsFont])
        return ceil(bounds.width)
    }
    
    var body: some View {
        GeometryReader { geo in
            let container = geo.size.width
            let overflows = container > 0 && textWidth > container + tolerance
            let shouldScroll = overflows && !reduceMotion
            let distance = max(textWidth - container + tail, 0)
            let travel = max(Double(distance / speed), 1.0)
            
            Group {
                if shouldScroll {
                    Text(text)
                        .font(.system(size: size, weight: weight))
                        .lineLimit(1)
                        .fixedSize()
                        .keyframeAnimator(
                            initialValue: CGFloat(0),
                            repeating: true
                        ) { content, offset in
                            content.offset(x: offset)
                        } keyframes: { _ in
                            KeyframeTrack(\.self) {
                                // Rest at the start
                                LinearKeyframe(CGFloat(0), duration: pause)
                                // Scroll out at a constant rate
                                LinearKeyframe(-distance, duration: travel)
                                // Rest at the end
                                LinearKeyframe(-distance, duration: pause)
                                // Return at the same rate
                                LinearKeyframe(CGFloat(0), duration: travel)
                            }
                        }
                } else {
                    // Truncate in the middle so the extension stays visible —
                    // on long release names that's usually the useful part.
                    Text(text)
                        .font(.system(size: size, weight: weight))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(width: max(container, 0), alignment: .leading)
            .clipped()
        }
        .frame(height: 16)
        .clipped()
        .help(text)
    }
}

// MARK: - Font weight bridging

private extension Font.Weight {
    /// SwiftUI and AppKit weights don't bridge automatically, and measurement
    /// has to use the same weight that will actually be drawn.
    var nsWeight: NSFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin:       return .thin
        case .light:      return .light
        case .regular:    return .regular
        case .medium:     return .medium
        case .semibold:   return .semibold
        case .bold:       return .bold
        case .heavy:      return .heavy
        case .black:      return .black
        default:          return .regular
        }
    }
}

// MARK: - NSRange search helper

private func findNSRangesInContent(of query: String, in content: String) -> [NSRange] {
    let searchString = content as NSString
    var ranges: [NSRange] = []
    var searchRange = NSRange(location: 0, length: searchString.length)
    
    while searchRange.location < searchString.length {
        let found = searchString.range(of: query, options: .caseInsensitive, range: searchRange)
        if found.location == NSNotFound { break }
        ranges.append(found)
        searchRange.location = found.location + found.length
        searchRange.length = searchString.length - searchRange.location
    }
    return ranges
}
