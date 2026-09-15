//
//  FinderSync.swift
//  OpenInSwiftMediaInfo
//
//  PHASE 4 (corrected) — fixes "does not have permission to open <filename>".
//
//  IMPORTANT: this target MUST have App Sandbox ENABLED. macOS refuses to
//  register a non-sandboxed Finder Sync extension — pluginkit silently drops
//  it, the context menu never appears, and the extension doesn't even show up
//  in System Settings. Do not turn App Sandbox off on this target.
//
//  THE ORIGINAL BUG
//
//  The extension used to call NSWorkspace.open(fileURL, withApplicationAt:),
//  which asks LaunchServices to hand a *file* from this process to the app.
//  That handoff requires the extension itself to hold access to the file, and
//  its entitlements only covered Movies, Music and Pictures — precisely the
//  three folders that worked. Everywhere else failed.
//
//  THE FIX
//
//  The extension now passes a *string*. It opens a custom URL
//  (swiftmediainfo://open?path=…) and the main app — which is not sandboxed —
//  reads the file under its own authority. Nothing crosses a security
//  boundary, so the extension's entitlements no longer matter for opening.
//
//  This works with the sandbox fully enabled, which is the whole point: the
//  fix is about which process does the reading, not about weakening the
//  extension's protection.
//
//  EXTERNAL VOLUMES
//
//  Declaring "/Volumes" once at startup does not cover drives mounted later,
//  which is why the menu never appeared on the external SSD. The extension now
//  watches mount and unmount events and rebuilds its observed directory list
//  as volumes come and go.
//

import Cocoa
import FinderSync

final class FinderSyncExtension: FIFinderSync {
    
    /// Must match CFBundleURLSchemes in the main app's Info.plist.
    private static let urlScheme = "swiftmediainfo"
    
    override init() {
        super.init()
        
        refreshObservedDirectories()
        
        // Volumes appearing and disappearing changes what needs observing.
        // Without this, a drive plugged in after launch is invisible to the
        // extension and Finder never asks it for a menu there.
        let center = NSWorkspace.shared.notificationCenter
        
        center.addObserver(
            self,
            selector: #selector(volumesChanged),
            name: NSWorkspace.didMountNotification,
            object: nil
        )
        
        center.addObserver(
            self,
            selector: #selector(volumesChanged),
            name: NSWorkspace.didUnmountNotification,
            object: nil
        )
        
        center.addObserver(
            self,
            selector: #selector(volumesChanged),
            name: NSWorkspace.didRenameVolumeNotification,
            object: nil
        )
    }
    
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    // MARK: - Observed directories
    
    @objc private func volumesChanged(_ notification: Notification) {
        refreshObservedDirectories()
    }
    
    /// Root plus every currently mounted volume.
    ///
    /// "/" covers the boot volume, which is why Desktop, Documents and
    /// Downloads always showed the menu. Each mounted volume has to be listed
    /// explicitly — "/Volumes" on its own does not cover its children.
    private func refreshObservedDirectories() {
        var directories: Set<URL> = [
            URL(fileURLWithPath: "/"),
            URL(fileURLWithPath: "/Volumes")
        ]
        
        if let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) {
            for volume in volumes {
                directories.insert(volume.standardizedFileURL)
            }
        }
        
        FIFinderSyncController.default().directoryURLs = directories
    }
    
    // MARK: - Context menu
    
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems ||
                menuKind == .contextualMenuForContainer else {
            return nil
        }
        
        let selection = FIFinderSyncController.default().selectedItemURLs() ?? []
        
        let menu = NSMenu(title: "SwiftMediaInfo")
        
        let open = NSMenuItem(
            title: "Open in SwiftMediaInfo",
            action: #selector(openInSwiftMediaInfo(_:)),
            keyEquivalent: ""
        )
        open.image = NSImage(
            systemSymbolName: "film.stack",
            accessibilityDescription: "SwiftMediaInfo"
        )
        menu.addItem(open)
        
        // Exactly two files selected is an unambiguous request to compare.
        // Offering it here saves opening one file and then hunting for the
        // second through a picker.
        if selection.count == 2 {
            let compare = NSMenuItem(
                title: "Compare in SwiftMediaInfo",
                action: #selector(compareInSwiftMediaInfo(_:)),
                keyEquivalent: ""
            )
            compare.image = NSImage(
                systemSymbolName: "rectangle.split.2x1",
                accessibilityDescription: "Compare"
            )
            menu.addItem(compare)
        }
        
        return menu
    }
    
    // MARK: - Actions
    
    @objc func openInSwiftMediaInfo(_ sender: NSMenuItem) {
        guard let first = FIFinderSyncController.default().selectedItemURLs()?.first else {
            return
        }
        launch(path: first.path(percentEncoded: false), comparePath: nil)
    }
    
    @objc func compareInSwiftMediaInfo(_ sender: NSMenuItem) {
        guard let items = FIFinderSyncController.default().selectedItemURLs(),
              items.count == 2 else {
            return
        }
        launch(
            path: items[0].path(percentEncoded: false),
            comparePath: items[1].path(percentEncoded: false)
        )
    }
    
    // MARK: - Handoff
    
    /// Builds the custom URL and asks the system to open it.
    ///
    /// URLComponents does the percent-encoding, so paths containing spaces,
    /// accented characters, ampersands, or emoji survive intact. Building the
    /// string by hand is where this kind of thing usually breaks.
    private func launch(path: String, comparePath: String?) {
        var components = URLComponents()
        components.scheme = Self.urlScheme
        components.host   = "open"
        
        var items = [URLQueryItem(name: "path", value: path)]
        if let comparePath {
            items.append(URLQueryItem(name: "compare", value: comparePath))
        }
        components.queryItems = items
        
        guard let url = components.url else { return }
        
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        
        NSWorkspace.shared.open(
            url,
            configuration: configuration,
            completionHandler: nil
        )
    }
}
