//
//  HTMLView.swift
//  SwiftMediaInfo
//
//  Uses WKWebView for proper HTML rendering with CSS-level zoom scaling.
//  Tables, borders, padding, and typography all scale proportionally.
//

import SwiftUI
import WebKit

struct HTMLView: NSViewRepresentable {
    
    let htmlString: String
    @EnvironmentObject var store: MediaStore
    @Environment(\.colorScheme) var colorScheme
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        var cachedSourceKey: String = ""
        var cachedFontSize: Double = 0
        var cachedSearchQuery: String = ""
        weak var webView: WKWebView?
        var store: MediaStore?
        
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            // Receive match count from JS
            if message.name == "searchResults",
               let count = message.body as? Int {
                DispatchQueue.main.async {
                    self.store?.searchMatchCount = count
                    if count > 0 && (self.store?.searchMatchIndex ?? 0) >= count {
                        self.store?.searchMatchIndex = 0
                    }
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        
        // Add message handler for search result count
        config.userContentController.add(context.coordinator, name: "searchResults")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        context.coordinator.store = store
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        let isDark = colorScheme == .dark
        let sourceKey = "\(isDark)|\(htmlString)"
        let coord = context.coordinator
        coord.store = store
        
        let needsReload = coord.cachedSourceKey != sourceKey
        let needsZoom   = coord.cachedFontSize != store.fontSize
        
        if needsReload {
            let fullHTML = buildStyledHTML(htmlString, isDark: isDark, fontSize: store.fontSize)
            webView.loadHTMLString(fullHTML, baseURL: nil)
            coord.cachedSourceKey = sourceKey
            coord.cachedFontSize  = store.fontSize
            coord.cachedSearchQuery = ""
            
            // Re-apply search after page loads
            if store.showSearchBar && !store.searchQuery.isEmpty {
                let query = store.searchQuery
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.performSearch(in: webView, query: query, index: self.store.searchMatchIndex)
                }
            }
        } else if needsZoom {
            let zoomPercent = (store.fontSize / 12.0) * 100.0
            webView.evaluateJavaScript(
                "document.body.style.zoom = '\(zoomPercent)%';",
                completionHandler: nil
            )
            coord.cachedFontSize = store.fontSize
        }
        
        // Handle search query changes
        let currentQuery = store.showSearchBar ? store.searchQuery : ""
        if coord.cachedSearchQuery != currentQuery {
            coord.cachedSearchQuery = currentQuery
            if currentQuery.isEmpty {
                clearSearch(in: webView)
            } else {
                performSearch(in: webView, query: currentQuery, index: store.searchMatchIndex)
            }
        }
        
        // Handle search index navigation
        if !currentQuery.isEmpty && store.searchMatchCount > 0 {
            scrollToMatch(in: webView, index: store.searchMatchIndex)
        }
    }
    
    // MARK: - JavaScript search helpers
    
    private func performSearch(in webView: WKWebView, query: String, index: Int) {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "")
        
