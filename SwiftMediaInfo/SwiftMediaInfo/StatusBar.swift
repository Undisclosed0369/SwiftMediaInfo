//
//  StatusBar.swift
//  SwiftMediaInfo
//

import SwiftUI
import AppKit

struct StatusBar: View {
    @EnvironmentObject var store: MediaStore
    @State private var isInstalling = false
    @State private var appeared = false
    
    private var isMediaInfoMissing: Bool {
        let path = MediaEngine.binaryPath
        if path.hasPrefix("/") {
            return !FileManager.default.fileExists(atPath: path)
        }
        return true
    }
    
    var body: some View {
        HStack(spacing: 12) {
            if isMediaInfoMissing {
                missingMediaInfoWarning
            } else if let file = store.currentFile {
                if file.isLoading {
                    loadingItems(file: file)
                } else {
                    fileItems(file: file)
                }
            } else {
                Text("No file open")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .onAppear {
            withAnimation(.easeIn(duration: 0.4)) { appeared = true }
        }
    }
    
    // MARK: - Loading state
    
    @ViewBuilder
    private func loadingItems(file: MediaFile) -> some View {
        statusChip(icon: "doc", text: file.fileName, color: .brandBlue)
        statusChip(icon: "internaldrive", text: file.fileSizeString, color: .brandViolet)
        Spacer()
        
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.55)
                .tint(.brandViolet)
            Text("Analysing…")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.brandViolet)
        }
    }
    
    // MARK: - Loaded state
    
    @ViewBuilder
    private func fileItems(file: MediaFile) -> some View {
        if let general = file.generalTrack {
            if let fmt = general.fields.first(where: { $0.key == "Format" })?.value {
                statusChip(icon: "doc", text: fmt, color: .brandBlue)
            }
            
            if let dur = general.fields.first(where: { $0.key == "Duration_String3" })?.value
                ?? general.fields.first(where: { $0.key == "Duration_String" })?.value
                ?? general.fields.first(where: { $0.key == "Duration" })?.value {
                statusChip(icon: "clock", text: dur, color: .brandViolet)
            }
            if let br = general.fields.first(where: { $0.key == "OverallBitRate_String" })?.value
                ?? general.fields.first(where: { $0.key == "OverallBitRate" })?.value {
                statusChip(icon: "waveform.path", text: br, color: .brandPink)
            }
        }
        
        if let video = file.videoTracks.first {
            let w = video.fields.first(where: { $0.key == "Width"  })?.value ?? ""
            let h = video.fields.first(where: { $0.key == "Height" })?.value ?? ""
            if !w.isEmpty {
                statusChip(icon: "film", text: "\(w)×\(h)", color: .brandBlue)
            }
            if let fps = video.fields.first(where: { $0.key == "FrameRate" })?.value {
                statusChip(icon: "speedometer", text: "\(fps) fps", color: .brandGreen)
            }
        }
        
        if !file.audioTracks.isEmpty {
            let n = file.audioTracks.count
            statusChip(
                icon: "waveform",
                text: "\(n) audio stream\(n == 1 ? "" : "s")",
                color: .brandViolet
            )
        }
        
        if !file.textTracks.isEmpty {
            let n = file.textTracks.count
            statusChip(
                icon: "captions.bubble",
                text: "\(n) subtitle\(n == 1 ? "" : "s")",
                color: .brandGreen
            )
        }
        
        Spacer()
        statusChip(icon: "internaldrive", text: file.fileSizeString, color: .brandPink)
    }
    
    // MARK: - Status chip
    
    private func statusChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color.opacity(0.85))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(0.75))
        }
    }
    
    // MARK: - Missing mediainfo warning
    
    private var missingMediaInfoWarning: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                Text("mediainfo not installed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.red.opacity(0.85))
            )
            
            Text("SwiftMediaInfo requires the MediaInfo CLI.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button(action: installMediaInfo) {
                HStack(spacing: 5) {
                    if isInstalling {
                        ProgressView().scaleEffect(0.55)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(LinearGradient.brandBlueViolet)
                    }
                    Text(isInstalling ? "Installing…" : "Install via Homebrew")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandViolet)
            .disabled(isInstalling)
        }
    }
    
    // MARK: - Install
    
    private func installMediaInfo() {
        isInstalling = true
        
        let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        guard let brewPath = brewPaths.first(where: {
            FileManager.default.fileExists(atPath: $0)
        }) else {
            isInstalling = false
            if let url = URL(string: "https://brew.sh") { NSWorkspace.shared.open(url) }
            let a = NSAlert()
            a.messageText = "Homebrew Not Installed"
            a.informativeText = "Install Homebrew first, then try again."
            a.runModal()
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments = ["install", "mediainfo"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError  = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                DispatchQueue.main.async {
                    isInstalling = false
                    let a = NSAlert()
                    if process.terminationStatus == 0 {
                        a.messageText = "MediaInfo Installed"
                        a.informativeText = "mediainfo was installed successfully. You can now use SwiftMediaInfo normally."
                    } else {
                        a.messageText = "Installation Failed"
                        a.informativeText = "Try running manually:\n\(brewPath) install mediainfo"
                    }
                    a.runModal()
                }
            } catch {
                DispatchQueue.main.async {
                    isInstalling = false
                    let a = NSAlert()
                    a.messageText = "Failed to Start Installation"
                    a.informativeText = error.localizedDescription
                    a.runModal()
                }
            }
        }
    }
}
