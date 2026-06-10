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
                
                Button("Open File…") {
                    mediaStore.openFilePicker()
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Button("Open Folder…") {
                    mediaStore.openFolderPicker()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                
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
