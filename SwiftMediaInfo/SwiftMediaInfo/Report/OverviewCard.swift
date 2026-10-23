//
//  OverviewCard.swift
//  SwiftMediaInfo
//
//  The Overview: the summary card at the top of Easy View, drawn from
//  MediaSummary. Settings › Appearance › Overview decides whether it opens
//  expanded, collapsed or as last left (OverviewExpansion).
//
//  The track cards below it list what MediaInfo reports, stream by stream.
//  This answers the questions people actually open a file to settle — what
//  resolution, is it HDR, what is the main audio, which subtitles — as a short
//  spec sheet: the file on top, then one compact block per kind of stream,
//  each in the colour its track card uses further down.
//

import SwiftUI

// MARK: - Expansion preference

/// Whether the overview starts open. Set in Settings › Appearance.
enum OverviewExpansion: String, CaseIterable, Identifiable {
    case expanded, collapsed, remember

    static let key = "overviewExpansion"
    /// The last state, used by `.remember`.
    static let rememberedKey = "easyOverviewExpanded"
    static let shippedDefault = OverviewExpansion.remember

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expanded:  return "Always Expanded"
        case .collapsed: return "Always Collapsed"
        case .remember:  return "Remember Last"
        }
    }
}

// MARK: - Card

struct OverviewCard: View {
    let summary: MediaSummary
    let fileURL: URL

    @EnvironmentObject var store: MediaStore
    @AppStorage(OverviewExpansion.key) private var expansionRaw = OverviewExpansion.shippedDefault.rawValue
    @AppStorage(OverviewExpansion.rememberedKey) private var rememberedExpanded = true
    /// This file's own open/closed state under the two "Always" options, so a
    /// click still opens or closes it — just without changing the next file.
    @State private var localExpanded: Bool?
    @State private var isHeaderHovered = false

    /// The content width, for choosing between columns and a stack. Nil
    /// until first measured, and treated as "columns" until then, so the
    /// common case — a full window — lays out in columns from the first frame
    /// instead of flicking over from a stack.
    @State private var availableWidth: CGFloat?

    private static let minimumBlockWidth: CGFloat = 260
    private let tint = Color.brandViolet

    private var expansion: OverviewExpansion {
        OverviewExpansion(rawValue: expansionRaw) ?? .shippedDefault
    }

    /// The state on screen. Starts from the setting, and every click changes
    /// it here first, inside the animation — so the card and the cards below
    /// it move together. Under Remember Last the choice is then saved; writing
    /// the saved value directly was what made the cards below jump instead of
    /// gliding, since a stored setting changing doesn't carry the animation.
    private var isExpanded: Bool {
        if let localExpanded { return localExpanded }
        switch expansion {
        case .remember:  return rememberedExpanded
        case .expanded:  return true
        case .collapsed: return false
        }
    }

    private func toggle() {
        let next = !isExpanded
        smiWithAnimation(SMI.Motion.disclosure) {
            localExpanded = next
        }
        if expansion == .remember {
            rememberedExpanded = next
        }
    }

    var body: some View {
        GlassCard(tint: tint, isExpanded: isExpanded) {
            header
        } content: {
            content
        }
        .onChange(of: expansionRaw) { _, _ in localExpanded = nil }
    }

    // MARK: Header

