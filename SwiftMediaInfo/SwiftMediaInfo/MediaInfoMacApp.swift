//
//  MediaInfoMacApp.swift
//  SwiftMediaInfo
//

import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    
    weak var mediaStore: MediaStore?
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Automatically enable the Finder Sync Extension so users don't
        // have to go to System Settings → Extensions and toggle it on manually.
        // Uses pluginkit under the hood — safe to call every launch;
        // it's a no-op if the extension is already enabled.
        enableFinderExtension()
    }
    
    // Handles:
    // - Dragging file onto dock icon
    // - Finder "Open With"
    // - Opening files associated with app
    
    func application(_ application: NSApplication, open urls: [URL]) {
        
        guard let firstURL = urls.first else {
            return
        }
        
        DispatchQueue.main.async {
            self.mediaStore?.openURL(firstURL)
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
        }
        .windowResizability(.contentSize)
        
        .commands {
            
            CommandGroup(replacing: .appInfo) {
                Button("About SwiftMediaInfo") {
                    openWindow(id: "about-window")
                }
            }
            
            CommandGroup(after: .newItem) {
                
                // Single "Open…" that allows files AND folders
                Button("Open…") {
                    mediaStore.openFilePicker()
                }
                .keyboardShortcut("o", modifiers: .command)
                
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
            }
            
            CommandGroup(replacing: .help) {
                
                Button("SwiftMediaInfo Help") {
                    if let url = URL(string: "https://github.com/Undisclosed0369/SwiftMediaInfo") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut("/", modifiers: .command)
                
                Divider()
                
                Button("Report Issues / Bugs") {
                    if let url = URL(string: "https://github.com/Undisclosed0369/SwiftMediaInfo/issues") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}
