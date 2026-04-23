//
//  HTMLView.swift
//  SwiftMediaInfo
//
//  Created by Undisclosed on 23/4/26.
//

//
//  HTMLView.swift
//  MediaInfoMac
//

import SwiftUI
import WebKit

struct HTMLView: NSViewRepresentable {
    let htmlString: String
    
    func makeNSView(context: Context) -> WKWebView {
        let wv = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        wv.setValue(false, forKey: "drawsBackground")
        return wv
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        let style = """
        <style>
          :root { color-scheme: dark; }
        
          body {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            font-size: 13px;
            padding: 16px;
            color: #ffffff;
            background: #1e1e1e;
          }
        
          table {
            border-collapse: collapse;
            width: 100%;
            background: #1e1e1e;
          }
        
          td, th {
            padding: 4px 8px;
            border: 1px solid #444;
            background: #1e1e1e;
            color: #ffffff;
          }
        
          th {
            font-weight: 600;
          }
        </style>
        """
        
        var html = htmlString
        if let r = html.range(of: "</head>") {
            html.insert(contentsOf: style, at: r.lowerBound)
        } else {
            html = style + html
        }
        
        webView.loadHTMLString(html, baseURL: nil)
    }
}
