//
//  ReportHTML.swift
//  SwiftMediaInfo
//
//  One stylesheet for MediaInfo's HTML report, in the app (HTMLView) and in
//  exported and shared HTML files. Both go through `styledDocument`, and the
//  rules are written once against CSS variables (the PDF report has its own
//  design and stylesheet, in ReportDocument):
//
//    • In the app, the variables are set for the window's current appearance
//      and zoom, over a transparent background (the app's own backdrop shows
//      through, as before).
//    • In an exported file, the palette is the app's appearance at the time
//      of export, on a solid page background, centred at a comfortable
//      reading width.
//
//  A change to how the report looks therefore changes both at once.
//

import Foundation

enum ReportHTML {

    enum Appearance {
        /// The in-app HTML tab: one palette, the user's zoom, transparent page.
        case inApp(isDark: Bool, fontSize: Double)
        /// An exported file: the app's appearance when it was exported, on a
        /// solid page.
        case export(isDark: Bool)
    }

    // MARK: Palettes

    private static func variables(isDark: Bool) -> String {
        let v: [(String, String)] = [
            ("page",         isDark ? "#16161f" : "#f6f6fa"),
            ("fg",           isDark ? "#ededf5" : "#1a1a2e"),
            ("fg2",          isDark ? "#d0d0e4" : "#3a3a5c"),
            ("border",       isDark ? "rgba(255,255,255,0.12)" : "rgba(0,0,0,0.10)"),
            ("header-bg",    isDark ? "rgba(255,255,255,0.05)" : "rgba(0,0,0,0.025)"),
            ("hover-bg",     isDark ? "rgba(130,100,255,0.10)" : "rgba(130,100,255,0.05)"),
            ("track-bg",     isDark ? "rgba(130,100,255,0.12)" : "rgba(130,100,255,0.07)"),
            ("track-border", isDark ? "rgba(160,130,255,0.6)"  : "rgba(130,100,255,0.4)"),
            ("accent",       isDark ? "#c4b5fd" : "#7c3aed"),
            ("value-fg",     isDark ? "#f8f8ff" : "#111128"),
            ("table-bg",     isDark ? "rgba(30,30,50,0.95)" : "#ffffff"),
            ("table-shadow", isDark ? "0 2px 8px rgba(0,0,0,0.3), 0 0 0 1px rgba(255,255,255,0.05)" : "0 1px 4px rgba(0,0,0,0.06)"),
            ("scroll-track", isDark ? "rgba(255,255,255,0.03)" : "rgba(0,0,0,0.02)"),
            ("scroll-thumb", isDark ? "rgba(255,255,255,0.15)" : "rgba(0,0,0,0.15)"),
            ("scroll-hover", isDark ? "rgba(255,255,255,0.2)" : "rgba(0,0,0,0.2)"),
            ("hl",           isDark ? "rgba(74,222,128,0.3)" : "rgba(34,197,94,0.25)"),
            ("hl-active",    isDark ? "rgba(74,222,128,0.6)" : "rgba(34,197,94,0.5)"),
            ("hl-outline",   isDark ? "#4ade80" : "#22c55e"),
        ]
        return v.map { "--\($0.0): \($0.1);" }.joined(separator: " ")
    }

    private static func rootRules(_ appearance: Appearance) -> String {
        switch appearance {
        case .inApp(let isDark, let fontSize):
            let zoom = (fontSize / 12.0) * 100.0
            return """
            :root { \(variables(isDark: isDark)) --page-bg: transparent; --zoom: \(zoom)%; --pad: 16px; --max: none; }
            """
        case .export(let isDark):
            return """
            :root { color-scheme: \(isDark ? "dark" : "light"); \(variables(isDark: isDark)) --page-bg: var(--page); --zoom: 100%; --pad: 32px 28px; --max: 1100px; }
            """
        }
    }

    // MARK: Stylesheet

