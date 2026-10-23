//
//  DiffEasyView.swift
//  SwiftMediaInfo
//
//  Compare Mode's Easy View: each side's tracks, from the shared
//  MediaComparison, so every field sits at the same position in both panes
//  (a placeholder where one file lacks it). With Highlight Differences on
//  (⌘D), rows are coloured by how they differ — amber changed, blue only in
//  File A, pink only in File B. DiffTrackCard is a GlassCard like Easy View's,
//  and clicking a track in the summary scrolls both panes to it.
//

import SwiftUI

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
                CardStack(itemCount: trackComparisons.count) {
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
                // Rows ignore the pointer while the pane scrolls.
                .pausesHoverWhileScrolling()
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
        GlassCard(tint: trackColor, isExpanded: isExpanded, roundsOwnCorners: true) {
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
            smiWithAnimation(SMI.Motion.disclosure) { isExpanded.toggle() }
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
                
                CardDisclosureChevron(isExpanded: isExpanded, fontSize: store.fontSize)
            }
            .padding(.horizontal, SMI.Spacing.large)
            .padding(.vertical, SMI.Spacing.medium)
            .cardBackground(isHeaderHovered ? SMI.Palette.hoverWash : Color.clear, at: .top)
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
                Button("Copy Track as Markdown") {
                    store.copyTrack(
                        track,
                        from: (isFileB ? store.compareFile : store.currentFile)?.url,
                        asMarkdown: true
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
                    fileURL: (isFileB ? store.compareFile : store.currentFile)?.url,
                    nearCardBottom: index >= comparison.fields.count - 6
                )
            }
        }
        .padding(.bottom, SMI.Spacing.hair)
    }
}
