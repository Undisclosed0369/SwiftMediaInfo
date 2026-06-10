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
            // ── Animated gradient wallpaper (behind everything) ────────────
            AnimatedGradientBackground()
            
            // ── Main layout ────────────────────────────────────────────────
            VStack(spacing: 0) {
                ToolbarView()
                SpectrumDivider()
                MainDetailView()
                SpectrumDivider()
                StatusBar()
            }
            
            // ── Drop highlight overlay ─────────────────────────────────────
            if isTargeted {
                GlassDropOverlay(color: .brandViolet)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers, _ in
            Task { @MainActor in
                withAnimation(.spring(response: 0.25)) { isTargeted = true }
                if let provider = providers.first,
                   let item = try? await provider.loadItem(
                    forTypeIdentifier: UTType.fileURL.identifier
                   ),
                   let data = item as? Data,
                   let url  = URL(dataRepresentation: data, relativeTo: nil) {
                    store.openURL(url)
                }
                try? await Task.sleep(nanoseconds: 350_000_000)
                withAnimation(.spring(response: 0.25)) { isTargeted = false }
            }
            return true
        }
        .background(
            Group {
                Button("") { store.showExportMenu = true }
                    .keyboardShortcut("e", modifiers: .command)
                
                Button("") { handleCompareShortcut() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                
                Button("") { handleOpenInDefaultApp() }
                    .keyboardShortcut(.return, modifiers: .command)
                
                Button("") { store.zoomIn()  }.keyboardShortcut("+", modifiers: .command)
                Button("") { store.zoomIn()  }.keyboardShortcut("=", modifiers: .command)
                Button("") { store.zoomOut() }.keyboardShortcut("-", modifiers: .command)
                
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
    
    private func handleOpenInDefaultApp() {
        if let url = store.currentFile?.url {
            OpenInDefaultAppButton.openInDefaultApp(url)
        }
    }
    
    private func handleCompareShortcut() {
        if store.isCompareMode {
            store.exitCompareMode()
        } else {
            if store.currentFile == nil { store.openFilePicker() }
            store.openCompareFilePicker()
        }
    }
    
    private func handleShortcut(_ number: Int) {
        if store.isCompareMode {
            switch number {
            case 1: store.openFilePicker()
            case 2: store.openCompareFilePicker()
            default:
                if let mode = ViewMode.allCases.first(where: {
                    $0.shortcut == KeyEquivalent(Character(String(number)))
                }) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        store.viewMode = mode
                    }
                }
            }
        } else {
            if let mode = ViewMode.allCases.first(where: {
                $0.shortcut == KeyEquivalent(Character(String(number)))
            }) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    store.viewMode = mode
                }
            }
        }
    }
}
