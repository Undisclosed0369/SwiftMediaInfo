//
//  MiddleClick.swift
//  SwiftMediaInfo
//
//  Middle-click (the wheel button) on SwiftUI views.
//
//  SwiftUI has no middle-click gesture. This puts a transparent AppKit view
//  over the target that claims hit-testing for middle-button events only, and
//  returns nil for everything else — so left clicks, right clicks, hover,
//  drags and scrolling reach the SwiftUI view underneath exactly as before.
//
//  Used by tabs (middle-click closes, as in every browser) and by recent-file
//  chips (middle-click opens in a background tab).
//

import SwiftUI
import AppKit

extension View {
    /// Run `action` when the view is middle-clicked: pressed and released
    /// with the middle button inside its bounds.
    func onMiddleClick(perform action: @escaping () -> Void) -> some View {
        overlay(MiddleClickCatcher(action: action))
    }
}

private struct MiddleClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> MiddleClickView {
        let view = MiddleClickView()
        view.action = action
        return view
    }

    func updateNSView(_ view: MiddleClickView, context: Context) {
        view.action = action
    }
}

private final class MiddleClickView: NSView {
    var action: (() -> Void)?
    private var isPressed = false

    /// AppKit's middle button is button number 2.
    private static let middleButton = 2

    /// Claimed only while a middle-button event is being dispatched. Any
    /// other event finds nothing here and falls through to the views below.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent,
              event.type == .otherMouseDown || event.type == .otherMouseUp,
              event.buttonNumber == Self.middleButton else { return nil }
        return super.hitTest(point)
    }

    override func otherMouseDown(with event: NSEvent) {
        isPressed = event.buttonNumber == Self.middleButton
    }

    /// Fires on release, and only if the pointer is still over the view —
    /// the same rule a left click follows, so a press that slides off is a
    /// cancelled click, not a closed tab.
    override func otherMouseUp(with event: NSEvent) {
        defer { isPressed = false }

        guard isPressed, event.buttonNumber == Self.middleButton else { return }

        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            action?()
        }
    }
}
