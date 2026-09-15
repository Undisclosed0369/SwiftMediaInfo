//
//  HTMLView.swift
//  SwiftMediaInfo
//
//  Uses WKWebView for proper HTML rendering with CSS-level zoom scaling.
//  Tables, borders, padding, and typography all scale proportionally.
//
//  PHASE 5 — hardened.
//
//  This view renders HTML that MediaInfo generated from file metadata. Most of
//  that metadata comes from inside the media file itself, which means it is
//  attacker-controllable in principle: a crafted file can put arbitrary text
//  into a title or comment field, and that text ends up in the document.
//
//  Two changes close that off:
//
//  1. A navigation delegate. Previously any link in the document would
//     navigate inside the app's own web view, replacing the report with
//     whatever it pointed at, with no address bar and no way back. Now the
//     only navigation permitted is the initial in-memory load. Clicked links
//     open in the user's browser, where they belong, and only for http/https
//     and mailto — file:// and other schemes are refused outright.
//
//  2. File drops are handled here rather than swallowed. WKWebView claims
//     dragged files for itself, which is why the HTML tab was the one tab
//     that ignored them.
//
//  The `drawsBackground` KVC call remains, because WebKit still offers no
//  public way to make a web view transparent on macOS and the CSS-side
//  `background: transparent` only affects the page, not the view drawing it.
//
//  baseURL stays nil, which was already correct: it denies the document any
//  origin, so it cannot read local files or reach the network on its own.
//

import SwiftUI
import WebKit

struct HTMLView: NSViewRepresentable {
    
    let htmlString: String
    /// Which pane this instance is rendering, so dropped files route correctly.
    var dropTarget: FileDropTarget = .main
    @EnvironmentObject var store: MediaStore
    @Environment(\.colorScheme) var colorScheme
    
    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
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
        
        // MARK: - Navigation policy
        
        /// Only the initial in-memory document may load here. Anything the
        /// user clicks goes to their browser instead, so the report can never
        /// be silently replaced by remote content inside a chromeless view.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            
            // loadHTMLString(baseURL: nil) surfaces as about:blank.
            if url.absoluteString == "about:blank" {
                decisionHandler(.allow)
                return
            }
            
            decisionHandler(.cancel)
            
            // Hand off only schemes that make sense from a metadata report.
            // file:// is refused deliberately — a crafted media file should not
            // be able to make the app open arbitrary local paths.
            guard let scheme = url.scheme?.lowercased(),
                  ["http", "https", "mailto"].contains(scheme) else {
                return
            }
            
            NSWorkspace.shared.open(url)
        }
        
        /// New-window requests (target="_blank") never open a window here.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased(),
               ["http", "https", "mailto"].contains(scheme) {
                NSWorkspace.shared.open(url)
            }
            return nil
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
        
        // The document is generated locally and needs JavaScript only for the
        // search highlighting this view injects itself.
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        let webView = TransparentWebView(frame: .zero, configuration: config)
        
        // WebKit has no public switch for a transparent web view on macOS.
        // `underPageBackgroundColor` covers only the overscroll area, which is
        // why the margins around the tables stayed opaque when that was used
        // alone. The KVC call is the only thing that actually works.
        //
        // My previous attempt guarded it with `responds(to:)`. That silently
        // did nothing: `drawsBackground` is exposed to KVC but has no matching
        // Objective-C selector, so the check always failed. Calling it directly
        // is what v1.5 did and what works.
        webView.underPageBackgroundColor = .clear
        webView.setValue(false, forKey: "drawsBackground")
        
        // Forward file drops to the app. WKWebView claims dragged files for
        // itself, so simply unregistering the types was not enough — the drop
        // never reached the SwiftUI handler beneath. Handling it here and
        // calling back into the store is direct and reliable.
        webView.configureDrop(target: dropTarget, store: store)
        
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.allowsMagnification = false
        
        context.coordinator.webView = webView
        context.coordinator.store = store
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // Entering or leaving Compare Mode changes which pane this instance
        // represents, so the drop destination is refreshed rather than fixed
        // at construction.
        if let dropView = webView as? TransparentWebView {
            dropView.configureDrop(target: dropTarget, store: store)
        }
        
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
        
        // MediaInfo writes URLs from tags (YouTube links, cover art sources,
        // encoder homepages) as plain text, so there was nothing to click.
        // This walks text nodes only — never attribute values — and turns bare
        // http(s) URLs into real links. Combined with the navigation policy
        // above, clicking one opens the user's browser rather than replacing
        // the report inside the app.
        let linkifyScript = """
        <script>
        (function() {
            function linkify() {
                var walker = document.createTreeWalker(
                    document.body, NodeFilter.SHOW_TEXT, null, false
                );
                var nodes = [];
                var node;
                while (node = walker.nextNode()) {
                    if (node.parentNode && node.parentNode.nodeName === 'A') continue;
                    if (/https?:\\/\\//.test(node.textContent)) nodes.push(node);
                }
                var pattern = /(https?:\\/\\/[^\\s<>"']+)/g;
                nodes.forEach(function(n) {
                    var text = n.textContent;
                    var frag = document.createDocumentFragment();
                    var last = 0, m;
                    pattern.lastIndex = 0;
                    while ((m = pattern.exec(text)) !== null) {
                        if (m.index > last) {
                            frag.appendChild(
                                document.createTextNode(text.substring(last, m.index))
                            );
                        }
                        var a = document.createElement('a');
                        a.href = m[1];
                        a.textContent = m[1];
                        frag.appendChild(a);
                        last = m.index + m[1].length;
                    }
                    if (last < text.length) {
                        frag.appendChild(document.createTextNode(text.substring(last)));
                    }
                    if (last > 0) n.parentNode.replaceChild(frag, n);
                });
            }
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', linkify);
            } else {
                linkify();
            }
        })();
        </script>
        """
        
        var html = raw
        
        if let r = html.range(of: "</body>") {
            html.insert(contentsOf: linkifyScript, at: r.lowerBound)
        } else {
            html += linkifyScript
        }
        
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

