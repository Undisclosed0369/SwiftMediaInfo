//
//  ContentView.swift
//  SwiftMediaInfo
//
//  Created by Undisclosed on 23/4/26.
//

//
//  ContentView.swift
//  SwiftMediaInfo
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
                // ── Export shortcut ───────────────────────────────────────
                Button("") { store.showExportMenu = true }
                    .keyboardShortcut("e", modifiers: .command)
                
                // ── Zoom shortcuts ────────────────────────────────────────
                Button("") { store.zoomIn()  }.keyboardShortcut("+", modifiers: .command)
                Button("") { store.zoomIn()  }.keyboardShortcut("=", modifiers: .command)
                Button("") { store.zoomOut() }.keyboardShortcut("-", modifiers: .command)
                
                // ── View mode shortcuts (⌘1 – ⌘6) ────────────────────────
                // In normal mode: switches view tabs.
                // In compare mode: ⌘1 opens File A picker, ⌘2 opens File B picker.
                // We always wire both behaviours and decide at runtime.
                Button("") { handleShortcut(1) }.keyboardShortcut("1", modifiers: .command)
                Button("") { handleShortcut(2) }.keyboardShortcut("2", modifiers: .command)
                Button("") { handleShortcut(3) }.keyboardShortcut("3", modifiers: .command)
                Button("") { handleShortcut(4) }.keyboardShortcut("4", modifiers: .command)
                Button("") { handleShortcut(5) }.keyboardShortcut("5", modifiers: .command)
                Button("") { handleShortcut(6) }.keyboardShortcut("6", modifiers: .command)
            }
                .opacity(0)
        )
    }
    
    // MARK: - Shortcut handler
    //
    // ⌘1–⌘6 behaviour:
    //   • Normal mode  → switch to the matching ViewMode tab
    //   • Compare mode → ⌘1 = open/replace File A,  ⌘2 = open/replace File B
    //                    ⌘3–⌘6 still switch the view tab (affects both panes)
    
    private func handleShortcut(_ number: Int) {
        if store.isCompareMode {
            switch number {
            case 1: store.openFilePicker()
            case 2: store.openCompareFilePicker()
            default:
                // Numbers 3-6 switch view tabs even in compare mode
                if let mode = ViewMode.allCases.first(where: {
                    $0.shortcut == KeyEquivalent(Character(String(number)))
                }) {
                    store.viewMode = mode
                }
            }
        } else {
            if let mode = ViewMode.allCases.first(where: {
                $0.shortcut == KeyEquivalent(Character(String(number)))
            }) {
                store.viewMode = mode
            }
        }
    }
}
