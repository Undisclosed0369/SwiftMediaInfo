//
//  MediaInfoMacApp.swift
//  SwiftMediaInfo
//
//  The app's entry point: its four windows (the main window, About,
//  Keyboard Shortcuts and Settings), the menu bar, and the app delegate.
//
//  APP DELEGATE
//
//  • Files and folders arriving from outside: dropped on the Dock icon,
//    opened from Finder, or sent by the Finder extension as
//    swiftmediainfo://open?path=…&compare=… (see OpenInSwiftMediaInfo), or by
//    the website as swiftmediainfo://find?name=…&size=…&modified=… (see
//    FileLookup). The
//    app isn't sandboxed, so it reads those paths under its own authority —
//    the reason the extension passes paths rather than file handles.
//  • Cold-launch queueing: macOS delivers an open request during launch,
//    before ContentView has handed the store to the delegate, so requests are
//    queued and flushed the moment `mediaStore` is set.
//  • ⌘W: AppKit's Close item is moved to ⌥⌘W so the app's own ⌘W can close
//    a tab (see "Freeing up ⌘W").
//  • Switches the Finder extension on at launch unless it has been turned
//    off (FinderExtension), clears preview files left by a crash, and
//    deletes the preview's files when the app quits.
//
//  MENUS
//
//  Menu items that own a key equivalent are never added or removed
//  conditionally — a rebuilt AppKit menu can leave the key dead (see the File
//  actions note). Several keys shown in menus are actually handled by
//  ContentView's key monitor; the menu entry is there to display them.
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
        enum Rule {
            /// Files dragged onto the Dock icon: the drop rules — two compare,
            /// more open a tab each.
            case drop
            /// An explicit Open (Finder's menu): a tab each.
            case tabs
            /// Finder's Compare: the first file as File A, `compareURL` as B.
            case compare
            /// The website's button found no single match: the Open dialog,
            /// starting in the folder of the first candidate if there was one.
            case choose
        }
        
        let urls: [URL]
        var compareURL: URL? = nil
        let rule: Rule
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // So nobody has to find it in System Settings › General › Login
        // Items & Extensions. Leaves it alone if it is on, or if it has been
        // turned off.
        FinderExtension.switchOnUnlessTurnedOff()
        
        retargetCloseShortcut()
        observeMenuRebuilds()
        
        // Preview clips left behind by a copy of the app that crashed or was
        // force-quit.
        DispatchQueue.global(qos: .utility).async { PreviewLeftovers.sweep() }
    }
    
    /// Quitting with a preview open deletes its temporary files too.
    func applicationWillTerminate(_ notification: Notification) {
        MediaPreviewController.shared.close()
    }
    
    // MARK: - Freeing up ⌘W
    //
    // AppKit's Close item claims ⌘W, and menu key equivalents are matched in
    // `NSApplication.sendEvent` before the key press reaches the responder
    // chain — so the app's own ⌘W command (close the tab) would never fire
    // while that item still holds the chord.
    //
    // It is moved to ⌥⌘W rather than stripped. Leaving the window with no
    // keyboard route to close at all, so that only the red traffic light works,
    // would be a worse outcome than one unfamiliar chord.
    //
    // The move is deferred by one run-loop turn, because SwiftUI builds the
    // main menu after `applicationDidFinishLaunching`.

    /// Re-applies the move whenever the menu bar changes. SwiftUI rebuilds the
    /// File menu as tabs open and close (Close Tab's label and Close All Tabs'
    /// enabled state follow the tab count), and a rebuilt AppKit Close comes
    /// back holding ⌘W. ContentView handles ⌘W directly, so the key is safe
    /// either way; this keeps the menu honest, with one ⌘W item, not two.
    private func observeMenuRebuilds() {
        let center = NotificationCenter.default

        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleRetarget()
                }
            }
        }
    }

    /// Coalesces a burst of menu notifications into one pass.
    private var retargetScheduled = false

    private func scheduleRetarget() {
        guard !retargetScheduled else { return }
        retargetScheduled = true

        DispatchQueue.main.async {
            self.retargetScheduled = false
            self.retargetCloseShortcut()
        }
    }

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
    //   • the Finder Sync extension's swiftmediainfo://open URL
    //   • the website's swiftmediainfo://find URL (Open in SwiftMediaInfo)
    
    func application(_ application: NSApplication, open urls: [URL]) {
        // Files arrive together when several are dropped on the Dock icon or
        // opened at once — kept together, so the drop rules can see them all.
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty {
            enqueue(OpenRequest(urls: files, rule: .drop))
        }
        
        for url in urls where !url.isFileURL {
            if let lookup = parseFindURL(url) {
                Task { @MainActor in
                    let matches = await FileLookup.files(named: lookup.name, size: lookup.size, modified: lookup.modified)
                    enqueue(matches.count == 1
                            ? OpenRequest(urls: matches, rule: .tabs)
                            : OpenRequest(urls: Array(matches.prefix(1)), rule: .choose))
                }
            } else if let request = parseCustomURL(url) {
                enqueue(request)
            }
        }
    }
    
    /// Decodes swiftmediainfo://find?name=…&size=…&modified=… — the website's
    /// Open in SwiftMediaInfo button. A browser knows a file's name, size and
    /// modification date (milliseconds since 1970), never its location, so
    /// the file is looked up here (FileLookup).
    private func parseFindURL(_ url: URL) -> (name: String, size: Int64?, modified: Date?)? {
        guard url.scheme?.lowercased() == "swiftmediainfo", url.host()?.lowercased() == "find",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let name = items.first(where: { $0.name == "name" })?.value, !name.isEmpty
        else { return nil }
        let size = items.first(where: { $0.name == "size" })?.value.flatMap { Int64($0) }
        let modified = items.first(where: { $0.name == "modified" })?.value
            .flatMap { Double($0) }
            .map { Date(timeIntervalSince1970: $0 / 1000) }
        return (name, size, modified)
    }
    
    /// Decodes swiftmediainfo://open?path=…&compare=…
    ///
    /// `path` may repeat, for several items opened from Finder at once.
    ///
    /// Both paths are validated before use: they must be absolute and must
    /// actually exist. A malformed or stale URL is ignored rather than
    /// producing a confusing error.
    private func parseCustomURL(_ url: URL) -> OpenRequest? {
        guard url.scheme?.lowercased() == "swiftmediainfo" else { return nil }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return nil }
        
        func fileURLs(named name: String) -> [URL] {
            items
                .filter { $0.name == name }
                .compactMap(\.value)
                .filter { $0.hasPrefix("/") && FileManager.default.fileExists(atPath: $0) }
                .map { URL(fileURLWithPath: $0) }
        }
        
        let paths = fileURLs(named: "path")
        guard !paths.isEmpty else { return nil }
        
        if let compare = fileURLs(named: "compare").first {
            return OpenRequest(urls: [paths[0]], compareURL: compare, rule: .compare)
        }
        return OpenRequest(urls: paths, rule: .tabs)
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
            switch request.rule {
            case .drop:
                store.openDropped(request.urls)
            case .tabs:
                store.openTabs(request.urls)
            case .compare:
                if let first = request.urls.first { store.openURL(first) }
                if let compareURL = request.compareURL { store.openCompareURL(compareURL) }
            case .choose:
                NSApp.activate()
                store.openFilePicker(startingIn: request.urls.first?.deletingLastPathComponent())
            }
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
            // The store, because About reads the background preference —
            // without it the view traps the moment it is opened. The zoom
            // scale, so ⌘+ enlarges this window's contents like Settings and
            // Keyboard Shortcuts.
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
                // ⌘I, so About can be reached from the keyboard like Settings
                // (⌘,) and the shortcuts reference (⌘K). It's free here and
                // the conventional key for an information window.
                Button("About SwiftMediaInfo") {
                    openWindow(id: "about-window")
                }
                .keyboardShortcut("i", modifiers: .command)
            }
            
            CommandGroup(after: .newItem) {
                
                // An empty tab showing the start screen, as in Safari.
                Button("New Tab") {
                    mediaStore.openNewTab()
                }
                .keyboardShortcut("t", modifiers: .command)
                
                // Single "Open…" that allows files AND folders
                Button("Open…") {
                    mediaStore.openFilePicker()
                }
                .keyboardShortcut("o", modifiers: .command)
                
                // ⌘W closes the tab, not the window.
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
                //
                // The label says what ⌘W closes; the item and its key
                // equivalent never go away (see the note on file actions
                // below).
                Button(mediaStore.tabs.isEmpty && mediaStore.newTab == nil ? "Close" : "Close Tab") {
                    handleCloseCommand()
                }
                .keyboardShortcut("w", modifiers: .command)

                Button("Close All Tabs") {
                    mediaStore.closeAllTabs()
                }
                .disabled(mediaStore.tabs.count < 2)

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
                
                // Favorites. Each starred file has its own submenu:
                // open it, or compare it with the file on screen — offered
                // only when there is a file on screen and the favorite is a
                // different file, so the menu never holds a dead item.
                Menu("Favorites") {
                    if mediaStore.favoriteURLs.isEmpty {
                        Text("No Favorites")
                        Text("Star a tab to add it here")
                    } else {
                        ForEach(mediaStore.favoriteURLs, id: \.self) { url in
                            let exists = mediaStore.favoriteExists(url)
                            
                            Menu {
                                Button("Open File") {
                                    mediaStore.openURL(url)
                                }
                                .disabled(!exists)
                                
                                if mediaStore.canCompareWithCurrentFile(url) {
                                    Button("Compare with Current File") {
                                        mediaStore.openCompareURL(url)
                                    }
                                }
                                
                                Divider()
                                
                                Button("Remove from Favorites") {
                                    mediaStore.removeFavorite(url)
                                }
                            } label: {
                                Label(
                                    exists ? url.lastPathComponent : "\(url.lastPathComponent) — Missing",
                                    systemImage: FileTabBar.symbol(for: url)
                                )
                            }
                        }
                        
                        Divider()
                        
                        Button("Clear Favorites") {
                            mediaStore.clearFavorites()
                        }
                    }
                }
                
                Divider()
                
                // ── File actions ───────────────────────────────────────
                //
                // In Compare Mode these become two submenus rather than flat
                // items, and the key equivalents come off. A single ⇧⌘R that
                // silently picked File A would act on a file the user may not
                // have meant — better to make them say which file than to
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
                
                Divider()
                
                // Always present, so its key equivalent never goes stale (see
                // the note above); disabled with nothing open. In
                // Compare Mode it opens on File A, and the window itself
                // switches between the two files.
                Button("Check Media Health…") {
                    mediaStore.showMediaHealth()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(!mediaStore.canCheckHealth)
                
                ExplainMenuItem(store: mediaStore)
            }
            
            // View modes, mirroring the toolbar. No key equivalents shown on
            // purpose: ⌃⌘1–⌃⌘6 are handled by ContentView (⌘1–⌘9 select
            // tabs), and this menu lists the modes without keys.
            CommandGroup(before: .toolbar) {
                // Toggles rather than an inline Picker: the Picker wraps
                // itself in its own separators and a header, which doubled up
                // with the divider below.
                ForEach(ViewMode.allCases) { mode in
                    Toggle(isOn: Binding(
                        get: { mediaStore.viewMode == mode },
                        set: { isOn in
                            guard isOn else { return }
                            smiWithAnimation(SMI.Motion.smooth) {
                                mediaStore.viewMode = mode
                            }
                        }
                    )) {
                        Label(mode.label, systemImage: mode.icon)
                    }
                }
                
                Divider()
            }
            
            // Next / previous tab, with Safari's keys: ⌘⇧] / ⌘⇧[. Control-Tab
            // also works, but is handled by ContentView's key monitor — text
            // views swallow it before a menu would ever see it.
            CommandGroup(before: .windowArrangement) {
                Button("Show Next Tab") {
                    mediaStore.selectAdjacentTab(1)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(mediaStore.tabs.count < 2)

                Button("Show Previous Tab") {
                    mediaStore.selectAdjacentTab(-1)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(mediaStore.tabs.count < 2)
                
                // Folder tabs: step through the folder's files. The keys are
                // handled by ContentView's monitor; declared here so the menu
                // shows them. Off in Compare Mode, as the keys are.
                Button("Next File in Folder") {
                    mediaStore.selectAdjacentFolderItem(1)
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(mediaStore.currentFolder == nil || mediaStore.isCompareMode)
                
                Button("Previous File in Folder") {
                    mediaStore.selectAdjacentFolderItem(-1)
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(mediaStore.currentFolder == nil || mediaStore.isCompareMode)

                Divider()
            }

            CommandGroup(replacing: .help) {
                
                Button("Keyboard Shortcuts") {
                    openWindow(id: "shortcuts-window")
                }
                .keyboardShortcut("k", modifiers: .command)
                
                Divider()
                
                // ⌘/ opens the app's own page (it used to open the GitHub
                // repository, from before the app had a page).
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
// Kept out of the `.commands` builder because a result builder is a poor
// place for branching logic — and because this needs to be readable.

private extension MediaInfoMacApp {
    
    func handleCloseCommand() {
        let key = NSApp.keyWindow
        
        let isDocumentWindow =
        key?.identifier?.rawValue == DocumentWindowMarker.identifier
        
        let hasFile =
        mediaStore.currentFile != nil || mediaStore.compareFile != nil || mediaStore.newTab != nil
        
        if isDocumentWindow && hasFile {
            mediaStore.closeFile()
        } else {
            // Settings, About, Keyboard Shortcuts — or the document window
            // with no tabs left, which closes it and quits the app.
            key?.performClose(nil)
        }
    }
}