// MARK: - Web view with file-drop support

/// WKWebView registers for dragged file types and consumes the drop, which is
/// why dragging a media file onto the HTML tab did nothing while every other
/// tab opened it. Unregistering the types alone doesn't help — AppKit doesn't
/// then hand the drag to the SwiftUI view underneath. Accepting the drop here
/// and calling back into the store is the reliable route.
final class TransparentWebView: WKWebView {
    
    /// Where a file dropped here should go, before zone resolution.
    var dropTarget: FileDropTarget = .main
    
    /// Whether the centre "open on its own" zone applies here.
    var centreZoneAvailable: Bool = false
    
    var onFileDrop: ((URL, FileDropTarget) -> Void)?
    var onDragStateChange: ((FileDropTarget?) -> Void)?
    var onDragSessionChange: ((Bool) -> Void)?
    
    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        registerForDraggedTypes([.fileURL])
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
    
    // MARK: Drag destination
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard FileDropSupport.firstFileURL(from: sender) != nil else { return [] }
        onDragSessionChange?(true)
        notify(resolvedTarget(for: sender))
        return .copy
    }
    
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard FileDropSupport.firstFileURL(from: sender) != nil else { return [] }
        notify(resolvedTarget(for: sender))
        return .copy
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        notify(nil)
        onDragSessionChange?(false)
    }
    
    override func draggingEnded(_ sender: NSDraggingInfo) {
        notify(nil)
        onDragSessionChange?(false)
    }
    
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        FileDropSupport.firstFileURL(from: sender) != nil
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = FileDropSupport.firstFileURL(from: sender),
              let target = resolvedTarget(for: sender) else {
            notify(nil)
            onDragSessionChange?(false)
            return false
        }
        
        notify(nil)
        onDragSessionChange?(false)
        
        DispatchQueue.main.async { [weak self] in
            self?.onFileDrop?(url, target)
        }
        return true
    }
    
    private func resolvedTarget(for sender: NSDraggingInfo) -> FileDropTarget? {
        // A view configured as a Compare pane that has outlived Compare Mode
        // behaves as the window-wide target rather than refusing the drag.
        // Refusing left the drop unhandled in panes with no other handler.
        guard isPaneLive else { return .main }
        
        let point = convert(sender.draggingLocation, from: nil)
        return FileDropSupport.resolveTarget(
            paneTarget: dropTarget,
            localPoint: point,
            paneSize: bounds.size,
            centreAvailable: centreZoneAvailable
        )
    }
    
    /// Refreshed on every update. When false, this view was configured as a
    /// Compare pane and has outlived Compare Mode, so its stored target no
    /// longer refers to anything.
    var isPaneLive: Bool = true
    
    private func notify(_ target: FileDropTarget?) {
        DispatchQueue.main.async { [weak self] in
            self?.onDragStateChange?(target)
        }
    }
    
    // MARK: Configuration
    
    /// Same wiring as FileDropScrollView, deliberately mirrored so the two
    /// AppKit hosts can't drift apart in how they treat a drag.
    @MainActor
    func configureDrop(target: FileDropTarget, store: MediaStore) {
        dropTarget = target
        centreZoneAvailable = store.isCentreDropAvailable
        
        // A pane target is only valid while Compare Mode is on. `.main` is
        // always valid, since it means the single-file window.
        isPaneLive = (target == .main) || store.isCompareMode
        
        let owner: FileDropTarget = isPaneLive ? target : .main
        
        onFileDrop = { [owner] url, destination in
            store.reportDropTarget(nil, from: owner)
            store.endDragSession(from: owner)
            FileDropSupport.deliver(url, to: destination, store: store)
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
