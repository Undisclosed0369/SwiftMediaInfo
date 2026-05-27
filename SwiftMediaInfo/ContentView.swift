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
                
                // ── Compare mode shortcut (⇧⌘C) ───────────────────────────
                Button("") { handleCompareShortcut() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                
                // ── CHANGE 3: Open in default app shortcut (⌘↩) ──────────
                //
                // ⌘↩ (Command + Return) opens the current file in its default
                // app — same as clicking the "Open in App" button in the toolbar.
                // In compare mode, it opens File A (the primary file).
                // We reuse the exact same OpenInDefaultAppButton.openInDefaultApp
                // helper so the behaviour is identical to the toolbar button.
                Button("") { handleOpenInDefaultApp() }
                    .keyboardShortcut(.return, modifiers: .command)
                
                // ── Zoom shortcuts ────────────────────────────────────────
                Button("") { store.zoomIn()  }.keyboardShortcut("+", modifiers: .command)
                Button("") { store.zoomIn()  }.keyboardShortcut("=", modifiers: .command)
                Button("") { store.zoomOut() }.keyboardShortcut("-", modifiers: .command)
                
                // ── View mode shortcuts (⌘1 – ⌘6) ────────────────────────
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
    
    // MARK: - Open in default app handler (⌘↩)
    //
    // If a file is open, launch it in its default app.
    // In compare mode, we open the primary file (File A).
    // This does nothing if no file is loaded yet.
    
    private func handleOpenInDefaultApp() {
        if let url = store.currentFile?.url {
            OpenInDefaultAppButton.openInDefaultApp(url)
        }
    }
    
    // MARK: - Compare shortcut handler
    //
    // ⇧⌘C toggles compare mode on/off.
    // If compare mode is off and no file is open yet, open a file first.
    
    private func handleCompareShortcut() {
        if store.isCompareMode {
            store.exitCompareMode()
        } else {
            if store.currentFile == nil { store.openFilePicker() }
            store.openCompareFilePicker()
        }
    }
    
    // MARK: - Number shortcut handler
    
    private func handleShortcut(_ number: Int) {
        if store.isCompareMode {
            switch number {
            case 1: store.openFilePicker()
            case 2: store.openCompareFilePicker()
            default:
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