        let js = """
        (function() {
            // Remove previous highlights
            document.querySelectorAll('.smi-highlight').forEach(el => {
                el.outerHTML = el.textContent;
            });
            
            var query = '\(escaped)'.toLowerCase();
            var queryNorm = query.replace(/\\s+/g, '');
            if (!query) { window.webkit.messageHandlers.searchResults.postMessage(0); return; }
            
            var body = document.body;
            var walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT, null, false);
            var matches = [];
            var node;
            
            while (node = walker.nextNode()) {
                var text = node.textContent;
                var lower = text.toLowerCase();
                
                // Try exact match first
                var idx = lower.indexOf(query);
                if (idx !== -1) {
                    matches.push({ node: node, index: idx, length: query.length, type: 'exact' });
                } else {
                    // Try normalized match (strip spaces from text)
                    var lowerNorm = lower.replace(/\\s+/g, '');
                    var nIdx = lowerNorm.indexOf(queryNorm);
                    if (nIdx !== -1) {
                        // Map normalized index back to original
                        var origIdx = 0, normCount = 0;
                        for (var ci = 0; ci < lower.length; ci++) {
                            if (lower[ci] !== ' ') {
                                if (normCount === nIdx) { origIdx = ci; break; }
                                normCount++;
                            }
                        }
                        // Find the end position
                        var endNorm = nIdx + queryNorm.length;
                        var origEnd = origIdx, nc2 = nIdx;
                        for (var ci2 = origIdx; ci2 < lower.length && nc2 < endNorm; ci2++) {
                            if (lower[ci2] !== ' ') nc2++;
                            origEnd = ci2 + 1;
                        }
                        matches.push({ node: node, index: origIdx, length: origEnd - origIdx, type: 'norm' });
                    }
                }
            }
            
            // Highlight all matches
            for (var i = matches.length - 1; i >= 0; i--) {
                var m = matches[i];
                var n = m.node;
                var text = n.textContent;
                var parent = n.parentNode;
                var frag = document.createDocumentFragment();
                
                // For this node, find all occurrences
                var lower = text.toLowerCase();
                var positions = [];
                
                if (m.type === 'exact') {
                    var pos = lower.indexOf(query);
                    while (pos !== -1) {
                        positions.push({ start: pos, length: query.length });
                        pos = lower.indexOf(query, pos + query.length);
                    }
                } else {
                    // Use the pre-computed position for normalized matches
                    positions.push({ start: m.index, length: m.length });
                }
                
                var lastIdx = 0;
                for (var p = 0; p < positions.length; p++) {
                    var pos = positions[p];
                    if (pos.start > lastIdx) {
                        frag.appendChild(document.createTextNode(text.substring(lastIdx, pos.start)));
                    }
                    var span = document.createElement('span');
                    span.className = 'smi-highlight';
                    span.textContent = text.substring(pos.start, pos.start + pos.length);
                    frag.appendChild(span);
                    lastIdx = pos.start + pos.length;
                }
                
                if (lastIdx < text.length) {
                    frag.appendChild(document.createTextNode(text.substring(lastIdx)));
                }
                
                parent.replaceChild(frag, n);
            }
            
            var allHighlights = document.querySelectorAll('.smi-highlight');
            window.webkit.messageHandlers.searchResults.postMessage(allHighlights.length);
            
            // Scroll to current match
            if (allHighlights.length > 0) {
                var idx = Math.min(\(index), allHighlights.length - 1);
                allHighlights.forEach((el, i) => {
                    el.classList.remove('smi-highlight-active');
                });
                allHighlights[idx].classList.add('smi-highlight-active');
                allHighlights[idx].scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
        })();
        """
        
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    
    private func scrollToMatch(in webView: WKWebView, index: Int) {
        let js = """
        (function() {
            var highlights = document.querySelectorAll('.smi-highlight');
            if (highlights.length === 0) return;
            var idx = Math.min(\(index), highlights.length - 1);
            highlights.forEach((el, i) => {
                el.classList.remove('smi-highlight-active');
            });
            highlights[idx].classList.add('smi-highlight-active');
            highlights[idx].scrollIntoView({ behavior: 'smooth', block: 'center' });
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    
    private func clearSearch(in webView: WKWebView) {
        let js = """
        (function() {
            document.querySelectorAll('.smi-highlight').forEach(el => {
                el.outerHTML = el.textContent;
            });
            window.webkit.messageHandlers.searchResults.postMessage(0);
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    
    // MARK: - Build full styled HTML document
    
    private func buildStyledHTML(_ raw: String, isDark: Bool, fontSize: Double) -> String {
        
        let zoomPercent = (fontSize / 12.0) * 100.0
        
        // ── Colour palette ──────────────────────────────────────────
        //  Dark mode mirrors light mode's clarity: solid backgrounds,
        //  high-contrast text, crisp borders.
        _           = isDark ? "#1e1e2e" : "#fafbfc"
        let fg           = isDark ? "#ededf5" : "#1a1a2e"
        let fgSecondary  = isDark ? "#d0d0e4" : "#3a3a5c"
        let border       = isDark ? "rgba(255,255,255,0.12)" : "rgba(0,0,0,0.10)"
        let headerBg     = isDark ? "rgba(255,255,255,0.05)" : "rgba(0,0,0,0.025)"
        let hoverBg      = isDark ? "rgba(130,100,255,0.10)" : "rgba(130,100,255,0.05)"
        let trackTitleBg = isDark ? "rgba(130,100,255,0.12)" : "rgba(130,100,255,0.07)"
        let trackBorder  = isDark ? "rgba(160,130,255,0.6)"  : "rgba(130,100,255,0.4)"
        let accent       = isDark ? "#c4b5fd" : "#7c3aed"
        let valueFg      = isDark ? "#f8f8ff" : "#111128"
        let tableBg      = isDark ? "rgba(30,30,50,0.95)"    : "#ffffff"
        let scrollTrack  = isDark ? "rgba(255,255,255,0.03)" : "rgba(0,0,0,0.02)"
        let scrollThumb  = isDark ? "rgba(255,255,255,0.15)" : "rgba(0,0,0,0.15)"
        
        let style = """
        <style>
        * {
            box-sizing: border-box;
        }
        
        ::-webkit-scrollbar {
            width: 8px;
            height: 8px;
        }
        ::-webkit-scrollbar-track {
            background: \(scrollTrack);
            border-radius: 4px;
        }
        ::-webkit-scrollbar-thumb {
            background: \(scrollThumb);
            border-radius: 4px;
        }
        ::-webkit-scrollbar-thumb:hover {
            background: \(isDark ? "rgba(255,255,255,0.2)" : "rgba(0,0,0,0.2)");
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
            font-size: 12px;
            line-height: 1.5;
            margin: 0;
            padding: 16px;
            background: transparent;
            color: \(fg);
            zoom: \(zoomPercent)%;
            -webkit-font-smoothing: antialiased;
        }
        
        /* ── Track section titles ──────────────────────────── */
        h2, h3, .track-title {
            font-size: 14px;
            font-weight: 700;
            letter-spacing: 0.03em;
            color: \(accent);
            margin: 24px 0 10px 0;
            padding: 10px 16px;
            background: \(trackTitleBg);
            border-left: 3px solid \(trackBorder);
            border-radius: 0 8px 8px 0;
        }
        h2:first-child, h3:first-child {
            margin-top: 0;
        }
        
        /* ── Tables ────────────────────────────────────────── */
        table {
            border-collapse: separate;
            border-spacing: 0;
            width: 100%;
            margin: 0 0 20px 0;
            border: 1px solid \(border);
            border-radius: 10px;
            overflow: hidden;
            background: \(tableBg);
            box-shadow: \(isDark ? "0 2px 8px rgba(0,0,0,0.3), 0 0 0 1px rgba(255,255,255,0.05)" : "0 1px 4px rgba(0,0,0,0.06)");
        }
        
        td, th {
            padding: 9px 16px;
            border-bottom: 1px solid \(border);
            text-align: left;
            vertical-align: top;
            transition: background 0.12s ease;
        }
        
        /* Remove bottom border on last row */
        tr:last-child td {
            border-bottom: none;
        }
        
        /* Field name column */
        td:first-child {
            font-weight: 600;
            font-size: 12.5px;
            color: \(fgSecondary);
            white-space: nowrap;
            width: 30%;
            min-width: 140px;
        }
        
        /* Value column */
        td:last-child {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            font-size: 12.5px;
            font-weight: 500;
            color: \(valueFg);
            word-break: break-word;
        }
        
        /* Header row */
        th {
            font-weight: 700;
            font-size: 11.5px;
            letter-spacing: 0.04em;
            text-transform: uppercase;
            background: \(headerBg);
            color: \(fgSecondary);
            border-bottom: 1px solid \(border);
        }
        
        /* Alternating row stripes */
        tr:nth-child(even) td {
            background: \(headerBg);
        }
        
        /* Hover */
        tr:hover td {
            background: \(hoverBg);
        }
        
        /* ── Links ─────────────────────────────────────────── */
        a {
            color: \(accent);
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
        
        /* ── Horizontal rules ──────────────────────────────── */
        hr {
            border: none;
            border-top: 1px solid \(border);
            margin: 16px 0;
        }
        
        /* ── Pre / code ────────────────────────────────────── */
        pre, code {
            font-family: "SF Mono", "Menlo", monospace;
            font-size: 11.5px;
            background: \(headerBg);
            border-radius: 4px;
            padding: 2px 5px;
        }
        pre {
            padding: 12px 14px;
            overflow-x: auto;
            border: 1px solid \(border);
        }
        
        /* ── Search highlights ─────────────────────────────── */
        .smi-highlight {
            background: \(isDark ? "rgba(74,222,128,0.3)" : "rgba(34,197,94,0.25)");
            border-radius: 3px;
            padding: 1px 2px;
            transition: background 0.15s ease;
        }
        .smi-highlight-active {
            background: \(isDark ? "rgba(74,222,128,0.6)" : "rgba(34,197,94,0.5)");
            outline: 2px solid \(isDark ? "#4ade80" : "#22c55e");
            outline-offset: 1px;
        }
        </style>
        """
        
        var html = raw
        
        if let r = html.range(of: "</head>") {
            html.insert(contentsOf: style, at: r.lowerBound)
        } else if let r = html.range(of: "<body") {
            html.insert(contentsOf: style, at: r.lowerBound)
        } else {
            html = """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            \(style)
            </head>
            <body>\(html)</body>
            </html>
            """
        }
        
        return html
    }
}
