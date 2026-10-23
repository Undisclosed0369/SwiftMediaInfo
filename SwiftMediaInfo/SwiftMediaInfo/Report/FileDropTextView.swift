//
//  FileDropTextView.swift
//  SwiftMediaInfo
//
//  File drops for the AppKit-backed panes: the drop targets and Compare
//  Mode's three zones (FileDropTarget, CompareDropGeometry), the shared
//  drop helpers (FileDropSupport), the handler both AppKit panes use
//  (FileDropHandler) and the text panes' scroll view (FileDropScrollView).
//
//  WHY THIS EXISTS
//
//  Easy View is pure SwiftUI, so SwiftUI's own drop target sees a drag.
//  Every other view is backed by an AppKit view — NSTextView for Text, Raw
//  Text, XML and JSON, WKWebView for HTML — and AppKit views registered for
//  dragged types consume the drag before SwiftUI is consulted. NSTextView
//  registers for file drags by default, even when read-only.
//
//  HOW IT WORKS
//
//  The text view is unregistered and its enclosing scroll view is registered
//  instead. AppKit delivers a drag to the deepest *registered* view under the
//  cursor, so resolution stays inside one view hierarchy — no reliance on a
//  refused drag being re-offered to an ancestor, which AppKit does not promise.
//  The text view itself is still built by NSTextView.scrollableTextView(),
//  whose layout behaviour is known-good.
//
//  THREE-ZONE RESOLUTION
//
//  In Compare Mode a pane holds more than one destination: its own file, and
//  the centre card straddling the divider. Each pane classifies the cursor in
//  its own local coordinates using CompareDropGeometry, which is also what
//  sizes the card that gets drawn — so what you see and what you hit are the
//  same rectangle.
//
//  STALE PANES
//
//  A view configured as a Compare pane can outlive Compare Mode. Such a view
//  resolves to `.main` rather than refusing the drag: refusing left the drop
//  unhandled in panes that have no other handler, because SwiftUI does not pass
//  a declined drop up to an ancestor. Behaving as the window-wide target is
//  correct either way and needs no assumption about teardown timing.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drop destination

/// Which pane a dropped file should open into.
///
/// Also drives the drop highlight, so the correct zone lights up in its own
/// colour instead of the whole window turning violet.
enum FileDropTarget: Equatable {
    /// Single-file mode — the main window.
    case main
    /// Compare Mode, left pane.
    case fileA
    /// Compare Mode, right pane.
    case fileB
    /// Compare Mode, the centre zone: open the file on its own and leave
    /// Compare Mode entirely.
    case newFile
    
    /// Highlight colour for this destination.
    ///
    /// Green for the centre because blue and pink are already spoken for by
    /// File A and File B, and a third zone sharing either one's colour would be
    /// worse than no colour at all.
    var tint: Color {
        switch self {
        case .main:    return .brandViolet
        case .fileA:   return .brandBlue
        case .fileB:   return .brandPink
        case .newFile: return .brandGreen
        }
    }
    
    var message: String {
        switch self {
        case .main:    return "Drop to open"
        case .fileA:   return "Drop to replace File A"
        case .fileB:   return "Drop to replace File B"
        case .newFile: return "Open on its own"
        }
    }
}

// MARK: - Compare-mode drop geometry

/// Which of the three Compare Mode drop zones a point falls in.
enum CompareDropZone: Equatable {
    /// The pane the cursor is over.
    case pane
    /// The centre card straddling the divider.
    case centre
    /// The ring of unclaimed space around the centre card.
    ///
    /// Without it the boundary between "replace File B" and "leave Compare
    /// Mode" would be a single pixel, and a near-miss would silently do the
    /// opposite of what was intended. A moment with nothing highlighted is a
    /// far better outcome than confident wrongness.
    case neutral
}

