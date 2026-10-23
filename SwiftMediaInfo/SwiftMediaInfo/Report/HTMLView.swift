//
//  HTMLView.swift
//  SwiftMediaInfo
//
//  The HTML view: MediaInfo's HTML report in a transparent WKWebView,
//  styled by ReportHTML (the same stylesheet HTML exports use) and zoomed
//  through CSS, so tables, borders, padding and type all scale together.
//  Search highlights matches with injected JavaScript. TransparentWebView
//  takes file drops (through FileDropHandler) and drops Reload from the
//  right-click menu.
//
//  SECURITY
//
//  This view renders HTML that MediaInfo generated from file metadata. Most of
//  that metadata comes from inside the media file itself, which means it is
//  attacker-controllable in principle: a crafted file can put arbitrary text
//  into a title or comment field, and that text ends up in the document.
//
//  So the only navigation permitted is the initial in-memory load. Clicked
//  links open in the user's browser, and only for http/https and mailto —
//  file:// and other schemes are refused outright.
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
        // Don't guard it with `responds(to:)`: `drawsBackground` is exposed
        // to KVC but has no matching Objective-C selector, so the check always
        // fails and the call silently never happens.
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
    
    /// The report as shown here. The styling lives in ReportHTML so an
    /// exported HTML file is styled by exactly the same rules.
    private func buildStyledHTML(_ raw: String, isDark: Bool, fontSize: Double) -> String {
        ReportHTML.styledDocument(raw, appearance: .inApp(isDark: isDark, fontSize: fontSize))
    }
}

// MARK: - Web view with file-drop support

/// WKWebView registers for dragged file types and consumes the drop, which is
/// why dragging a media file onto the HTML tab did nothing while every other
/// tab opened it. Unregistering the types alone doesn't help — AppKit doesn't
/// then hand the drag to the SwiftUI view underneath. Accepting the drop here
/// and calling back into the store is the reliable route.
final class TransparentWebView: WKWebView {
    
    private lazy var drops = FileDropHandler(view: self)
    
    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        registerForDraggedTypes([.fileURL])
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
    
    // MARK: Context menu without Reload
    //
    // WebKit's right-click menu offers Reload, and reloading a page
    // that was handed over as a string rather than loaded from a URL leaves
    // nothing to reload: the view goes blank until the file is reopened.
    // The menu stays — Copy, Look Up, Share and the rest are useful — with
    // Reload taken out, along with any separator that leaves dangling.
    
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.items
            .filter { item in
                item.identifier?.rawValue == "WKMenuItemIdentifierReload"
                || item.title == "Reload"
                || item.action == #selector(WKWebView.reload(_:))
                || item.action == #selector(WKWebView.reloadFromOrigin(_:))
            }
            .forEach(menu.removeItem)
        
        // Tidy separators: none at either end, never two in a row.
        var previousWasSeparator = true
        for item in menu.items {
            if item.isSeparatorItem && previousWasSeparator { menu.removeItem(item) }
            else { previousWasSeparator = item.isSeparatorItem }
        }
        if let last = menu.items.last, last.isSeparatorItem { menu.removeItem(last) }
        
        super.willOpenMenu(menu, with: event)
    }
    
    // MARK: Drag destination
    //
    // The same handling as the text panes' FileDropScrollView, shared through
    // FileDropHandler.
    
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
    
    // MARK: Configuration
    
    /// Wires the drop callbacks to the store for a given destination.
    @MainActor
    func configureDrop(target: FileDropTarget, store: MediaStore) {
        drops.configure(target: target, store: store)
    }
}
