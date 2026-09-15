//
//  MediaInfoMacApp.swift
//  SwiftMediaInfo
//
//  PHASE 4 — receives the Finder extension's handoff.
//
//  Two things changed:
//
//  1. URL SCHEME HANDLING
//     The app now answers swiftmediainfo://open?path=…&compare=…, sent by the
//     Finder Sync extension. Because this app is not sandboxed, it can read the
//     path under its own authority — which is the whole point of passing a
//     string rather than a file handle.
//
//  PHASE 6 adds the Settings scene.
//
//  2. COLD-LAUNCH QUEUEING
//     Previously, opening a file from Finder while the app was *not* running
//     could drop it. macOS delivers the open request during launch, before
//     ContentView's onAppear has handed the store to the delegate — so
//     `mediaStore` was still nil and the request went nowhere. Requests are now
//     queued and flushed the moment the store attaches.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    
    /// Set by ContentView once the scene exists.
    weak var mediaStore: MediaStore? {
        didSet { flushPendingRequests() }
    }
    
    /// Requests that arrived before the store was ready.
    private var pendingRequests: [OpenRequest] = []
    
    private struct OpenRequest {
        let url: URL
        let compareURL: URL?
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ask the system to enable the Finder Sync extension so users don't
        // have to visit System Settings › Extensions. Safe to call every
        // launch — it's a no-op when already enabled.
        enableFinderExtension()
        
        retargetCloseShortcut()
    }
    
    // MARK: - Freeing up ⌘W
    //
    // PHASE 12c. AppKit's Close item claims ⌘W, and menu key equivalents are
    // matched in `NSApplication.sendEvent` before the key press reaches the
    // responder chain — so the app's own ⌘W command would never fire while this
    // item still holds the chord.
    //
    // It is moved to ⌥⌘W rather than stripped. Leaving the window with no
    // keyboard route to close at all, so that only the red traffic light works,
    // would be a worse outcome than one unfamiliar chord.
    //
    // Deferred by one run-loop turn because SwiftUI builds the main menu after
    // this delegate callback, so running immediately would search a menu that
    // does not exist yet.
    private func retargetCloseShortcut() {
        DispatchQueue.main.async {
            guard let mainMenu = NSApp.mainMenu else { return }
            
            // Selectors are just names in Objective-C, so any class that
            // declares `performClose:` yields the identical selector. Xcode's
            // fix-it offers NSPopover; NSWindow is the same value and the one
            // that describes what is being matched — the menu item's target is
            // nil, so it resolves down the responder chain to the key window.
            let performClose = #selector(NSWindow.performClose(_:))
            
            for topLevel in mainMenu.items {
                guard let submenu = topLevel.submenu else { continue }
                
                for item in submenu.items
                where item.action == performClose
                && item.keyEquivalent == "w"
                && item.keyEquivalentModifierMask == .command {
                    item.keyEquivalentModifierMask = [.command, .option]
                }
            }
        }
    }
    
    // MARK: - Incoming URLs
    //
    // Handles all four entry points:
    //   • dragging a file onto the Dock icon
    //   • Finder "Open With"
    //   • double-clicking an associated file
    //   • the Finder Sync extension's swiftmediainfo:// URL
    
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL {
                enqueue(OpenRequest(url: url, compareURL: nil))
            } else if let request = parseCustomURL(url) {
                enqueue(request)
            }
        }
    }
    
    /// Decodes swiftmediainfo://open?path=…&compare=…
    ///
    /// Both paths are validated before use: they must be absolute and must
    /// actually exist. A malformed or stale URL is ignored rather than
    /// producing a confusing error.
    private func parseCustomURL(_ url: URL) -> OpenRequest? {
        guard url.scheme?.lowercased() == "swiftmediainfo" else { return nil }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return nil }
        
        func fileURL(named name: String) -> URL? {
            guard let path = items.first(where: { $0.name == name })?.value,
                  path.hasPrefix("/"),
                  FileManager.default.fileExists(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        }
        
        guard let primary = fileURL(named: "path") else { return nil }
        
        return OpenRequest(url: primary, compareURL: fileURL(named: "compare"))
    }
    
    // MARK: - Dispatch
    
    private func enqueue(_ request: OpenRequest) {
        guard mediaStore != nil else {
            pendingRequests.append(request)
            return
        }
        deliver(request)
    }
    
    private func flushPendingRequests() {
        guard mediaStore != nil, !pendingRequests.isEmpty else { return }
        let queued = pendingRequests
        pendingRequests = []
        for request in queued { deliver(request) }
    }
    
    private func deliver(_ request: OpenRequest) {
        guard let store = mediaStore else { return }
        
        DispatchQueue.main.async {
            store.openURL(request.url)
            
            if let compareURL = request.compareURL {
                store.openCompareURL(compareURL)
            }
        }
    }
    
    // MARK: - Auto-enable Finder Extension
    
    private func enableFinderExtension() {
        let extensionBundleID = Bundle.main.bundleIdentifier
            .map { $0 + ".OpenInSwiftMediaInfo" } ?? ""
        
        guard !extensionBundleID.isEmpty else { return }
        
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
            process.arguments = ["-e", "use", "-i", extensionBundleID]
            process.standardOutput = Pipe()
            process.standardError  = Pipe()
            try? process.run()
            process.waitUntilExit()
        }
    }
}

