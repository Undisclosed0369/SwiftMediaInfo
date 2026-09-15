//
//  RawTextView.swift
//  SwiftMediaInfo
//
//  PHASE 5 — accepts dropped files.
//
//  NSTextView registers for file drags by default, even when read-only, so
//  this pane silently swallowed every drop. That's why dragging a file onto
//  the window worked in Easy View (pure SwiftUI) and nowhere else.
//
//  The shared FileDropScrollView handles it now and reports which pane it
//  belongs to, so in Compare Mode a drop lands where it was aimed.
//

import SwiftUI
import AppKit

struct RawTextView: NSViewRepresentable {
    let content: String
    /// Which pane this instance is rendering, so drops route correctly.
    var dropTarget: FileDropTarget = .main
    
    @EnvironmentObject var store: MediaStore
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = FileDropScrollView.make(richText: false)
        scrollView.configureDrop(target: dropTarget, store: store)
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = FileDropScrollView.textView(in: scrollView) else { return }
        
        // The pane a view belongs to can change when Compare Mode is entered
        // or left, so this is refreshed rather than set once.
        (scrollView as? FileDropScrollView)?.configureDrop(target: dropTarget, store: store)
        
        let font = NSFont.monospacedSystemFont(
            ofSize: CGFloat(store.fontSize),
            weight: .regular
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font:            font,
            .foregroundColor: NSColor.labelColor
        ]
        
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: content, attributes: attributes)
        )
    }
}
