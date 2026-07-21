//
//  FinderSync.swift
//  OpenInSwiftMediaInfo
//
//  Finder Sync Extension — adds "Open in SwiftMediaInfo" to the
//  right-click context menu for any file or folder in Finder.
//  macOS discovers this extension automatically when the app is installed
//  and the user enables it in System Settings → Extensions → Finder.
//

import Cocoa
import FinderSync

class FinderSyncExtension: FIFinderSync {
    
    override init() {
        super.init()
        
        // Monitor all mounted volumes so the context menu appears everywhere.
        // "/" covers the entire file system. We also add /Volumes/ to cover
        // external drives, USB sticks, network shares, etc.
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/"),
            URL(fileURLWithPath: "/Volumes")
        ]
    }
    
    // MARK: - Context menu
    
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        // Only show in the context menu (right-click), not in toolbar or sidebar
        guard menuKind == .contextualMenuForItems ||
                menuKind == .contextualMenuForContainer else {
            return nil
        }
        
        let menu = NSMenu(title: "SwiftMediaInfo")
        let item = NSMenuItem(
            title: "Open in SwiftMediaInfo",
            action: #selector(openInSwiftMediaInfo(_:)),
            keyEquivalent: ""
        )
        item.image = NSImage(systemSymbolName: "film.stack", accessibilityDescription: "SwiftMediaInfo")
        menu.addItem(item)
        return menu
    }
    
    @objc func openInSwiftMediaInfo(_ sender: NSMenuItem) {
        // Get the selected items from Finder
        guard let items = FIFinderSyncController.default().selectedItemURLs(),
              let firstURL = items.first else {
            return
        }
        
        // Find SwiftMediaInfo.app — it's 3 levels up from this extension's
        // bundle inside PlugIns/
        let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent()   // PlugIns/
            .deletingLastPathComponent()   // Contents/
            .deletingLastPathComponent()   // SwiftMediaInfo.app
        
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        
        NSWorkspace.shared.open(
            [firstURL],
            withApplicationAt: appURL,
            configuration: configuration
        )
    }
}
