//
//  QuickLook.swift
//  SwiftMediaInfo
//
//  Space shows the current file in Quick Look, as in Finder — for the
//  formats macOS can preview (PreviewRouter decides; the rest get the
//  SwiftMediaInfo preview).
//
//  The panel is the system's own QLPreviewPanel, so it previews exactly what
//  Finder would: MP4, MOV and M4V video, most audio, and images. The panel
//  looks for a controller along the responder chain, which ends at the app
//  delegate — so the app delegate takes control (see the extension below)
//  and hands it this object as the panel's data source.
//

import AppKit
import Quartz

@MainActor
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {

    static let shared = QuickLookController()

    private(set) var url: URL?

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    /// Space: open on `url`, or close if already open.
    func toggle(url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            self.url = url
            panel.makeKeyAndOrderFront(nil)
            panel.reloadData()
        }
    }

    /// Keeps an open panel on whatever file is now on screen — switching tabs
    /// with the panel open shows the new tab's file, as Finder does when you
    /// move the selection.
    func follow(_ url: URL?) {
        guard isVisible else { return }
        guard let url else {
            QLPreviewPanel.shared().orderOut(nil)
            return
        }
        guard url != self.url else { return }
        self.url = url
        QLPreviewPanel.shared().reloadData()
    }

    // MARK: QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { url == nil ? 0 : 1 }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { url as NSURL? }
    }

    // MARK: QLPreviewPanelDelegate

    /// Space and Escape inside the panel close it, as they do in Finder.
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
              event.keyCode == 49 || event.keyCode == 53 else { return false }
        MainActor.assumeIsolated { panel.orderOut(nil) }
        return true
    }
}

// MARK: - Panel control

extension AppDelegate {
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = QuickLookController.shared
        panel.delegate = QuickLookController.shared
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}
