//
//  DiffRawTextView.swift
//  SwiftMediaInfo
//
//  Compare Mode's Text and Raw Text: the report with differing lines
//  highlighted (TextDiff in MediaInfoUtilities classifies each line), with
//  search highlights on top while searching.
//

import SwiftUI
import AppKit

// MARK: - Diff Raw Text View (line-by-line diff for text/rawText modes)

struct DiffRawTextView: NSViewRepresentable {
    let content: String
    let otherContent: String
    let isFileB: Bool
    @EnvironmentObject var store: MediaStore
    
    private var dropTarget: FileDropTarget { isFileB ? .fileB : .fileA }
    
    class Coordinator {
        var lastContent: String = ""
        var lastOtherContent: String = ""
        var lastFontSize: Double = 0
        var lastQuery: String = ""
        var lastIndex: Int = -1
        /// The track this pane has already scrolled to, so a focus request is
        /// acted on once rather than on every subsequent update.
        var lastFocusedID: String? = nil
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = FileDropScrollView.make(richText: true)
        scrollView.configureDrop(target: dropTarget, store: store)
        return scrollView
    }
    
    /// Scrolls a track's heading into view and flashes it.
    ///
    /// The heading is placed near the top rather than merely made visible: a
    /// section scrolled to the bottom edge is technically on screen and useless,
    /// since everything belonging to it is still below the fold.
    ///
    /// `showFindIndicator` is AppKit's own highlight — the same animated badge
    /// Find uses. Native, self-dismissing, and nothing to clean up afterwards.
    private static func reveal(trackID: String, in textView: NSTextView, text: String) {
        guard let range = MediaComparison.range(ofTrackID: trackID, in: text),
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }
        
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: range,
            actualCharacterRange: nil
        )
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        rect.origin.y -= textView.textContainerInset.height
        
        // Leave a little room above so the heading isn't flush against the edge.
        let target = NSRect(
            x: 0,
            y: max(rect.minY - 12, 0),
            width: 1,
            height: textView.enclosingScrollView?.contentSize.height ?? rect.height
        )
        
        textView.scrollToVisible(target)
        textView.showFindIndicator(for: range)
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = FileDropScrollView.textView(in: scrollView) else { return }
        
        (scrollView as? FileDropScrollView)?.configureDrop(target: dropTarget, store: store)
        
        let coord = context.coordinator
        let query = store.showSearchBar ? store.searchQuery : ""
        let fontSize = store.fontSize
        
        // Handled before the change guard below, because a focus request on its
        // own changes none of the values that guard tests — the text is already
        // correct, it just isn't on screen.
        if let focusID = store.focusedComparisonTrackID {
            if coord.lastFocusedID != focusID {
                coord.lastFocusedID = focusID
                let text = content
                DispatchQueue.main.async {
                    Self.reveal(trackID: focusID, in: textView, text: text)
                }
            }
        } else {
            coord.lastFocusedID = nil
        }
        
        let contentChanged = coord.lastContent != content || coord.lastOtherContent != otherContent
        let fontChanged = coord.lastFontSize != fontSize
        let queryChanged = coord.lastQuery != query
        let indexChanged = coord.lastIndex != store.searchMatchIndex
        
        guard contentChanged || fontChanged || queryChanged || indexChanged else { return }
        
        let needsFullRebuild = contentChanged || fontChanged || queryChanged
        
        if needsFullRebuild {
            coord.lastContent = content
            coord.lastOtherContent = otherContent
            coord.lastFontSize = fontSize
            coord.lastQuery = query
        }
        
        let font = NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        
        let myLines    = content.components(separatedBy: "\n")
        let otherLines = otherContent.components(separatedBy: "\n")
        
        // Matched by section and field, not by line position — see TextDiff.
        let kinds = TextDiff.classify(myLines, against: otherLines)
        
        let attrStr = NSMutableAttributedString()
        
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        
        let modifiedBg    = NSColor(Color.orange.opacity(0.12))
        let modifiedFg    = NSColor(Color(red: 0.85, green: 0.50, blue: 0.10))
        let onlyInThisBg  = NSColor((isFileB ? Color.brandPink : Color.brandBlue).opacity(0.10))
        let onlyInThisFg  = NSColor(isFileB ? Color.brandPink : Color.brandBlue)
        
        for (i, line) in myLines.enumerated() {
            let lineText = line + (i < myLines.count - 1 ? "\n" : "")
            var attrs = normalAttrs
            
            switch kinds[i] {
            case .unchanged:
                break
            case .modified:
                attrs[.backgroundColor] = modifiedBg
                attrs[.foregroundColor] = modifiedFg
            case .onlyInThis:
                attrs[.backgroundColor] = onlyInThisBg
                attrs[.foregroundColor] = onlyInThisFg
            }
            
            attrStr.append(NSAttributedString(string: lineText, attributes: attrs))
        }
        
        // Overlay search highlights on top of diff colors
        var searchRanges: [NSRange] = []
        if !query.isEmpty {
            let fullText = attrStr.string
            
            // Try exact match first
            searchRanges = findNSRanges(of: query, in: fullText)
            
            // If no exact matches, try space-normalized
            if searchRanges.isEmpty {
                let qNorm = query.lowercased().replacingOccurrences(of: " ", with: "")
                let lower = fullText.lowercased()
                var indexMap: [Int] = []
                for (i, char) in lower.enumerated() {
                    if char != " " { indexMap.append(i) }
                }
                let normalized = lower.replacingOccurrences(of: " ", with: "")
                let nsNorm = normalized as NSString
                var sr = NSRange(location: 0, length: nsNorm.length)
                
                while sr.location < nsNorm.length {
                    let found = nsNorm.range(of: qNorm, options: [], range: sr)
                    if found.location == NSNotFound { break }
                    let origStart = found.location < indexMap.count ? indexMap[found.location] : found.location
                    let origEndIdx = found.location + found.length - 1
                    let origEnd = origEndIdx < indexMap.count ? indexMap[origEndIdx] + 1 : origStart + found.length
                    searchRanges.append(NSRange(location: origStart, length: origEnd - origStart))
                    sr.location = found.location + found.length
                    sr.length = nsNorm.length - sr.location
                }
            }
            
            let highlightBg = NSColor(Color.brandGreen.opacity(0.3))
            let activeBg    = NSColor(Color.brandGreen.opacity(0.6))
            
            for (idx, range) in searchRanges.enumerated() {
                if idx == store.searchMatchIndex {
                    attrStr.addAttribute(.backgroundColor, value: activeBg, range: range)
                } else {
                    attrStr.addAttribute(.backgroundColor, value: highlightBg, range: range)
                }
            }
            
            if queryChanged {
                DispatchQueue.main.async {
                    self.store.searchMatchCount = searchRanges.count
                }
            }
        }
        
        textView.textStorage?.setAttributedString(attrStr)
        
        // Only scroll when index actually changed
        if indexChanged {
            coord.lastIndex = store.searchMatchIndex
            if !searchRanges.isEmpty && store.searchMatchIndex < searchRanges.count {
                textView.scrollRangeToVisible(searchRanges[store.searchMatchIndex])
            }
        }
    }
}
