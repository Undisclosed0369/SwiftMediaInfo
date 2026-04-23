//
//  MediaInfoMacApp.swift
//  SwiftMediaInfo
//
//  Created by Undisclosed on 23/4/26.
//

import SwiftUI

@main
struct MediaInfoMacApp: App {
    
    @StateObject private var mediaStore = MediaStore()
    @Environment(\.openWindow) private var openWindow
    
    var body: some Scene {
        
        WindowGroup {
            ContentView()
                .environmentObject(mediaStore)
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
        }
    }
}
