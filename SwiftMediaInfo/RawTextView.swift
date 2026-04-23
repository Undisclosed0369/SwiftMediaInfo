//
//  RawTextView.swift
//  SwiftMediaInfo
//
//  Created by Undisclosed on 23/4/26.
//


//
//  RawTextView.swift
//  MediaInfoMac
//

import SwiftUI
import AppKit

struct RawTextView: NSViewRepresentable {
    let content: String
    @EnvironmentObject var store: MediaStore

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView   = scrollView.documentView as! NSTextView
        textView.isEditable         = false
        textView.isRichText         = false
        textView.backgroundColor    = .clear
        textView.drawsBackground    = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isSelectable       = true
        textView.usesFontPanel      = false
        textView.usesRuler          = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let font  = NSFont.monospacedSystemFont(ofSize: CGFloat(store.fontSize), weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            font,
            .foregroundColor: NSColor.labelColor
        ]
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: content, attributes: attrs)
        )
    }
}