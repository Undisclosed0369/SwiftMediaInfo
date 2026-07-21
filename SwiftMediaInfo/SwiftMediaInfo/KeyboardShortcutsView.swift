//
//  KeyboardShortcutsView.swift
//  SwiftMediaInfo
//
//  A polished, premium keyboard shortcuts reference window.
//

import SwiftUI

struct KeyboardShortcutsView: View {
    
    private let shortcutGroups: [(title: String, icon: String, color: Color, shortcuts: [(keys: String, description: String)])] = [
        (
            title: "File",
            icon: "doc",
            color: .brandBlue,
            shortcuts: [
                ("⌘ O",       "Open file or folder"),
                ("⌘ ⏎",       "Open file in default app"),
                ("⌘ ⇧ C",     "Toggle compare mode"),
            ]
        ),
        (
            title: "View Modes",
            icon: "rectangle.3.group",
            color: .brandViolet,
            shortcuts: [
                ("⌘ 1",       "Easy View  ·  Change File A (compare)"),
                ("⌘ 2",       "Text View  ·  Change File B (compare)"),
                ("⌘ 3",       "Raw Text View"),
                ("⌘ 4",       "HTML View"),
                ("⌘ 5",       "XML View"),
                ("⌘ 6",       "JSON View"),
            ]
        ),
        (
            title: "Display",
            icon: "eye",
            color: .brandGreen,
            shortcuts: [
                ("⌘ +",       "Zoom in (increase font size)"),
                ("⌘ −",       "Zoom out (decrease font size)"),
                ("⌘ 0",       "Reset zoom to 100%"),
                ("⌘ M",       "Cycle appearance (Light → Dark → System)"),
                ("⌘ B",       "Toggle animated background"),
            ]
        ),
        (
            title: "Compare",
            icon: "square.split.2x1",
            color: .brandPink,
            shortcuts: [
                ("⌘ D",       "Toggle difference highlighting"),
            ]
        ),
        (
            title: "Tools",
            icon: "wrench.and.screwdriver",
            color: .brandViolet,
            shortcuts: [
                ("⌘ E",       "Export menu"),
                ("⌘ F",       "Search / filter bar"),
                ("⌘ K",       "Show keyboard shortcuts"),
            ]
        ),
        (
            title: "Help",
            icon: "questionmark.circle",
            color: .brandBlue,
            shortcuts: [
                ("⌘ /",       "Open help / GitHub page"),
            ]
        ),
    ]
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.brandBlue, .brandViolet, .brandPink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Keyboard Shortcuts")
                        .font(.system(size: 22, weight: .semibold))
                    
                    Text("SwiftMediaInfo")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 28)
                .padding(.bottom, 16)
                
                Divider()
                    .padding(.horizontal, 24)
                
                // Shortcut groups
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(shortcutGroups.enumerated()), id: \.offset) { _, group in
                            shortcutGroup(group)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                }
                
                Divider()
                    .padding(.horizontal, 24)
                
                // Footer
                Text("Press Esc to close")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 12)
            }
        }
        .frame(width: 440, height: 640)
        .background(
            EscapeKeyHandler()
        )
    }
    
    // MARK: - Shortcut group
    
    private func shortcutGroup(
        _ group: (title: String, icon: String, color: Color, shortcuts: [(keys: String, description: String)])
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack(spacing: 7) {
                Image(systemName: group.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(group.color)
                Text(group.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(group.color)
            }
            .padding(.bottom, 2)
            
            // Shortcut rows
            VStack(spacing: 0) {
                ForEach(Array(group.shortcuts.enumerated()), id: \.offset) { idx, shortcut in
                    HStack(spacing: 0) {
                        // Keys
                        shortcutKeyBadge(shortcut.keys)
                            .frame(width: 80, alignment: .leading)
                        
                        // Description
                        Text(shortcut.description)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.85))
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        idx % 2 == 0
                        ? Color.clear
                        : group.color.opacity(0.03)
                    )
                }
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(group.color.opacity(0.12), lineWidth: 0.5)
            )
        }
    }
    
    // MARK: - Key badge
    
    private func shortcutKeyBadge(_ keys: String) -> some View {
        HStack(spacing: 3) {
            ForEach(keys.components(separatedBy: " "), id: \.self) { key in
                Text(key)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.75))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
            }
        }
    }
}

// MARK: - Escape key handler (closes the hosting window)

private struct EscapeKeyHandler: NSViewRepresentable {
    func makeNSView(context: Context) -> EscapeKeyView {
        let view = EscapeKeyView()
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }
    
    func updateNSView(_ nsView: EscapeKeyView, context: Context) {}
    
    class EscapeKeyView: NSView {
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { // Escape
                window?.close()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