@main
struct MediaInfoMacApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate
    
    @StateObject private var mediaStore = MediaStore()
    
    @Environment(\.openWindow)
    private var openWindow
    
    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
    
    var body: some Scene {
        
        Window("SwiftMediaInfo", id: "main-window") {
            ContentView()
                .environmentObject(mediaStore)
                .onAppear {
                    appDelegate.mediaStore = mediaStore
                }
        }
        
        Window("About SwiftMediaInfo", id: "about-window") {
            AboutView()
            // PHASE 11. Two things this window never had.
            //
            // The store, because the rebuilt About view reads the animated
            // background preference — without it the view would trap at launch
            // the moment it is opened, the same way Keyboard Shortcuts would.
            //
            // The zoom scale, so ⌘+ enlarges this window's contents like it
            // does Settings and Keyboard Shortcuts. It was the last panel that
            // ignored the app zoom entirely.
            //
            // Order matters exactly as it does below: the scale modifier sits
            // inside .environmentObject, because modifiers wrap outward and
            // WindowZoomScale reads the store itself.
                .windowZoomScaled(baseWidth: 460, baseHeight: 700)
                .environmentObject(mediaStore)
        }
        .windowResizability(.contentSize)
        
        Window("Keyboard Shortcuts", id: "shortcuts-window") {
            KeyboardShortcutsView()
            // Order matters twice over.
            //
            // The scale modifier must sit *inside* .environmentObject,
            // because modifiers wrap outward: anything applied after the
            // store is provided lives above that provision and cannot see
            // it. Applied the other way round, WindowZoomScale's own
            // @EnvironmentObject finds no MediaStore and traps at launch.
            //
            // It must also sit outside the view itself, since a view cannot
            // both publish an environment value and read it in its own body.
            //
            // The window keeps its fixed size; only the contents scale.
                .windowZoomScaled(baseWidth: 460, baseHeight: 660)
                .environmentObject(mediaStore)
        }
        .windowResizability(.contentSize)
        
        // A real Settings scene rather than another Window, so it lands under
        // the app menu and answers ⌘, the way every other Mac app does.
        Settings {
            SettingsView()
                .windowZoomScaled(baseWidth: 760, baseHeight: 560)
                .environmentObject(mediaStore)
        }
        // Without this the Settings window keeps whatever size it was given on
        // first appearance, so zooming grew the content inside a window that
        // never grew with it.
        .windowResizability(.contentSize)
        
        .commands {
            
            CommandGroup(replacing: .appInfo) {
                // PHASE 13n. ⌘I added. The item had no shortcut, which made
                // About the only auxiliary window in the app you could not
                // reach from the keyboard — Settings has ⌘, and the shortcuts
                // reference has ⌘K. ⌘I is free here and is the conventional
                // choice for an information window on macOS.
                Button("About SwiftMediaInfo") {
                    openWindow(id: "about-window")
                }
                .keyboardShortcut("i", modifiers: .command)
            }
            
            CommandGroup(after: .newItem) {
                
                // Single "Open…" that allows files AND folders
                Button("Open…") {
                    mediaStore.openFilePicker()
                }
                .keyboardShortcut("o", modifiers: .command)
                
                // PHASE 12c — ⌘W closes the *file*, not the window.
                //
                // WHY THIS IS NOT AS SIMPLE AS ADDING A SHORTCUT
                //
                // AppKit owns ⌘W. Its Close item lives in the File menu and its
                // key equivalent is matched inside `NSApplication.sendEvent`,
                // before any key press reaches the responder chain — so a
                // SwiftUI button claiming ⌘W would simply never fire. The
                // system item has to be moved out of the way first, which
                // `AppDelegate.retargetCloseShortcut()` does at launch by
                // reassigning it to ⌥⌘W.
                //
                // ⌥⌘W is kept working deliberately. Removing the shortcut
                // outright would leave the red traffic light as the only way to
                // close the window, which is a worse trade than a slightly
                // unfamiliar chord.
                //
                // NEVER DEAD, NEVER SURPRISING
                //
                // The action is conditional rather than the button being
                // disabled. ⌘W in Settings, About or Keyboard Shortcuts must
                // still close those windows, and ⌘W with nothing open should
                // still do the obvious thing. So: close the file when there is
                // a file and the document window is frontmost; otherwise fall
                // back to exactly what AppKit would have done.
                Button("Close") {
                    handleCloseCommand()
                }
                .keyboardShortcut("w", modifiers: .command)
                
                Divider()
                
                Menu("Open Recent") {
                    if mediaStore.recentFileURLs.isEmpty {
                        Text("No Recent Files")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(mediaStore.recentFileURLs, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                mediaStore.openURL(url)
                            }
                        }
                        
                        Divider()
                        
                        Button("Clear Recents") {
                            mediaStore.clearRecentFiles()
                        }
                    }
                }
                
                Divider()
                
                // ── Phase 8b: file actions ─────────────────────────────
                //
                // In Compare Mode these become two submenus rather than flat
                // items, and the key equivalents come off. A single ⇧⌘R that
                // silently picks File A would be the same trap ⌘↩ fell into
                // (Phase 8c) — better to make the user say which file than to
                // guess on their behalf.
                //
                // The `keyboardShortcut` calls in the single-file case are for
                // DISPLAY. The keys themselves are handled by ContentView's
                // event monitor, which sees a keystroke before the main menu
                // does. Two reasons for that:
                //
                //   • ⌘⌫ has to mean "clear to start of line" while you are
                //     typing in the rename field. A menu equivalent is matched
                //     before the keystroke ever reaches the field, so the menu
                //     would always win.
                //   • An earlier attempt hid these items while a confirmation
                //     was open. It worked, and then left the menu stale: the
                //     items came back in SwiftUI's model but the real AppKit
                //     menu was not rebuilt until it was next opened, so ⌘⌫ was
                //     dead afterwards. Never conditionally remove a menu item
                //     that owns a key equivalent.
                if mediaStore.isCompareMode {
                    if let fileA = mediaStore.currentFile {
                        Menu("File A — \(fileA.fileName)") {
                            FileActionsMenuItems(
                                store: mediaStore,
                                url: fileA.url,
                                isCompare: false
                            )
                        }
                    }
                    
                    if let fileB = mediaStore.compareFile {
                        Menu("File B — \(fileB.fileName)") {
                            FileActionsMenuItems(
                                store: mediaStore,
                                url: fileB.url,
                                isCompare: true
                            )
                        }
                    }
                } else if let file = mediaStore.currentFile {
                    FileActionsMenuItems(
                        store: mediaStore,
                        url: file.url,
                        isCompare: false,
                        withShortcuts: true
                    )
                }
            }
            
            CommandGroup(replacing: .help) {
                
                Button("Keyboard Shortcuts") {
                    openWindow(id: "shortcuts-window")
                }
                .keyboardShortcut("k", modifiers: .command)
                
                Divider()
                
                // PHASE 13n. ⌘/ used to open the GitHub repository, which is
                // where the app lived before it had anywhere else to be. It
                // now opens the app's own page.
                //
                // The FAQ sits directly below it, without a shortcut. It is
                // the genuinely useful document — why macOS warns on first
                // launch, why MediaInfo is needed, what happens to your files
                // — but it is the second thing someone wants, not the first,
                // and a Help menu with two shortcuts in it is a Help menu
                // arguing with itself.
                Button("SwiftMediaInfo Website") {
                    ProjectLinks.open(ProjectLinks.appPage)
                }
                .keyboardShortcut("/", modifiers: .command)
                
                Button("Frequently Asked Questions") {
                    ProjectLinks.open(ProjectLinks.faq)
                }
                
                Divider()
                
                Button("Report Issues / Bugs") {
                    ProjectLinks.open(ProjectLinks.issues)
                }
            }
        }
    }
}

// MARK: - Close command routing
//
// PHASE 12c. Kept out of the `.commands` builder because a result builder is a
// poor place for branching logic — and because this needs to be readable.

private extension MediaInfoMacApp {
    
    func handleCloseCommand() {
        let key = NSApp.keyWindow
        
        let isDocumentWindow =
        key?.identifier?.rawValue == DocumentWindowMarker.identifier
        
        let hasFile =
        mediaStore.currentFile != nil || mediaStore.compareFile != nil
        
        if isDocumentWindow && hasFile {
            mediaStore.closeFile()
        } else {
            // Settings, About, Keyboard Shortcuts — or the document window with
            // nothing in it. Standard behaviour, unchanged.
            key?.performClose(nil)
        }
    }
}
