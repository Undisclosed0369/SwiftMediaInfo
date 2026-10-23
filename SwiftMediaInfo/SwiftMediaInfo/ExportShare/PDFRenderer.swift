//
//  PDFRenderer.swift
//  SwiftMediaInfo
//
//  Turns the PDF report's HTML (built and styled by ReportDocument's
//  `pdfHTML`) into a paginated A4 PDF.
//
//  WebKit lays the page out and prints it through AppKit's print system, so
//  the result is real A4 pages — text stays text (selectable, searchable),
//  tables break between pages where the stylesheet allows, and links remain
//  clickable. WKWebView's own `createPDF` was the simpler call, but it makes
//  one endlessly tall page, which no printer or PDF reader handles well.
//
//  The web view lives in a window that is never shown: WebKit only prints
//  views that are part of a window.
//

import AppKit
import PDFKit
import WebKit

@MainActor
final class PDFRenderer: NSObject, WKNavigationDelegate {

    /// A4 in points.
    private static let paperSize = NSSize(width: 595.28, height: 841.89)

    private var webView: WKWebView?
    private var window: NSWindow?
    private var loaded: CheckedContinuation<Bool, Never>?

    /// Renders `html` to PDF data, or nil if WebKit could not load it.
    /// `paper` fills every page edge to edge, behind the content.
    static func render(html: String, paper: NSColor = .white) async -> Data? {
        let renderer = PDFRenderer()
        guard let data = await renderer.run(html: html) else { return nil }
        return Self.paint(data, paper: paper)
    }
    
    /// WebKit only paints the page area inside the @page margins, so a dark
    /// report printed straight came out as a dark block with a white border.
    /// Each page is drawn again into a new PDF over a full-bleed fill. The
    /// page is drawn as PDF, not as an image, so its text stays selectable
    /// and searchable; links are annotations, which drawing a page leaves
    /// behind, so they are put back over the same rectangles.
    ///
    /// (This used to be a PDFPage subclass that filled the page in
    /// `draw(with:to:)`. PDFKit warns against that: it disables PDFKit's
    /// fast, lossless saving and makes it re-render every page.)
    private static func paint(_ data: Data, paper: NSColor) -> Data {
        guard let provider = CGDataProvider(data: data as CFData),
              let source = CGPDFDocument(provider),
              source.numberOfPages > 0 else { return data }
        let links = PDFDocument(data: data)

        let output = NSMutableData()
        var media = CGRect(origin: .zero, size: paperSize)
        var info: [CFString: Any] = [kCGPDFContextCreator: "SwiftMediaInfo"]
        if let title = links?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String {
            info[kCGPDFContextTitle] = title
        }
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &media, info as CFDictionary)
        else { return data }

        for index in 1...source.numberOfPages {
            guard let page = source.page(at: index) else { continue }
            var box = page.getBoxRect(.mediaBox)
            context.beginPage(mediaBox: &box)
            context.setFillColor(paper.cgColor)
            context.fill(box)
            context.drawPDFPage(page)
            for annotation in links?.page(at: index - 1)?.annotations ?? [] {
                if let url = annotation.url {
                    context.setURL(url as CFURL, for: annotation.bounds)
                }
            }
            context.endPage()
        }
        context.closePDF()
        return output as Data
    }

    private func run(html: String) async -> Data? {
        let frame = NSRect(origin: .zero, size: Self.paperSize)
        let webView = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = self

        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: frame.width, height: frame.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = webView
        self.webView = webView
        self.window = window
        defer {
            window.contentView = nil
            window.close()
            self.webView = nil
            self.window = nil
        }

        let didLoad = await withCheckedContinuation { continuation in
            loaded = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
        guard didLoad else { return nil }

        // Fonts and the embedded icon settle a moment after "finished".
        try? await Task.sleep(nanoseconds: 150_000_000)

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftMediaInfo-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let info = NSPrintInfo()
        info.paperSize = Self.paperSize
        // The page margins come from the stylesheet's @page rule.
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output

        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.view?.frame = webView.bounds

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let box = ContinuationBox(continuation)
            operation.runModal(
                for: window,
                delegate: box,
                didRun: #selector(ContinuationBox.printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        }

        return try? Data(contentsOf: output)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume(returning: true)
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(returning: false)
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(returning: false)
        loaded = nil
    }
}

/// Bridges the print operation's Objective-C completion callback.
private final class ContinuationBox: NSObject {
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
        super.init()
        // Kept alive until the print operation calls back.
        Self.live.insert(self)
    }

    private static var live = Set<ContinuationBox>()

    @objc func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        continuation?.resume()
        continuation = nil
        Self.live.remove(self)
    }
}
