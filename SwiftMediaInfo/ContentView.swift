//
//  ContentView.swift
//  SwiftMediaInfo
//
//  Created by Undisclosed on 23/4/26.
//


//
//  ContentView.swift
//  MediaInfoMac
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: MediaStore
    @State private var isTargeted = false
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ToolbarView()
                Divider()
                MainDetailView()
                Divider()
                StatusBar()
            }
            
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.08).cornerRadius(12))
                    .overlay(
                        VStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.accentColor)
                            Text("Drop a media file to analyse")
                                .font(.headline)
                        }
                    )
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        // isTargeted: nil — never let SwiftUI write back to @State during
        // a render pass, which caused the reentrant-message crash.
        .onDrop(of: [.fileURL], isTargeted: nil) { providers, _ in
            Task { @MainActor in
                isTargeted = true
                if let provider = providers.first,
                   let item = try? await provider.loadItem(
                    forTypeIdentifier: UTType.fileURL.identifier
                   ),
                   let data = item as? Data,
                   let url  = URL(dataRepresentation: data, relativeTo: nil) {
                    store.openURL(url)
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
                isTargeted = false
            }
            return true
        }
        .background(
            Group {
                // CMD+E: opens the export popover on the toolbar button
                Button("") { store.showExportMenu = true }
                    .keyboardShortcut("e", modifiers: .command)
                Button("") { store.zoomIn()  }.keyboardShortcut("+", modifiers: .command)
                Button("") { store.zoomIn()  }.keyboardShortcut("=", modifiers: .command)
                Button("") { store.zoomOut() }.keyboardShortcut("-", modifiers: .command)
            }
                .opacity(0)
        )
    }
}