    /// The report's rules, shared by the app and exported files. Colours come
    /// from the variables above, never from literals here.
    private static let rules = """
    * { box-sizing: border-box; }

    ::-webkit-scrollbar { width: 8px; height: 8px; }
    ::-webkit-scrollbar-track { background: var(--scroll-track); border-radius: 4px; }
    ::-webkit-scrollbar-thumb { background: var(--scroll-thumb); border-radius: 4px; }
    ::-webkit-scrollbar-thumb:hover { background: var(--scroll-hover); }

    html { background: var(--page-bg); }

    body {
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
        font-size: 12px;
        line-height: 1.5;
        margin: 0 auto;
        max-width: var(--max);
        padding: var(--pad);
        background: transparent;
        color: var(--fg);
        zoom: var(--zoom);
        -webkit-font-smoothing: antialiased;
    }

    /* ── Track section titles ──────────────────────────── */
    h2, h3, .track-title {
        font-size: 14px;
        font-weight: 700;
        letter-spacing: 0.03em;
        color: var(--accent);
        margin: 24px 0 10px 0;
        padding: 10px 16px;
        background: var(--track-bg);
        border-left: 3px solid var(--track-border);
        border-radius: 0 8px 8px 0;
    }
    h2:first-child, h3:first-child { margin-top: 0; }

    /* ── Tables ────────────────────────────────────────── */
    table {
        border-collapse: separate;
        border-spacing: 0;
        width: 100%;
        margin: 0 0 20px 0;
        border: 1px solid var(--border);
        border-radius: 10px;
        overflow: hidden;
        background: var(--table-bg);
        box-shadow: var(--table-shadow);
    }
    td, th {
        padding: 9px 16px;
        border-bottom: 1px solid var(--border);
        text-align: left;
        vertical-align: top;
        transition: background 0.12s ease;
    }
    tr:last-child td { border-bottom: none; }

    /* Field name column */
    td:first-child {
        font-weight: 600;
        font-size: 12.5px;
        color: var(--fg2);
        white-space: nowrap;
        width: 30%;
        min-width: 140px;
    }

    /* Value column */
    td:last-child {
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
        font-size: 12.5px;
        font-weight: 500;
        color: var(--value-fg);
        word-break: break-word;
    }

    th {
        font-weight: 700;
        font-size: 11.5px;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        background: var(--header-bg);
        color: var(--fg2);
        border-bottom: 1px solid var(--border);
    }
    tr:nth-child(even) td { background: var(--header-bg); }
    tr:hover td { background: var(--hover-bg); }

    /* ── Links ─────────────────────────────────────────── */
    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }

    hr { border: none; border-top: 1px solid var(--border); margin: 16px 0; }

    pre, code {
        font-family: "SF Mono", "Menlo", monospace;
        font-size: 11.5px;
        background: var(--header-bg);
        border-radius: 4px;
        padding: 2px 5px;
    }
    pre { padding: 12px 14px; overflow-x: auto; border: 1px solid var(--border); }

    /* ── Search highlights (in the app) ────────────────── */
    .smi-highlight {
        background: var(--hl);
        border-radius: 3px;
        padding: 1px 2px;
        transition: background 0.15s ease;
    }
    .smi-highlight-active {
        background: var(--hl-active);
        outline: 2px solid var(--hl-outline);
        outline-offset: 1px;
    }
    """

    // MARK: Links

    /// MediaInfo writes URLs from tags (YouTube links, cover art sources,
    /// encoder homepages) as plain text, so there was nothing to click. This
    /// walks text nodes only — never attribute values — and turns bare
    /// http(s) URLs into real links.
    private static let linkifyScript = """
    <script>
    (function() {
        function linkify() {
            var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null, false);
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
                    if (m.index > last) frag.appendChild(document.createTextNode(text.substring(last, m.index)));
                    var a = document.createElement('a');
                    a.href = m[1];
                    a.textContent = m[1];
                    frag.appendChild(a);
                    last = m.index + m[1].length;
                }
                if (last < text.length) frag.appendChild(document.createTextNode(text.substring(last)));
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

    // MARK: Document

    /// MediaInfo's HTML with the report stylesheet and link script added.
    static func styledDocument(_ raw: String, appearance: Appearance) -> String {
        let style = "<style>\n\(rootRules(appearance))\n\(rules)\n</style>"
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

        // Exported files open in browsers that may not assume UTF-8 from
        // MediaInfo's own header.
        if case .export = appearance, !html.lowercased().contains("<meta charset") {
            if let r = html.range(of: "<head>") {
                html.insert(contentsOf: "\n<meta charset=\"utf-8\">", at: r.upperBound)
            }
        }

        return html
    }
}