/// Shared geometry for the three-zone drop in Compare Mode.
///
/// Both the AppKit panes (which resolve drags themselves) and the SwiftUI panes
/// read these numbers, and so does the card that gets drawn. Defining them once
/// is what keeps the thing you see and the thing you hit identical.
enum CompareDropGeometry {
    
    /// Total size of the centre card, straddling the divider.
    static let cardWidth: CGFloat  = 320
    static let cardHeight: CGFloat = 140
    
    /// Unclaimed margin around the card.
    static let deadZone: CGFloat = 12
    
    /// Half the card reaches into each pane.
    static var reachIntoPane: CGFloat { cardWidth / 2 }
    static var halfHeight: CGFloat { cardHeight / 2 }
    
    /// Classifies a point given in a pane's own coordinates.
    ///
    /// Distance is measured from the pane's *inner* edge — the divider — so
    /// each pane decides locally, with no shared coordinate space and no
    /// flipped-origin conversion to get wrong. Vertical position uses distance
    /// from the pane's centre, which is symmetric and therefore identical
    /// whether the view is flipped or not.
    static func zone(
        localPoint point: CGPoint,
        paneSize: CGSize,
        isLeftPane: Bool
    ) -> CompareDropZone {
        guard paneSize.width > 0, paneSize.height > 0 else { return .pane }
        
        let distanceFromDivider = isLeftPane
        ? paneSize.width - point.x
        : point.x
        
        let distanceFromMiddle = abs(point.y - paneSize.height / 2)
        
        if distanceFromDivider <= reachIntoPane,
           distanceFromMiddle <= halfHeight {
            return .centre
        }
        
        if distanceFromDivider <= reachIntoPane + deadZone,
           distanceFromMiddle <= halfHeight + deadZone {
            return .neutral
        }
        
        return .pane
    }
}

// MARK: - Drop handling

/// Shared drag-destination behaviour for the AppKit views this app embeds.
///
/// Kept in one place so NSTextView and WKWebView can't drift apart in how they
/// treat a drag — earlier bugs came from exactly that kind of drift.
enum FileDropSupport {
    
    /// True while one of the app's own tabs is being dragged. The drag
    /// carries the tab's file, so without this every drop target in the
    /// window would treat a tab passing over it as a file arriving.
    @MainActor static var isTabDragActive = false
    
    /// Reads the first dropped file URL, if the drag carries one.
    static func firstFileURL(from sender: NSDraggingInfo) -> URL? {
        fileURLs(from: sender).first
    }
    
    /// Every dropped file URL, in the order they were dragged.
    static func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        
        return sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] ?? []
    }
    
    /// The same, from SwiftUI's item providers, keeping the drag's order.
    @MainActor
    static func fileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
               let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                urls.append(url)
            }
        }
        return urls
    }
    
    /// Routes dropped files. Several at once follow the drop rules — two
    /// compare, three or more open a tab each, a folder opens a folder tab —
    /// wherever they land. One file keeps the pane-by-pane behaviour below.
    @MainActor
    static func deliver(_ urls: [URL], to target: FileDropTarget, store: MediaStore) {
        if urls.count > 1 {
            if target == .newFile { store.exitCompareMode() }
            store.openDropped(urls)
        } else if let url = urls.first {
            deliver(url, to: target, store: store)
        }
    }
    
    /// Routes a dropped file to the right destination.
    @MainActor
    static func deliver(_ url: URL, to target: FileDropTarget, store: MediaStore) {
        // A pane destination only means anything while Compare Mode is on.
        //
        // This guard exists because a `.fileB` drop was still being delivered
        // after Compare Mode had been exited — turning it back on and pushing
        // the file into a comparison the user had already dismissed. A target
        // captured when a view was configured is a statement about the past;
        // the drop happens in the present, so it is validated here.
        //
        // Routed through `openDropped` so an Option-drop onto a
        // single-file window enters Compare Mode. Every pane goes through this
        // one function, so the gesture works on every tab rather than only the
        // pure-SwiftUI one.
        guard store.isCompareMode else {
            store.openDropped(url)
            return
        }
        
        switch target {
        case .main, .fileA:
            store.openURL(url)
            
        case .fileB:
            store.openCompareURL(url)
            
        case .newFile:
            // Leave Compare Mode first so the incoming file lands in a clean
            // single-file window rather than replacing one side of a
            // comparison the user is abandoning anyway.
            store.exitCompareMode()
            store.openURL(url)
        }
    }
    
    /// Resolves the destination for a drag inside a pane.
    ///
    /// Returns nil while the cursor sits in the dead zone, so nothing lights up
    /// and nothing would be accepted there.
    @MainActor
    static func resolveTarget(
        paneTarget: FileDropTarget,
        localPoint: CGPoint,
        paneSize: CGSize,
        centreAvailable: Bool
    ) -> FileDropTarget? {
        guard centreAvailable,
              paneTarget == .fileA || paneTarget == .fileB else {
            return paneTarget
        }
        
        switch CompareDropGeometry.zone(
            localPoint: localPoint,
            paneSize: paneSize,
            isLeftPane: paneTarget == .fileA
        ) {
        case .pane:    return paneTarget
        case .centre:  return .newFile
        case .neutral: return nil
        }
    }
}

