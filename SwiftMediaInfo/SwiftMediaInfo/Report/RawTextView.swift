//
//  RawTextView.swift
//  SwiftMediaInfo
//
//  The Text, Raw Text, XML and JSON views: MediaInfo's output in a
//  read-only NSTextView, syntax-highlighted for JSON and XML
//  (SyntaxHighlighter), at the app's zoom. While searching,
//  FilterableRawTextView (SearchBarView) takes its place.
//
//  It lives in a FileDropScrollView, because a read-only NSTextView still
//  swallows file drops; the scroll view takes them instead and reports which
//  pane it belongs to, so in Compare Mode a drop lands where it was aimed.
//  The text is only re-set when it changes, which keeps large reports fast.
//

import SwiftUI
import AppKit

struct RawTextView: NSViewRepresentable {
    let content: String
    /// Which pane this instance is rendering, so drops route correctly.
    var dropTarget: FileDropTarget = .main
    /// Set for the JSON and XML views, which are syntax highlighted.
    var language: CodeLanguage? = nil
    
    @EnvironmentObject var store: MediaStore
    @AppStorage(SyntaxHighlighting.key) private var highlighting = SyntaxHighlighting.shippedDefault.rawValue
    
    /// The language actually applied, after Settings › Appearance › Syntax
    /// Highlighting has had its say.
    private var effectiveLanguage: CodeLanguage? {
        (SyntaxHighlighting(rawValue: highlighting) ?? .shippedDefault).language(language)
    }
    
    /// What the text was last built from. The text used to be rebuilt on
    /// every SwiftUI update — harmless for plain text, but highlighting a
    /// large JSON report on every hover or tab-bar redraw is not.
    final class Coordinator {
        var content: String?
        var fontSize: Double = 0
        var language: CodeLanguage?
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = FileDropScrollView.make(richText: effectiveLanguage != nil)
        scrollView.configureDrop(target: dropTarget, store: store)
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = FileDropScrollView.textView(in: scrollView) else { return }
        
        // The pane a view belongs to can change when Compare Mode is entered
        // or left, so this is refreshed rather than set once.
        (scrollView as? FileDropScrollView)?.configureDrop(target: dropTarget, store: store)
        
        let language = effectiveLanguage
        textView.isRichText = language != nil
        
        let coordinator = context.coordinator
        guard coordinator.content != content
                || coordinator.fontSize != store.fontSize
                || coordinator.language != language else { return }
        coordinator.content = content
        coordinator.fontSize = store.fontSize
        coordinator.language = language
        
        let font = NSFont.monospacedSystemFont(
            ofSize: CGFloat(store.fontSize),
            weight: .regular
        )
        
        if let language {
            // Colours are dynamic, so light/dark changes need no rebuild.
            textView.textStorage?.setAttributedString(
                SyntaxHighlighter.attributedString(content, language: language, font: font)
            )
        } else {
            textView.textStorage?.setAttributedString(
                NSAttributedString(string: content, attributes: [
                    .font:            font,
                    .foregroundColor: NSColor.labelColor
                ])
            )
        }
    }
}