    private var header: some View {
        Button(action: toggle) {
            HStack(spacing: SMI.Spacing.medium - 2) {
                Image(systemName: summary.kind.symbol)
                    .font(.system(size: CGFloat(store.fontSize) + 2, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: CGFloat(store.fontSize) + 8)

                Text("Overview")
                    .font(.system(size: CGFloat(store.fontSize) + 2, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize()

                // Chips stay visible while the card is folded, so the overview
                // still says something useful in one line. Whole colour groups
                // drop off from the end when space runs out, never half a group.
                let groups = summary.chipGroups
                ViewThatFits(in: .horizontal) {
                    ForEach((0...groups.count).reversed(), id: \.self) { count in
                        chipRow(Array(groups.prefix(count)))
                    }
                }

                Spacer(minLength: SMI.Spacing.small)

                CardDisclosureChevron(isExpanded: isExpanded, fontSize: store.fontSize)
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
            Button("Copy Overview") {
                store.copySummary(summary, from: fileURL, asMarkdown: false)
            }
            Button("Copy Overview as Markdown") {
                store.copySummary(summary, from: fileURL, asMarkdown: true)
            }
        }
        .accessibilityLabel("Overview: \(summary.chipGroups.flatMap(\.chips).joined(separator: ", "))")
        .accessibilityHint(isExpanded ? "Collapses the overview" : "Expands the overview")
    }

    private func chipRow(_ groups: [MediaSummary.ChipGroup]) -> some View {
        HStack(spacing: SMI.Spacing.small) {
            ForEach(groups) { group in
                HStack(spacing: SMI.Spacing.tight) {
                    ForEach(Array(group.chips.enumerated()), id: \.offset) { _, chip in
                        GlassBadge(
                            text: chip,
                            tint: SMI.Palette.track(group.trackType),
                            filled: false,
                            scale: store.fontSize
                        )
                    }
                }
            }
        }
        .fixedSize()
    }

    // MARK: Content

    private var blocks: [MediaSummary.Section] {
        summary.sections.filter { $0.trackType != "General" }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: SMI.Spacing.medium) {
            fileHeader
                // Measured here rather than on the blocks themselves: the
                // header always spans the card, so its width can't be changed
                // by the very layout choice it is used to make.
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }

            if !blocks.isEmpty {
                // Side by side when there is room, stacked in a narrow Compare
                // pane — never squeezed into columns too thin to read.
                //
                // Decided from the width actually available, not with
                // ViewThatFits: that measures each block's single-line ideal
                // width, so one long value (a list of 57 subtitle tracks)
                // made the columns "not fit" in any window.
                let gaps = CGFloat(blocks.count - 1) * SMI.Spacing.medium
                let columnsFit = availableWidth.map {
                    ($0 - gaps) / CGFloat(blocks.count) >= Self.minimumBlockWidth
                } ?? true
                
                Group {
                    if columnsFit {
                        HStack(alignment: .top, spacing: SMI.Spacing.medium) {
                            ForEach(blocks) { block in
                                blockView(block)
                                    // Equally flexible, so the row is split
                                    // evenly however long one block's text is.
                                    // Never a fixed width: a column wider than
                                    // the window would push the window itself
                                    // wider. A single block (an image's) stays
                                    // a readable width.
                                    .frame(minWidth: 0, maxWidth: blocks.count == 1 ? 560 : .infinity, alignment: .topLeading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: SMI.Spacing.medium) {
                            ForEach(blocks) { block in
                                blockView(block)
                            }
                        }
                    }
                }

            }
        }
        .padding(SMI.Spacing.large)
    }

    private var fileHeader: some View {
        VStack(alignment: .leading, spacing: SMI.Spacing.hair) {
            Text(summary.fileName)
                .font(.system(size: CGFloat(store.fontSize) + 1, weight: .semibold))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if !summary.fileDetails.isEmpty {
                Text(summary.fileDetails.joined(separator: "  ·  "))
                    .font(.system(size: CGFloat(store.fontSize) - 1, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, SMI.Spacing.snug)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Copy File Name") { store.copySnippet(summary.fileName, from: fileURL) }
            if !summary.fileDetails.isEmpty {
                Button("Copy Details") {
                    store.copySnippet(summary.fileDetails.joined(separator: " · "), from: fileURL)
                }
            }
        }
    }

    private func blockView(_ block: MediaSummary.Section) -> some View {
        let color = SMI.Palette.track(block.trackType)
        let small = max(9, CGFloat(store.fontSize) - 3)

        return VStack(alignment: .leading, spacing: SMI.Spacing.hair) {
            HStack(spacing: SMI.Spacing.snug) {
                Image(systemName: block.symbol)
                    .font(.system(size: small, weight: .bold))
                    .foregroundStyle(color)
                Text(block.title.uppercased())
                    .font(.system(size: small, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(color.opacity(0.9))
            }
            .padding(.horizontal, SMI.Spacing.snug)
            .padding(.bottom, SMI.Spacing.tight)
            .accessibilityAddTraits(.isHeader)

            ForEach(block.rows) { row in
                OverviewLine(row: row, fileURL: fileURL, accent: color)
            }
        }
        .padding(SMI.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: SMI.Radius.control, style: .continuous)
                .fill(color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SMI.Radius.control, style: .continuous)
                .strokeBorder(color.opacity(0.16), lineWidth: 0.8)
        )
    }
}

// MARK: - Line

/// A quiet label and its value. Lighter than a FieldCell — no zebra stripes or
/// info icons — but with the same three copy actions, so copying works the
/// same everywhere in Easy View.
private struct OverviewLine: View {
    let row: MediaSummary.Row
    let fileURL: URL
    /// The block's colour, for the "Show all" link.
    var accent: Color = .brandViolet

    @EnvironmentObject var store: MediaStore
    @State private var isHovering = false
    @State private var showsAll = false
    
    /// How many entries of a list show before "Show all". Enough to see the
    /// main languages at a glance; a disc with 57 subtitle tracks would
    /// otherwise turn one block into a wall of text.
    private static let listLimit = 8
    
    private var isShortened: Bool {
        (row.items?.count ?? 0) > Self.listLimit && !showsAll
    }
    
    private var displayedValue: String {
        guard isShortened, let items = row.items else { return row.value }
        return items.prefix(Self.listLimit).joined(separator: ", ") + ", …"
    }

    private var explanation: String? {
        row.glossaryKey.flatMap { FieldGlossary.explanation(for: $0) }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SMI.Spacing.small) {
            Text(row.label)
                .font(.system(size: CGFloat(store.fontSize) - 1, weight: .medium))
                .foregroundStyle(.secondary)
                // Wide enough for "Main Language" at any zoom, so every value in
                // a block starts on the same vertical line.
                .frame(width: CGFloat(store.fontSize) * 7.4, alignment: .leading)
                .help(explanation ?? "")

            VStack(alignment: .leading, spacing: SMI.Spacing.tight) {
                Text(displayedValue)
                    .font(.system(size: CGFloat(store.fontSize)))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    // A new Text when the list grows or shrinks, crossfaded,
                    // rather than the same Text re-laid out in place: changed
                    // text takes its new size instantly, so the longer list
                    // would spill past the block while the block was still
                    // growing to hold it.
                    .id(showsAll)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.08)),
                        removal: .opacity.animation(.easeIn(duration: 0.08))
                    ))
                
                if let items = row.items, items.count > Self.listLimit {
                    Button {
                        smiWithAnimation(SMI.Motion.disclosure) { showsAll.toggle() }
                    } label: {
                        Text(showsAll ? "Show fewer" : "Show all \(items.count)")
                            .font(.system(size: CGFloat(store.fontSize) - 2, weight: .semibold))
                            .foregroundStyle(accent)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SMI.Spacing.snug)
        .padding(.vertical, SMI.Spacing.tight)
        .background(
            RoundedRectangle(cornerRadius: SMI.Radius.chip, style: .continuous)
                .fill(isHovering ? SMI.Palette.hoverWash : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Copy Value") { copy(row.value) }
            Button("Copy Field and Value") { copy("\(row.label): \(row.value)") }
            Divider()
            Button("Copy Field Name") { copy(row.label) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.label), \(row.value)")
        .accessibilityAction(named: "Copy value") { copy(row.value) }
    }

    private func copy(_ text: String) {
        store.copySnippet(text, from: fileURL)
        SMI.A11y.announce("Copied to clipboard")
    }
}