// MARK: - Drop handling

/// How an AppKit pane takes a dropped file: which zone the cursor is in, the
/// highlight to show for it, and where the file goes. Shared by the text
/// panes' scroll view and the HTML pane's web view, which forward their
/// dragging calls here — one copy, so the two can't drift apart in how they
/// treat a drag.
@MainActor
final class FileDropHandler {

    private weak var view: NSView?

    /// Where a file dropped here should go, before zone resolution.
    /// Refreshed on every update, since entering or leaving Compare Mode
    /// changes which pane a view represents.
    private var dropTarget: FileDropTarget = .main

    /// Whether the centre "open on its own" zone applies here.
    private var centreZoneAvailable = false

    /// Refreshed on every update. When false, this view was configured as a
    /// Compare pane and has outlived Compare Mode, so its stored target no
    /// longer refers to anything.
    private var isPaneLive = true

    /// Called with the dropped file URLs and their resolved destination.
    private var onFileDrop: (([URL], FileDropTarget) -> Void)?

    /// Called as the resolved destination changes, so the matching zone can
    /// show a highlight. Nil means nothing should be highlighted.
    private var onDragStateChange: ((FileDropTarget?) -> Void)?

    /// Called when a drag begins or ends here, so the centre card can be shown
    /// for the whole duration of the drag.
    private var onDragSessionChange: ((Bool) -> Void)?

    init(view: NSView) {
        self.view = view
    }

