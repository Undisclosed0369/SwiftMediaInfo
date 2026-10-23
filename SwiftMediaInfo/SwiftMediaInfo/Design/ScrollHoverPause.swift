//
//  ScrollHoverPause.swift
//  SwiftMediaInfo
//
//  Rows stop reacting to the pointer while their list moves. Apply
//  `pausesHoverWhileScrolling()` to a scroll view's content (Easy View,
//  Compare's panes, search results).
//
//  WHY
//
//  A list is scrolled with the pointer resting on it, so every row that
//  passes under the pointer used to light up and go dark again — forty or
//  more hover changes a second, each one rebuilding its row — and SwiftUI
//  re-checked every row's hover area against the pointer on every frame of
//  the scroll. With Fight Club open on an M4, a fast scroll ran at about 33
//  frames a second because of it, against 100 with the pointer elsewhere.
//
//  While the list is moving, its content takes no pointer events, so nothing
//  under the pointer is hovered or hit-tested; a tenth of a second after it
//  stops, the row under the pointer lights up as before. Finder, Mail and
//  Safari behave the same way. The scroll itself is untouched: wheel and
//  trackpad events go to the scroll view, not to its content.
//
//  Two things end the pause early, so nothing that worked before is lost: a
//  click, which is always meant for what is under it, and a held mouse button
//  — a text selection dragged past the edge scrolls the list, and the row
//  being selected in must keep receiving the drag.
//

import SwiftUI
import AppKit

extension View {
    /// For a scroll view's content: pauses hover and clicks while it scrolls.
    func pausesHoverWhileScrolling() -> some View {
        modifier(ScrollHoverPause())
    }
}

private struct ScrollHoverPause: ViewModifier {
    @State private var isScrolling = false

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!isScrolling)
            .background(ScrollActivityReader(isScrolling: $isScrolling).allowsHitTesting(false))
    }
}

/// Watches the enclosing scroll view from inside its content.
private struct ScrollActivityReader: NSViewRepresentable {
    @Binding var isScrolling: Bool

    func makeNSView(context: Context) -> ScrollActivityView {
        let view = ScrollActivityView()
        view.onChange = { isScrolling = $0 }
        return view
    }

    func updateNSView(_ view: ScrollActivityView, context: Context) {
        view.onChange = { isScrolling = $0 }
    }
}

final class ScrollActivityView: NSView {
    var onChange: ((Bool) -> Void)?

    /// How long the list must be still before the pointer counts again.
    /// Longer than the gap between frames of a wheel or momentum scroll,
    /// short enough that the highlight seems to arrive as the list stops.
    private static let settle: TimeInterval = 0.1

    private weak var clipView: NSClipView?
    private var isScrolling = false
    private var settleTimer: Timer?
    private var clickMonitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observe(window == nil ? nil : enclosingScrollView?.contentView)
        if window == nil { finish() }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if window != nil { observe(enclosingScrollView?.contentView) }
    }

    override func layout() {
        super.layout()
        // In case the scroll view was assembled after this view arrived.
        if clipView == nil, window != nil { observe(enclosingScrollView?.contentView) }
    }

    private func observe(_ clip: NSClipView?) {
        guard clip !== clipView else { return }
        if let clipView {
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: clipView)
        }
        clipView = clip
        guard let clip else { return }
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipViewMoved(_:)),
            name: NSView.boundsDidChangeNotification, object: clip
        )
    }

    @objc private func clipViewMoved(_ note: Notification) {
        // Never while a button is held: a drag that began on a row keeps it.
        guard NSEvent.pressedMouseButtons == 0 else {
            finish()
            return
        }
        if !isScrolling {
            isScrolling = true
            onChange?(true)
            watchForClicks()
        }
        // One timer, pushed back on every movement, rather than a new one
        // per frame.
        if let settleTimer {
            settleTimer.fireDate = Date(timeIntervalSinceNow: Self.settle)
        } else {
            let timer = Timer(timeInterval: Self.settle, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish() }
            }
            RunLoop.main.add(timer, forMode: .common)
            settleTimer = timer
        }
    }

    /// A click as the list comes to rest — a tap on the trackpad to stop it
    /// gliding, say — ends the pause before the click is delivered, so it
    /// reaches the row under it.
    private func watchForClicks() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.window else { return }
                self.finish()
                // Applies the change now, ahead of this click, rather than at
                // the next screen refresh.
                self.window?.contentView?.layoutSubtreeIfNeeded()
            }
            return event
        }
    }

    private func finish() {
        settleTimer?.invalidate()
        settleTimer = nil
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        guard isScrolling else { return }
        isScrolling = false
        onChange?(false)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        settleTimer?.invalidate()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    }
}
