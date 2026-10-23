//
//  ToolsSettings.swift
//  SwiftMediaInfo
//
//  Settings › Tools: MediaInfo (status, version, location, Re-detect,
//  install or reinstall) and ffmpeg (the same, for the preview). The page's
//  section case is still `.mediaInfo`, from before it was named Tools.
//

import SwiftUI

// MARK: - Tools

struct ToolsSettings: View {
    @Environment(\.smiScale) private var scale
    
    // The shared instance, so an install started here is visible in
    // the status bar and vice versa, and neither can start a second `brew`
    // while the other is running.
    @ObservedObject private var installer = DependencyInstaller.shared
    
    // Needed so an install started here can re-read whatever file is open in
    // the main window, exactly as the status bar's install does.
    @EnvironmentObject private var store: MediaStore
    
    @State private var version: String? = nil
    @State private var isChecking = false
    @State private var resolvedPath: String? = nil
    
    private var tint: Color { SettingsSection.mediaInfo.tint }
    
    private var isInstalled: Bool { resolvedPath != nil }
    
    private var installExplanation: String {
        if isInstalled {
            return "Already installed. Reinstalling would upgrade it to the latest version Homebrew has."
        }
        if DependencyInstaller.isHomebrewInstalled {
            return "Runs brew install mediainfo for you. Homebrew prints no progress percentage, so there is a spinner rather than a bar that would only be guessing."
        }
        return "Homebrew isn't installed. Opening brew.sh is the first step; come back here afterwards."
    }
    
    /// The installer is shared by both tools, so each row only shows a
    /// spinner or a tick for its own package.
    @ViewBuilder
    private func installControl(_ package: String, installed: Bool, onDone: @escaping () -> Void) -> some View {
        switch installer.state {
        case .installing(let current) where current == package:
            HStack(spacing: scale.s(SMI.Spacing.small)) {
                ProgressView().controlSize(.small)
                Text("Installing…")
                    .font(scale.font(12, .medium))
                    .foregroundStyle(.secondary)
            }
            
        case .succeeded(let current) where current == package:
            HStack(spacing: scale.s(SMI.Spacing.snug)) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(SMI.Palette.success)
                Text("Installed")
                    .font(scale.font(12, .medium))
                    .foregroundStyle(.secondary)
            }
            
        default:
            Button(installed ? "Reinstall" : "Install") {
                installer.install(package, onCompletion: onDone)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .disabled(installer.isInstalling)
        }
    }
    
    private var installControl: some View {
        installControl("mediainfo", installed: isInstalled) {
            refresh()
            store.retryAfterDependencyInstall()
        }
    }
    
    // MARK: ffmpeg
    
    @State private var ffmpegPath: String? = nil
    
    private var ffmpegExplanation: String {
        if ffmpegPath != nil {
            return "Already installed. Reinstalling would upgrade it to the latest version Homebrew has."
        }
        if DependencyInstaller.isHomebrewInstalled {
            return "Runs brew install ffmpeg for you. It can take a few minutes — ffmpeg is a large package."
        }
        return "Homebrew isn't installed. Opening brew.sh is the first step; come back here afterwards."
    }
    
