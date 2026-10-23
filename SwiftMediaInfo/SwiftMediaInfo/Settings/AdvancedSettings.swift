//
//  AdvancedSettings.swift
//  SwiftMediaInfo
//
//  Settings › Advanced: the environment summary for bug reports (copyable,
//  with no file paths or personal data), Report an Issue, and Restore
//  Default Settings (MediaStore.resetSettingsToDefaults).
//

import SwiftUI
import AppKit

// MARK: - Advanced

struct AdvancedSettings: View {
    @Environment(\.smiScale) private var scale
    
    @EnvironmentObject var store: MediaStore
    @State private var showResetConfirmation = false
    @State private var didCopyDiagnostics = false
    
    private var tint: Color { SettingsSection.advanced.tint }
    
    /// Read straight from the store so the summary reflects whatever is known
    /// by the time it is copied.
    private var mediaInfoVersion: String? { store.mediaInfoVersion }
    
    var body: some View {
        VStack(alignment: .leading, spacing: scale.s(SMI.Spacing.xLarge)) {
            
            SettingsGroup(title: "Diagnostics", tint: tint) {
                SettingsRow(
                    title: "Environment summary",
                    explanation: "Version, macOS build, MediaInfo location, and your current settings. Handy to paste into a bug report — it contains no file paths or personal data.",
                    isFirst: true
                ) {
                    Button(didCopyDiagnostics ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(diagnosticsText, forType: .string)
                        
                        smiWithAnimation(SMI.Motion.snap) { didCopyDiagnostics = true }
                        
                        Task {
                            try? await Task.sleep(nanoseconds: 1_600_000_000)
                            await MainActor.run {
                                smiWithAnimation(SMI.Motion.fade) { didCopyDiagnostics = false }
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(didCopyDiagnostics ? SMI.Palette.success : nil)
                }
                
                SettingsRow(
                    title: "Report an issue",
                    explanation: "Opens the project's issue tracker on GitHub."
                ) {
                    Button("Open") {
                        ProjectLinks.open(ProjectLinks.issues)
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            SettingsGroup(title: "Reset", tint: tint) {
                SettingsRow(
                    title: "Restore default settings",
                    explanation: "Returns every preference on every page to its original value. Your recent files and the file currently open are left alone.",
                    isFirst: true
                ) {
                    Button("Reset…", role: .destructive) {
                        showResetConfirmation = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .confirmationDialog(
            "Restore default settings?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore Defaults", role: .destructive) {
                smiWithAnimation(SMI.Motion.smooth) { store.resetSettingsToDefaults() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Appearance, effects, analysis, text size, preview playback and the Finder menu return to their defaults. Recent files are kept.")
        }
    }
    
    private var diagnosticsText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let arch: String
#if arch(arm64)
        arch = "arm64"
#else
        arch = "x86_64"
#endif
        
        // The palette, named where it has a name and spelled out where it
        // does not. A bug report saying "Ember" is instantly reproducible; one
        // saying "custom" is not, and the three hexes are what make the
        // difference between the two.
        let hexes = BackgroundPalette.current.map(\.smiHex)
        let palette = GradientPreset.matching(hexes)?.title
        ?? "custom (\(hexes.joined(separator: ", ")))"
        
        return """
        SwiftMediaInfo \(short) (\(build))
        macOS: \(os)
        Architecture: \(arch)
        MediaInfo: \(MediaEngine.resolveBinaryPath() ?? "not found")
        MediaInfo version: \(mediaInfoVersion ?? "unknown")
        Analysis timeout: \(Int(store.analysisTimeoutSeconds))s
        Liquid Glass: \(GlassPreference.isEnabled ? "on" : "off")
        Background: \(store.backgroundMode.rawValue)
        Palette: \(palette)
        Appearance: \(store.appearanceMode.rawValue)
        Text size: \(Int(store.fontSize))pt
        """
    }
}
