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
                            Text("Drop media files to analyse")
                                .font(.headline)
                        }
                    )
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            var urls: [URL] = []
            let group = DispatchGroup()
            for provider in providers {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    if let data = item as? Data,
                       let url  = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) { store.addURLs(urls) }
            return true
        }
        .background(
            Group {
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