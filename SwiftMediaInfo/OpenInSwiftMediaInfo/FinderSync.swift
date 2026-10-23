//
//  FinderSync.swift
//  OpenInSwiftMediaInfo
//
//  The Finder extension: adds "Open in SwiftMediaInfo" (or "Open Folder…",
//  "Open N Items…") and, with exactly two files selected, "Compare in
//  SwiftMediaInfo" to Finder's right-click menu. The app switches it on at
//  launch unless it has been turned off; it is turned on and off in Settings
//  › General or in System Settings › General › Login Items & Extensions,
//  which share one switch (FinderExtension, in the app).
//
//  IMPORTANT: this target MUST have App Sandbox ENABLED. macOS refuses to
//  register a non-sandboxed Finder Sync extension — pluginkit silently drops
//  it, the context menu never appears, and the extension doesn't even show up
//  in System Settings. Do not turn App Sandbox off on this target.
//
//  HOW THE APP IS OPENED
//
//  The extension never hands the app a file. It opens a custom URL —
//  swiftmediainfo://open?path=…[&path=…][&compare=…] — and the main app,
//  which is not sandboxed, reads the files under its own authority
//  (MediaInfoMacApp's `parseCustomURL` decodes it; the scheme is registered
//  in the app's Info.plist).
//
//  Don't go back to NSWorkspace.open(fileURL, withApplicationAt:). That asks
//  LaunchServices to pass a *file* from this process, which needs the
//  extension itself to hold access to it — and its sandbox only covers a few
//  folders (Downloads, Movies, Music, Pictures). Everywhere else failed with
//  "does not have permission to open <filename>". Passing a string means
//  nothing crosses a security boundary, so the extension's entitlements play
//  no part in opening.
//
//  EXTERNAL VOLUMES
//
//  Finder only asks the extension for a menu inside the directories it
//  observes. Listing "/Volumes" does not cover the drives inside it, and a
//  list built once at launch misses anything mounted later, so the list is
//  rebuilt whenever a volume mounts, unmounts or is renamed.
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
        
        let targets = openTargets(for: menuKind)
        guard !targets.isEmpty else { return nil }
        
        let menu = NSMenu(title: "SwiftMediaInfo")
        
        // The title says what will happen: a folder opens as one folder tab,
        // several items as a tab each.
        let open = NSMenuItem(
            title: openTitle(for: targets),
            action: #selector(openInSwiftMediaInfo(_:)),
            keyEquivalent: ""
        )
        open.image = NSImage(
            systemSymbolName: targets.count == 1 && isDirectory(targets[0]) ? "folder" : "film.stack",
            accessibilityDescription: "SwiftMediaInfo"
        )
        menu.addItem(open)
        
        // Exactly two files selected is an unambiguous request to compare.
        // Offering it here saves opening one file and then hunting for the
        // second through a picker.
        if menuKind == .contextualMenuForItems,
           targets.count == 2,
           !targets.contains(where: isDirectory) {
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
    
    /// What "Open" acts on: the selected items, or — right-clicking empty
    /// space in a Finder window — the folder that window is showing.
    private func openTargets(for menuKind: FIMenuKind) -> [URL] {
        let controller = FIFinderSyncController.default()
        let selection = controller.selectedItemURLs() ?? []
        
        if menuKind == .contextualMenuForItems, !selection.isEmpty {
            return selection
        }
        if let folder = controller.targetedURL() {
            return [folder]
        }
        return selection
    }
    
    private func openTitle(for targets: [URL]) -> String {
        if targets.count > 1 {
            return "Open \(targets.count) Items in SwiftMediaInfo"
        }
        return isDirectory(targets[0])
            ? "Open Folder in SwiftMediaInfo"
            : "Open in SwiftMediaInfo"
    }
    
    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
    
    // MARK: - Actions
    
    /// Selection is read again here rather than captured when the menu was
    /// built: Finder can change it between the two.
    @objc func openInSwiftMediaInfo(_ sender: NSMenuItem) {
        let controller = FIFinderSyncController.default()
        var targets = controller.selectedItemURLs() ?? []
        if targets.isEmpty, let folder = controller.targetedURL() {
            targets = [folder]
        }
        guard !targets.isEmpty else { return }
        
        launch(paths: targets.map { $0.path(percentEncoded: false) }, comparePath: nil)
    }
    
    @objc func compareInSwiftMediaInfo(_ sender: NSMenuItem) {
        guard let items = FIFinderSyncController.default().selectedItemURLs(),
              items.count == 2 else {
            return
        }
        launch(
            paths: [items[0].path(percentEncoded: false)],
            comparePath: items[1].path(percentEncoded: false)
        )
    }
    
    // MARK: - Handoff
    
    /// Builds the custom URL and asks the system to open it.
    ///
    /// URLComponents does the percent-encoding, so paths containing spaces,
    /// accented characters, ampersands, or emoji survive intact. Building the
    /// string by hand is where this kind of thing usually breaks.
    private func launch(paths: [String], comparePath: String?) {
        var components = URLComponents()
        components.scheme = Self.urlScheme
        components.host   = "open"
        
        // One `path` per item; the app opens each in a tab of its own.
        var items = paths.map { URLQueryItem(name: "path", value: $0) }
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