    private var ffmpegGroup: some View {
        SettingsGroup(title: "ffmpeg", tint: tint) {
            SettingsRow(
                title: "Status",
                explanation: "Optional. Space previews MP4, MOV and most audio with Quick Look; MKV and other files macOS can't play are previewed with short clips that ffmpeg cuts from the original.",
                isFirst: true
            ) {
                HStack(spacing: scale.s(SMI.Spacing.snug)) {
                    Image(systemName: ffmpegPath != nil ? "checkmark.circle.fill" : "minus.circle.fill")
                        .foregroundStyle(ffmpegPath != nil ? SMI.Palette.success : Color.secondary)
                    Text(ffmpegPath != nil ? "Installed" : "Not installed")
                        .font(scale.font(12, .medium))
                        .foregroundStyle(.secondary)
                }
            }
            
            SettingsRow(
                title: "Location",
                explanation: "Where the binary was found."
            ) {
                Text(ffmpegPath ?? "Not found")
                    .font(scale.font(11, .regular, .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: scale.s(260), alignment: .trailing)
            }
            
            SettingsRow(
                title: "Install ffmpeg",
                explanation: ffmpegExplanation
            ) {
                installControl("ffmpeg", installed: ffmpegPath != nil) {
                    ffmpegPath = FFmpeg.path
                }
            }
        }
    }
    
    private func installFailureNotice(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: scale.s(SMI.Spacing.medium) - 2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SMI.Palette.warning)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Installation didn't finish")
                    .font(scale.font(12, .medium))
                Text(reason)
                    .font(scale.font(11, .regular, .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
            
            Button("Dismiss") { installer.reset() }
                .buttonStyle(.bordered)
        }
        .settingsNotice(tint: SMI.Palette.warning, scale: scale)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: scale.s(SMI.Spacing.xLarge)) {
            
            // One group for MediaInfo, as ffmpeg has one: what is installed,
            // then how to get or upgrade it.
            SettingsGroup(title: "MediaInfo", tint: tint) {
                SettingsRow(
                    title: "Status",
                    explanation: "SwiftMediaInfo reads metadata by running the MediaInfo command-line tool. Everything the app shows comes from it.",
                    isFirst: true
                ) {
                    statusBadge
                }
                
                SettingsRow(
                    title: "Version",
                    explanation: "Reported by MediaInfo itself."
                ) {
                    Group {
                        if isChecking {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(version ?? "—")
                                .font(scale.font(11, .regular, .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: scale.s(260), alignment: .trailing)
                        }
                    }
                }
                
                SettingsRow(
                    title: "Location",
                    explanation: "Where the binary was found. Homebrew installs to /opt/homebrew on Apple silicon and /usr/local on Intel."
                ) {
                    Text(resolvedPath ?? "Not found")
                        .font(scale.font(11, .regular, .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: scale.s(260), alignment: .trailing)
                }
                
                SettingsRow(
                    title: "Check again",
                    explanation: "Re-scans the usual locations. Useful straight after installing or upgrading MediaInfo."
                ) {
                    Button("Re-detect") { refresh() }
                        .buttonStyle(.bordered)
                        .disabled(isChecking)
                }

                SettingsRow(
                    title: "Install MediaInfo",
                    explanation: installExplanation
                ) {
                    installControl
                }
                
                SettingsRow(
                    title: "Download page",
                    explanation: "Official builds from MediaArea, if you'd rather not use Homebrew."
                ) {
                    Button("Open") {
                        ProjectLinks.open(ProjectLinks.mediaAreaDownload)
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            ffmpegGroup
            
            if case .failed(let reason) = installer.state {
                installFailureNotice(reason)
            }
        }
        .onAppear { refresh() }
        .smiAnimation(SMI.Motion.smooth, value: installer.state)
    }
    
    private var statusBadge: some View {
        let installed = resolvedPath != nil
        return HStack(spacing: scale.s(SMI.Spacing.snug)) {
            Image(systemName: installed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(installed ? SMI.Palette.success : SMI.Palette.warning)
            Text(installed ? "Installed" : "Not found")
                .font(scale.font(12, .medium))
                .foregroundStyle(.secondary)
        }
    }
    
    private func refresh() {
        isChecking = true
        MediaEngine.refreshBinaryLocation()
        resolvedPath = MediaEngine.resolveBinaryPath()
        ffmpegPath = FFmpeg.path
        
        Task {
            // Forced, because this runs from Re-detect as well as on appear,
            // and the whole point of Re-detect is to ignore what is cached.
            await store.loadMediaInfoVersion(force: true)
            await MainActor.run {
                version = store.mediaInfoVersion
                isChecking = false
            }
        }
    }
}
