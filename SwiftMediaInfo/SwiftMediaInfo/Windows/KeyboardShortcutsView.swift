//
//  KeyboardShortcutsView.swift
//  SwiftMediaInfo
//
//  The Keyboard Shortcuts window (⌘K, Help menu): every shortcut in the app,
//  grouped, with notes for the ones that mean something else in another
//  context. It is a hand-written list — when a shortcut is added or changed
//  anywhere (ContentView, the menus in MediaInfoMacApp, a window of its
//  own), update it here too. Esc closes it and ⌘M does nothing
//  (PanelWindowBehaviour, in WindowChrome).
//

import SwiftUI
import AppKit

/// Thin wrapper — see SettingsView for why the scale is read one level down
/// rather than in the view the scene applies it to.
struct KeyboardShortcutsView: View {
    var body: some View {
        KeyboardShortcutsContent()
    }
}

// MARK: - Model

private struct ShortcutEntry: Identifiable {
    let id = UUID()
    let keys: String
    let description: String
    
    /// A quiet caveat, in dimmer text under the description. For things that
    /// qualify the shortcut without changing what it is.
    var note: String? = nil
    
    /// A tinted pill under the description, for the shortcuts that mean a
    /// second thing in a second context.
    ///
    /// These were previously plain grey notes and were too easy to skim past —
    /// which matters most for exactly these entries, because ⌘1 doing something
    /// completely different in Compare Mode is a surprise, and a surprise
    /// buried in tertiary grey is a surprise you meet by accident.
    ///
    /// A pill reads as a distinct object rather than as an afterthought, and
    /// the tint ties it to the group it belongs to.
    var detail: String? = nil
    var detailIcon: String? = nil
}

private struct ShortcutGroup: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let tint: Color
    
    /// A condition that applies to every shortcut in the group.
    ///
    /// Stated once at the top rather than repeated on each row. The File
    /// Actions group is the reason this exists: all three of its shortcuts are
    /// single-file only, and saying so three times would be noise while saying
    /// it nowhere would be wrong.
    var condition: String? = nil
    var conditionIcon: String = "info.circle"
    
    let entries: [ShortcutEntry]
}

private struct KeyboardShortcutsContent: View {
    @Environment(\.smiScale) private var scale
    
    // No `@EnvironmentObject` here any more. The store was only read for the
    // count badges, which are gone; the scene still injects it, because
    // WindowZoomScale — applied outside this view — needs it, and so does the
    // gradient behind the glass.
    