    // MARK: Drag destination

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !FileDropSupport.isTabDragActive,
              FileDropSupport.firstFileURL(from: sender) != nil else { return [] }
        onDragSessionChange?(true)
        notify(resolvedTarget(for: sender))
        return .copy
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !FileDropSupport.isTabDragActive,
              FileDropSupport.firstFileURL(from: sender) != nil else { return [] }
        // Re-resolved continuously: the destination depends on where the cursor
        // is, not merely on which pane it entered.
        notify(resolvedTarget(for: sender))
        return .copy
    }

    func draggingExited() {
        notify(nil)
        onDragSessionChange?(false)
    }

    func draggingEnded() {
        notify(nil)
        onDragSessionChange?(false)
    }

    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        FileDropSupport.firstFileURL(from: sender) != nil
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = FileDropSupport.fileURLs(from: sender)
        guard !urls.isEmpty,
              let target = resolvedTarget(for: sender) else {
            // Dead zone — accept nothing rather than guess.
            notify(nil)
            onDragSessionChange?(false)
            return false
        }

        notify(nil)
        onDragSessionChange?(false)

        DispatchQueue.main.async { [weak self] in
            self?.onFileDrop?(urls, target)
        }
        return true
    }

    /// Which zone the cursor currently sits in, in the view's own coordinates.
    private func resolvedTarget(for sender: NSDraggingInfo) -> FileDropTarget? {
        // A view configured as a Compare pane that has outlived Compare Mode
        // behaves as the window-wide target rather than refusing the drag.
        // Refusing left the drop unhandled in panes with no other handler.
        guard isPaneLive else { return .main }
        guard let view else { return nil }

        let point = view.convert(sender.draggingLocation, from: nil)
        return FileDropSupport.resolveTarget(
            paneTarget: dropTarget,
            localPoint: point,
            paneSize: view.bounds.size,
            centreAvailable: centreZoneAvailable
        )
    }

    private func notify(_ target: FileDropTarget?) {
        DispatchQueue.main.async { [weak self] in
            self?.onDragStateChange?(target)
        }
    }

    // MARK: Configuration

    /// Wires the drop callbacks to the store for a given destination.
    func configure(target: FileDropTarget, store: MediaStore) {
        dropTarget = target
        centreZoneAvailable = store.isCentreDropAvailable

        // A pane target is only valid while Compare Mode is on. `.main` is
        // always valid, since it means the single-file window.
        isPaneLive = (target == .main) || store.isCompareMode

        // Highlight ownership follows the *effective* target, so a stale pane
        // claims and releases the window-wide highlight rather than a pane
        // highlight that no longer exists.
        let owner: FileDropTarget = isPaneLive ? target : .main

        onFileDrop = { [owner] urls, destination in
            store.reportDropTarget(nil, from: owner)
            store.endDragSession(from: owner)
            FileDropSupport.deliver(urls, to: destination, store: store)
        }

        onDragStateChange = { [owner] destination in
            store.reportDropTarget(destination, from: owner)
        }

        onDragSessionChange = { [owner] isActive in
            if isActive {
                store.beginDragSession()
            } else {
                store.endDragSession(from: owner)
            }
        }
    }
}

// MARK: - Scroll view

/// Scroll view that accepts dropped files on behalf of the text view it
/// contains.
final class FileDropScrollView: NSScrollView {
    
    private lazy var drops = FileDropHandler(view: self)
    
    // MARK: Drag destination
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        drops.draggingEntered(sender)
    }
    
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        drops.draggingUpdated(sender)
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        drops.draggingExited()
    }
    
    override func draggingEnded(_ sender: NSDraggingInfo) {
        drops.draggingEnded()
    }
    
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        drops.prepareForDragOperation(sender)
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        drops.performDragOperation(sender)
    }
    
    // MARK: - Construction
    
    /// Builds a read-only, transparent, scrollable text view configured the way
    /// every text pane in this app needs it.
    ///
    /// Each pane previously repeated the same eight lines of setup, which is
    /// how they drifted into subtly different behaviour.
    static func make(richText: Bool) -> FileDropScrollView {
        let source = NSTextView.scrollableTextView()
        guard let textView = source.documentView as? NSTextView else {
            return FileDropScrollView()
        }
        
        textView.isEditable         = false
        textView.isRichText         = richText
        textView.backgroundColor    = .clear
        textView.drawsBackground    = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isSelectable       = true
        textView.usesFontPanel      = false
        textView.usesRuler          = false
        
        // NSTextView registers for file drags by default, even when read-only,
        // and would otherwise consume every drop before anything else saw it.
        textView.unregisterDraggedTypes()
        
        let scrollView = FileDropScrollView()
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers    = true
        scrollView.drawsBackground       = false
        scrollView.borderType            = .noBorder
        scrollView.documentView          = textView
        scrollView.registerForDraggedTypes([.fileURL])
        
        return scrollView
    }
    
    /// The text view this scroll view contains.
    static func textView(in scrollView: NSScrollView) -> NSTextView? {
        scrollView.documentView as? NSTextView
    }
    
    /// Wires the drop callbacks to the store for a given destination.
    @MainActor
    func configureDrop(target: FileDropTarget, store: MediaStore) {
        drops.configure(target: target, store: store)
    }
}
