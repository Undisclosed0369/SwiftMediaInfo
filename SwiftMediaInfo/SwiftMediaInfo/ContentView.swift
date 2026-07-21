//
//  ContentView.swift
//  SwiftMediaInfo
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: MediaStore
    @Environment(\.openWindow) private var openWindow
    @State private var isTargeted = false
    
    var body: some View {
        ZStack {
            // ── Animated gradient wallpaper (behind everything) ────────────
            if store.showAnimatedBackground {
                AnimatedGradientBackground()
                    .transition(.opacity)
            }
            
            // ── Main layout ────────────────────────────────────────────────
            VStack(spacing: 0) {
                ToolbarView()
                SpectrumDivider()
                MainDetailView()
                SpectrumDivider()
                StatusBar()
            }
            
            // ── Search bar overlay ─────────────────────────────────────────
            SearchBarOverlay()
            
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
        .sheet(isPresented: $store.showShareResult) {
            ShareResultView()
                .environmentObject(store)
        }
        .alert("Unsupported Mode",
               isPresented: $store.showDiffUnsupportedPrompt) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Difference highlighting is only available in Easy View, Text View, and Raw Text View. Please switch to one of these modes to use this feature.")
        }
        .background(
            Color.clear
                .onAppear { installArrowKeyMonitor() }
                .onDisappear { removeArrowKeyMonitor() }
        )
        .background(
            Group {
                Button("") { store.showExportMenu = true }
                    .keyboardShortcut("e", modifiers: .command)
                
                Button("") { handleCompareShortcut() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                
                Button("") { handleOpenInDefaultApp() }
                    .keyboardShortcut(.return, modifiers: .command)
                
                Button("") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        store.showAnimatedBackground.toggle()
                    }
                }
                .keyboardShortcut("b", modifiers: .command)
                
                // Toggle diff highlighting (⌘D)
                Button("") {
                    if store.isCompareMode {
                        if [ViewMode.easy, .text, .rawText].contains(store.viewMode) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                store.showDiffHighlight.toggle()
                            }
                        } else {
                            store.showDiffUnsupportedPrompt = true
                        }
                    }
                }
                .keyboardShortcut("d", modifiers: .command)
                
                // Show keyboard shortcuts (⌘K)
                Button("") { openWindow(id: "shortcuts-window") }
                    .keyboardShortcut("k", modifiers: .command)
                
                // Toggle search bar (⌘F)
                Button("") { store.toggleSearchBar() }
                    .keyboardShortcut("f", modifiers: .command)
                
                Button("") { store.zoomIn()  }.keyboardShortcut("+", modifiers: .command)
                Button("") { store.zoomIn()  }.keyboardShortcut("=", modifiers: .command)
                Button("") { store.zoomOut() }.keyboardShortcut("-", modifiers: .command)
                Button("") { store.resetZoom() }.keyboardShortcut("0", modifiers: .command)
                
                Button("") { store.cycleAppearance() }
                    .keyboardShortcut("m", modifiers: .command)
                
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
    
    // MARK: - Arrow key search navigation
    
    @State private var arrowKeyMonitor: Any? = nil
    
    private func installArrowKeyMonitor() {
        guard arrowKeyMonitor == nil else { return }
        arrowKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard self.store.showSearchBar && !self.store.searchQuery.isEmpty else { return event }
            
            // Only intercept if the search text field is NOT focused
            if let responder = event.window?.firstResponder as? NSTextView,
               responder.isFieldEditor {
                return event  // let the search bar handle typing
            }
            
            switch event.keyCode {
            case 125, 124:  // Down arrow, Right arrow → next match
                guard self.store.searchMatchCount > 0 else { return event }
                self.store.searchMatchIndex = (self.store.searchMatchIndex + 1) % self.store.searchMatchCount
                return nil
            case 126, 123:  // Up arrow, Left arrow → previous match
                guard self.store.searchMatchCount > 0 else { return event }
                self.store.searchMatchIndex = (self.store.searchMatchIndex - 1 + self.store.searchMatchCount) % self.store.searchMatchCount
                return nil
            default:
                return event
            }
        }
    }
    
    private func removeArrowKeyMonitor() {
        if let monitor = arrowKeyMonitor {
            NSEvent.removeMonitor(monitor)
            arrowKeyMonitor = nil
        }
    }
}