    private var groups: [ShortcutGroup] {
        [
            ShortcutGroup(
                title: "File",
                icon: "doc",
                tint: .brandBlue,
                entries: [
                    ShortcutEntry(keys: "⌘ T", description: "New tab, showing the start screen"),
                    ShortcutEntry(keys: "⌘ O", description: "Open a file or folder in a new tab"),
                    ShortcutEntry(
                        keys: "⌘ W",
                        description: "Close the current tab",
                        // Worth spelling out: with tabs, ⌘W only reaches the
                        // window once the last tab has gone.
                        note: "Closes the window once no tabs are open"
                    ),
                    ShortcutEntry(keys: "⌥ ⌘ W", description: "Close the window"),
                    ShortcutEntry(
                        keys: "⌘ ⇧ ]",
                        description: "Show the next tab",
                        note: "Or Control-Tab (⌃ ⇥)"
                    ),
                    ShortcutEntry(
                        keys: "⌘ ⇧ [",
                        description: "Show the previous tab",
                        note: "Or Control-Shift-Tab (⌃ ⇧ ⇥)"
                    ),
                    ShortcutEntry(keys: "⌥ ⌘ ↓", description: "Next file in a folder tab"),
                    ShortcutEntry(keys: "⌥ ⌘ ↑", description: "Previous file in a folder tab"),
                    ShortcutEntry(
                        keys: "Middle-click",
                        description: "Close a tab",
                        note: "On a recent or folder file: open it in a background tab"
                    ),
                    ShortcutEntry(keys: "⌘ ⏎", description: "Open the file in its default app"),
                ]
            ),
            
            ShortcutGroup(
                title: "File Actions",
                icon: "doc.badge.ellipsis",
                tint: .brandGreen,
                // A key equivalent cannot ask which of two files you meant, so
                // in Compare Mode these move to the File menu as File A and
                // File B instead of guessing.
                condition: "Single file only. In Compare Mode these move to the File menu, under File A and File B.",
                entries: [
                    ShortcutEntry(keys: "⌘ ⇧ R", description: "Reveal in Finder"),
                    ShortcutEntry(keys: "⌥ ⌘ C", description: "Copy the full file path"),
                    ShortcutEntry(keys: "⌘ ⌫", description: "Move the file to the Trash"),
                ]
            ),
            
            ShortcutGroup(
                title: "Tabs",
                icon: "rectangle.stack",
                tint: .brandViolet,
                entries: [
                    ShortcutEntry(
                        keys: "⌘ 1",
                        description: "Show the first tab",
                        detail: "In Compare Mode  ·  Choose File A",
                        detailIcon: "square.split.2x1"
                    ),
                    ShortcutEntry(
                        keys: "⌘ 2",
                        description: "Show the second tab",
                        detail: "In Compare Mode  ·  Choose File B",
                        detailIcon: "square.split.2x1"
                    ),
                    ShortcutEntry(
                        keys: "⌘ 3–8",
                        description: "Show that tab",
                        note: "Not in Compare Mode"
                    ),
                    ShortcutEntry(
                        keys: "⌘ 9",
                        description: "Show the last tab",
                        note: "Not in Compare Mode"
                    ),
                ]
            ),
            
            ShortcutGroup(
                title: "View Modes",
                icon: "rectangle.3.group",
                tint: .brandBlue,
                entries: [
                    ShortcutEntry(keys: "⌃ ⌘ 1", description: "Easy View"),
                    ShortcutEntry(keys: "⌃ ⌘ 2", description: "Text View"),
                    ShortcutEntry(keys: "⌃ ⌘ 3", description: "Raw Text View"),
                    ShortcutEntry(keys: "⌃ ⌘ 4", description: "HTML View"),
                    ShortcutEntry(keys: "⌃ ⌘ 5", description: "XML View"),
                    ShortcutEntry(keys: "⌃ ⌘ 6", description: "JSON View"),
                ]
            ),
            
            ShortcutGroup(
                title: "Compare",
                icon: "square.split.2x1",
                tint: .brandPink,
                entries: [
                    ShortcutEntry(keys: "⌘ ⇧ C", description: "Turn Compare Mode on or off"),
                    ShortcutEntry(keys: "⌘ ⇧ S", description: "Swap File A and File B"),
                    ShortcutEntry(keys: "⌘ D", description: "Highlight differences"),
                    ShortcutEntry(
                        keys: "⌘ click",
                        description: "Compare a tab with the current one",
                        note: "⌘-click a tab to make it File B"
                    ),
                    ShortcutEntry(
                        keys: "⌥ drag",
                        description: "Drop a second file to compare",
                        note: "Hold ⌥ while dragging onto an open file"
                    ),
                ]
            ),
            
            ShortcutGroup(
                title: "Display",
                icon: "eye",
                tint: .brandGreen,
                entries: [
                    ShortcutEntry(keys: "⌘ +", description: "Zoom in"),
                    ShortcutEntry(keys: "⌘ −", description: "Zoom out"),
                    ShortcutEntry(keys: "⌘ 0", description: "Reset zoom to 100%"),
                    // The two cycling shortcuts get the same pill treatment as
                    // each other. Naming the states in order is the whole point
                    // of a cycle — otherwise you press it three times to find
                    // out what it does.
                    ShortcutEntry(
                        keys: "⌘ M",
                        description: "Cycle appearance",
                        detail: "Light  →  Dark  →  System",
                        detailIcon: "circle.lefthalf.filled"
                    ),
                    ShortcutEntry(
                        keys: "⌘ B",
                        description: "Cycle the background",
                        detail: "Static  →  Animated  →  Off",
                        detailIcon: "sparkles"
                    ),
                ]
            ),
            
            ShortcutGroup(
                title: "Tools",
                icon: "wrench.and.screwdriver",
                tint: .brandViolet,
                entries: [
                    ShortcutEntry(
                        keys: "Space",
                        description: "Preview the current file",
                        note: "Quick Look, or a SwiftMediaInfo preview for MKV and other formats macOS can’t open. Not in Compare Mode or while typing."
                    ),
                    ShortcutEntry(
                        keys: "← →",
                        description: "Skip back or forward 10 seconds",
                        note: "In the SwiftMediaInfo preview"
                    ),
                    ShortcutEntry(keys: "⌘ F", description: "Search and filter"),
                    ShortcutEntry(keys: "⌘ E", description: "Export"),
                    ShortcutEntry(
                        keys: "⌘ ⇧ H",
                        description: "Check Media Health",
                        note: "In Compare Mode, switch between File A and File B in the window"
                    ),
                    ShortcutEntry(
                        keys: "⌘ ⇧ I",
                        description: "Ask Siri AI",
                        note: "Only on Macs that support Apple Intelligence, running macOS 27 or later"
                    ),
                    ShortcutEntry(
                        keys: "⌘ R",
                        description: "Redo a stopped Siri AI answer",
                        note: "In the Siri AI window, after an answer is stopped with Esc or the Stop button"
                    ),
                    ShortcutEntry(keys: "⌘ ,", description: "Settings"),
                    ShortcutEntry(
                        keys: "⌘ K",
                        description: "Keyboard Shortcuts Reference",
                        note: "This window"
                    ),
                    // ⌘/ opens the app's own page (not the repository).
                    ShortcutEntry(keys: "⌘ /", description: "Open the website"),
                    ShortcutEntry(keys: "⌘ I", description: "About SwiftMediaInfo"),
                ]
            ),
        ]
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            ScrollView {
                VStack(alignment: .leading, spacing: scale.s(SMI.Spacing.large)) {
                    symbolLegend
                    
                    ForEach(groups) { group in
                        groupCard(group)
                    }
                }
                .padding(.horizontal, scale.s(SMI.Spacing.xLarge))
                .padding(.top, scale.s(SMI.Spacing.medium))
                .padding(.bottom, scale.s(SMI.Spacing.large))
            }
            
            footer
        }
        .frame(width: scale.s(460), height: scale.s(660))
        .background {
            ZStack {
                // Half strength, matching Settings and About. At full strength
                // a narrow window stacked with cards has the gradient fighting
                // the content; the glass still has colour to pick up at 0.5.
                GradientBackground()
                    .opacity(0.5)
                Rectangle().fill(.ultraThinMaterial)
            }
            .ignoresSafeArea()
        }
        .background(PanelWindowBehaviour())
    }
    
    // MARK: - Header
    
    private var header: some View {
        VStack(spacing: scale.s(SMI.Spacing.snug)) {
            Image(systemName: "keyboard")
                .font(scale.font(34, .light))
                .foregroundStyle(LinearGradient.brandSpectrum)
                .smiShadow(SMI.Elevation.resting(.brandViolet))
            
            Text("Keyboard Shortcuts")
                .font(scale.font(22, .semibold))
            
            Text("SwiftMediaInfo")
                .font(scale.font(12))
                .foregroundStyle(.secondary)
        }
        .padding(.top, scale.s(SMI.Spacing.xLarge))
        .padding(.bottom, scale.s(SMI.Spacing.medium))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
    
    // MARK: - Symbol legend
    
    /// What the modifier symbols mean. Every Mac user meets ⌘, but ⌃, ⌥ and ⇥
    /// are printed on few keyboards, and a reference written in symbols
    /// nobody can read is not much of a reference.
    private var symbolLegend: some View {
        let symbols: [(String, String)] = [
            ("⌘", "Command"), ("⇧", "Shift"), ("⌥", "Option"),
            ("⌃", "Control"), ("⇥", "Tab"), ("⏎", "Return"), ("⌫", "Delete"),
            ("↑↓", "Arrows")
        ]
        
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: scale.s(96)), spacing: scale.s(SMI.Spacing.small))],
            alignment: .leading,
            spacing: scale.s(SMI.Spacing.tight)
        ) {
            ForEach(symbols, id: \.0) { symbol, name in
                HStack(spacing: scale.s(SMI.Spacing.snug)) {
                    Text(symbol)
                        .font(scale.font(12, .semibold))
                        .frame(width: scale.s(22), height: scale.s(20))
                        .background(
                            RoundedRectangle(cornerRadius: scale.s(5), style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                    Text(name)
                        .font(scale.font(11))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(symbol) means \(name)")
            }
        }
        .padding(.horizontal, scale.s(SMI.Spacing.tight))
    }
    
    // MARK: - Group card
    
    private func groupCard(_ group: ShortcutGroup) -> some View {
        GlassCard(tint: group.tint) {
            PanelCardHeader(title: group.title, icon: group.icon, tint: group.tint)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if let condition = group.condition {
                    conditionStrip(condition, icon: group.conditionIcon, tint: group.tint)
                }
                
                ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                    row(entry, tint: group.tint, index: index)
                }
            }
            .padding(.bottom, scale.s(SMI.Spacing.tight))
        }
    }
    
    /// Sits directly under the group header, above the rows, so it is read
    /// before the shortcuts it qualifies rather than after them.
    private func conditionStrip(_ text: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: scale.s(SMI.Spacing.snug)) {
            Image(systemName: icon)
                .font(scale.font(10, .semibold))
                .foregroundStyle(tint)
                .padding(.top, scale.s(1))
            
            Text(text)
                .font(scale.font(11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, scale.s(SMI.Spacing.large))
        .padding(.vertical, scale.s(SMI.Spacing.snug))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.07))
        .smiReadAsOne(text)
    }
    
    private func row(_ entry: ShortcutEntry, tint: Color, index: Int) -> some View {
        HStack(alignment: .top, spacing: scale.s(SMI.Spacing.medium)) {
            keyBadge(entry.keys, tint: tint)
                .frame(width: scale.s(86), alignment: .leading)
            
            VStack(alignment: .leading, spacing: scale.s(SMI.Spacing.tight)) {
                Text(entry.description)
                    .font(scale.font(13))
                    .foregroundStyle(.primary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                
                if let detail = entry.detail {
                    detailPill(detail, icon: entry.detailIcon)
                }
                
                if let note = entry.note {
                    // `.secondary`, not `.tertiary`. Tertiary is for text you
                    // are not really meant to read — a copyright line, a hint
                    // you already know. These notes carry the actual caveat,
                    // and at 11pt over a translucent panel tertiary was close
                    // to invisible in both appearances.
                    Text(note)
                        .font(scale.font(11, .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, scale.s(SMI.Spacing.large))
        .padding(.vertical, scale.s(SMI.Spacing.snug))
        // The same zebra striping Easy View uses, so a long list stays
        // trackable across the row. Deliberately very low contrast — it is a
        // reading aid, not a divider.
        .background(index % 2 == 1 ? SMI.Palette.rowAlternate : Color.clear)
        // One spoken sentence per row rather than a pile of separated glyphs.
        .smiReadAsOne(spokenRow(entry))
    }
    
    /// "Command W. Close the open file. Closes the window instead when nothing
    /// is open." The symbols are expanded because VoiceOver reads ⌘ as
    /// "place of interest sign", which helps nobody.
    private func spokenRow(_ entry: ShortcutEntry) -> String {
        let spokenKeys = entry.keys
            .replacingOccurrences(of: "⌘", with: "Command")
            .replacingOccurrences(of: "⌥", with: "Option")
            .replacingOccurrences(of: "⇧", with: "Shift")
            .replacingOccurrences(of: "⌫", with: "Delete")
            .replacingOccurrences(of: "⏎", with: "Return")
            .replacingOccurrences(of: "⌃", with: "Control")
            .replacingOccurrences(of: "⇥", with: "Tab")
            .replacingOccurrences(of: "↓", with: "Down Arrow")
            .replacingOccurrences(of: "↑", with: "Up Arrow")
            .replacingOccurrences(of: "←", with: "Left Arrow")
            .replacingOccurrences(of: "→", with: "Right Arrow")
            .replacingOccurrences(of: "−", with: "Minus")
            .replacingOccurrences(of: "=", with: "Equals")
        
        var parts = [spokenKeys, entry.description]
        if let detail = entry.detail {
            // The separators are decoration; spoken aloud they are clutter.
            parts.append(
                detail
                    .replacingOccurrences(of: "→", with: "then")
                    .replacingOccurrences(of: "·", with: ",")
            )
        }
        if let note = entry.note { parts.append(note) }
        return parts.joined(separator: ". ")
    }
    
    /// One colour for every pill, rather than the group's own tint.
    ///
    /// The group tints were the problem. Green is bright, so it disappears
    /// against a light panel; violet is dark, so it disappears against a dark
    /// one. Each was legible in exactly one appearance.
    ///
    /// Blue is the brand colour that sits nearest the middle in luminance, so
    /// it holds up as a wash and a border in both. Using one colour throughout
    /// also makes the pill read as a consistent kind of object — "there is more
    /// to this row" — rather than as a fourth thing tinted like its group.
    private static let pillTint = Color.brandBlue
    
    // MARK: - Detail pill
    //
    // Deliberately the same shape language as the key badges beside it — a
    // rounded, tinted, bordered token — so the eye reads the whole row as one
    // designed object rather than a caption bolted under a control.
    //
    // Tinted at group strength rather than left grey, because the point is that
    // it should not be skippable.
    
    private func detailPill(_ text: String, icon: String?) -> some View {
        HStack(spacing: scale.s(SMI.Spacing.tight) + 1) {
            if let icon {
                Image(systemName: icon)
                    .font(scale.font(9, .bold))
                    .foregroundStyle(Self.pillTint)
            }
            
            Text(text)
            // `.primary` rather than the tint. This is the part that
            // actually fixes it: no single fixed colour is legible on both
            // a near-white and a near-black panel, because the two need
            // opposite luminance. `.primary` is the system's answer and it
            // is correct in every appearance, including any future one.
            //
            // The pill keeps its brand identity through the wash, the
            // border and the glyph, which are decoration and can afford to
            // be low contrast. The words cannot.
                .foregroundStyle(.primary.opacity(0.92))
                .font(scale.font(10, .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, scale.s(SMI.Spacing.snug) + 1)
        .padding(.vertical, scale.s(2) + 1)
        .background(
            Capsule(style: .continuous)
                .fill(Self.pillTint.opacity(0.16))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Self.pillTint.opacity(0.38), lineWidth: 0.7)
        )
    }
    
    // MARK: - Key badge
    
    private func keyBadge(_ keys: String, tint: Color) -> some View {
        HStack(spacing: scale.s(3)) {
            // By position, not by text: an entry may use the same key twice,
            // and two badges sharing an identity draw on top of each other.
            ForEach(Array(keys.components(separatedBy: " ").enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(scale.font(12, .semibold, .rounded))
                    .foregroundStyle(.primary.opacity(0.8))
                    .padding(.horizontal, scale.s(SMI.Spacing.tight) + 1)
                    .padding(.vertical, scale.s(2))
                    .background(
                        RoundedRectangle(cornerRadius: scale.s(SMI.Radius.chip), style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: scale.s(SMI.Radius.chip), style: .continuous)
                            .strokeBorder(tint.opacity(0.28), lineWidth: 0.6)
                    )
            }
        }
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        VStack(spacing: scale.s(SMI.Spacing.hair) + 1) {
            SpectrumDivider()
            
            // The Compare Mode caveat used to live here, far from the three
            // shortcuts it applied to. It now sits inside the File Actions
            // card, directly above them, which is where it is actually useful.
            Text("Press Esc to close")
                .font(scale.font(11))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, scale.s(SMI.Spacing.xLarge))
                .padding(.top, scale.s(SMI.Spacing.small))
                .padding(.bottom, scale.s(SMI.Spacing.medium))
        }
    }
}
