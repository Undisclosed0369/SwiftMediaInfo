//
//  HTMLView.swift
//  SwiftMediaInfo
//

import SwiftUI
import AppKit

struct HTMLView: NSViewRepresentable {
    
    let htmlString: String
    @EnvironmentObject var store: MediaStore
    
    // 1. Let SwiftUI directly control the color scheme detection
    @Environment(\.colorScheme) var colorScheme
    
    class Coordinator {
        /// The raw HTML + dark-mode combination that was last parsed.
        var cachedSourceKey: String = ""
        /// The parsed result at its original font sizes (before scaling).
        var cachedBaseParsed: NSMutableAttributedString?
        /// The font size last applied (so we only re-scale when zoom changes).
        var cachedFontSize: Double = 0
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        
        textView.textContainer?.lineFragmentPadding = 0
        
        textView.isEditable = false
        textView.isRichText = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isSelectable = true
        
        textView.textContainerInset = NSSize(width: 12, height: 12)
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        let availableWidth = scrollView.contentSize.width
        
        textView.frame = CGRect(
            x: 0,
            y: 0,
            width: availableWidth,
            height: textView.frame.height
        )
        
        textView.textContainer?.containerSize = CGSize(
            width: availableWidth,
            height: .greatestFiniteMagnitude
        )
        
        // 2. Determine dark mode using the SwiftUI Environment
        let isDark = colorScheme == .dark
        
        // Build a cache key from the raw HTML + color scheme.
        // Font size is NOT part of this key — we re-scale cheaply below.
        let sourceKey = "\(isDark)|\(htmlString)"
        
        let coord = context.coordinator
        
        // Layer 1: Re-parse only when the HTML content or color scheme changes.
        if coord.cachedSourceKey != sourceKey {
            let styled = styledHTML(htmlString, isDark: isDark)
            guard let data = styled.data(using: .utf8) else { return }
            
            let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]
            
            if let attrStr = try? NSMutableAttributedString(
                data: data,
                options: opts,
                documentAttributes: nil
            ) {
                // Fix dark-mode colours (Apple's HTML parser defaults to black)
                if isDark {
                    let fullRange = NSRange(location: 0, length: attrStr.length)
                    attrStr.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
                        if let color = value as? NSColor,
                           color.cgColor.components?.first == 0.0 {
                            attrStr.addAttribute(.foregroundColor, value: NSColor.white, range: range)
                        } else if value == nil {
                            attrStr.addAttribute(.foregroundColor, value: NSColor.white, range: range)
                        }
                    }
                }
                
                coord.cachedSourceKey = sourceKey
                coord.cachedBaseParsed = attrStr
                coord.cachedFontSize = 0  // force font scaling below
            }
        }
        
        guard let baseParsed = coord.cachedBaseParsed else { return }
        
        // Layer 2: Re-scale fonts only when zoom level changes (cheap pass).
        if coord.cachedFontSize != store.fontSize {
            let fullRange = NSRange(location: 0, length: baseParsed.length)
            baseParsed.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
                if let oldFont = value as? NSFont {
                    let newFont = NSFont(
                        descriptor: oldFont.fontDescriptor,
                        size: CGFloat(store.fontSize)
                    ) ?? oldFont
                    baseParsed.addAttribute(.font, value: newFont, range: range)
                }
            }
            coord.cachedFontSize = store.fontSize
        }
        
        textView.textStorage?.setAttributedString(baseParsed)
    }
    
    // 4. Pass the boolean down instead of relying on the NSView appearance
    private func styledHTML(_ raw: String, isDark: Bool) -> String {
        
        let bg = isDark ? "#1e1e1e" : "#ffffff"
        let fg = isDark ? "#ffffff" : "#000000"
        let border = isDark ? "#444444" : "#cccccc"
        let header = isDark ? "#2a2a2a" : "#f5f5f5"
        
        let style = """
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            font-size: 12px;
            margin: 0;
            padding: 0;
            background: \(bg);
            color: \(fg);
        }
        
        table {
            border-collapse: collapse;
            width: 100%;
        }
        
        td, th {
            padding: 4px 8px;
            border: 1px solid \(border);
            color: \(fg);
        }
        
        th {
            font-weight: 600;
            background: \(header);
            color: \(fg);
        }
        </style>
        """
        
        var html = raw
        
        if let r = html.range(of: "</head>") {
            html.insert(contentsOf: style, at: r.lowerBound)
        } else if let r = html.range(of: "<body") {
            html.insert(contentsOf: style, at: r.lowerBound)
        } else {
            html = "<html><head>\(style)</head><body>\(html)</body></html>"
        }
        
        return html
    }
}
