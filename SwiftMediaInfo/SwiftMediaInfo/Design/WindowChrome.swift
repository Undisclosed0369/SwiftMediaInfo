//
//  WindowChrome.swift
//  SwiftMediaInfo
//
//  The pieces the app's secondary windows share.
//
//  • Sheets (Siri AI, Media Health, Share): the round ✕ close button, and
//    the guard that keeps ⌘M from minimising the window behind them. Both
//    used to live in the Siri AI window's file.
//  • Panel windows (About, Keyboard Shortcuts): the header on each card, and
//    how the windows behave. Both lived as identical copies in each
//    window's file.
//

import SwiftUI
import AppKit

// MARK: - Sheet chrome

/// The round ✕ in a sheet's top-right corner: a Liquid Glass circle, as
/// iOS 27 and macOS 27 draw their own close buttons.
struct SheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help("Close")
        .accessibilityLabel("Close")
    }
}

/// Swallows ⌘M while a sheet is open. ⌘M cycles the appearance in the main
/// window; with a sheet in front it reached Window › Minimize instead and
/// minimised the whole window. Settings, About and the shortcuts window
/// ignore it, and so do sheets now.
struct SheetKeyGuard: View {
    var body: some View {
        Button("") {}
            .keyboardShortcut("m", modifiers: .command)
            .opacity(0)
            .accessibilityHidden(true)
    }
}

// MARK: - Card header

/// A card's header in the About and Keyboard Shortcuts windows: a small
/// coloured symbol and the title in spaced capitals.
struct PanelCardHeader: View {
    @Environment(\.smiScale) private var scale

    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: scale.s(SMI.Spacing.snug)) {
            Image(systemName: icon)
                .font(scale.font(11, .bold))
                .foregroundStyle(tint)
            
            Text(title.uppercased())
                .font(scale.font(11, .medium))
                .kerning(0.6)
                .foregroundStyle(.secondary)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, scale.s(SMI.Spacing.large))
        .padding(.vertical, scale.s(SMI.Spacing.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Panel window behaviour
//
// Two jobs, both about making an auxiliary window behave like a panel rather
// than like a document.
//
// ESC CLOSES IT. Standard for a reference window you opened to glance at.
//
// ⌘M DOES NOTHING. ⌘M is AppKit's Minimize, which lives in the
// Window menu and is matched before the key press reaches any SwiftUI shortcut
// — so pressing it here folded the window into the Dock, while in the main
// window ⌘M cycles the appearance. The same chord doing two unrelated things
// depending on which window happened to be frontmost is the kind of
// inconsistency that makes an app feel unfinished.
//
// The fix is not to intercept the key. It is to say what this window is:
// removing `.miniaturizable` tells AppKit this is a panel, and AppKit then
// disables its own menu item — so ⌘M does nothing, the Window menu greys
// Minimize out, and the yellow traffic light dims. One property, and every
// route to minimizing agrees with the others.
//
// Reapplied in `updateNSView` because the window is not attached during
// `makeNSView`, and because a restored window can arrive with its original
// style mask.

struct PanelWindowBehaviour: NSViewRepresentable {
    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
            configure(view.window)
        }
        return view
    }
    
    func updateNSView(_ nsView: KeyView, context: Context) {
        configure(nsView.window)
    }
    
    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        if window.styleMask.contains(.miniaturizable) {
            window.styleMask.remove(.miniaturizable)
        }
    }
    
    class KeyView: NSView {
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
