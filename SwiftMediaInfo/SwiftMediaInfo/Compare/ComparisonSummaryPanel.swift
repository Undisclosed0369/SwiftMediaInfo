//
//  ComparisonSummaryPanel.swift
//  SwiftMediaInfo
//
//  The summary above Compare Mode's panes: how many fields differ, and
//  where — collapsible, with crowded track types folded into one row, and
//  each track clickable to reveal it in both panes.
//

import SwiftUI

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
