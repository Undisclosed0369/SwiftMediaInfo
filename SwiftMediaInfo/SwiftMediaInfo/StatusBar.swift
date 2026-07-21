//
//  StatusBar.swift
//  SwiftMediaInfo
//

import SwiftUI
import AppKit

struct StatusBar: View {
    @EnvironmentObject var store: MediaStore
    @State private var isInstalling = false
    @State private var installingTool = ""
    @State private var appeared = false
    
    // MARK: - Dependency checks
    
    private var missingDeps: [(name: String, path: String, brew: String?)] {
        var missing: [(String, String, String?)] = []
        
        let miPath = MediaEngine.binaryPath
        if miPath.hasPrefix("/") {
            if !FileManager.default.fileExists(atPath: miPath) {
                missing.append(("mediainfo", miPath, "mediainfo"))
            }
        } else {
            missing.append(("mediainfo", "", "mediainfo"))
        }
        
        if !FileManager.default.fileExists(atPath: "/usr/bin/curl") {
            missing.append(("curl", "/usr/bin/curl", nil))
        }
        
        if !FileManager.default.fileExists(atPath: "/usr/bin/zip") {
            missing.append(("zip", "/usr/bin/zip", nil))
        }
        
        return missing
    }
    
    var body: some View {
        if !missingDeps.isEmpty {
            missingDepsWarning
                .padding(.vertical, 7)
                .background(.ultraThinMaterial)
        } else if store.isCompareMode {
            compareStatusBar
                .background(.ultraThinMaterial)
        } else if let file = store.currentFile {
            singleFileBar(file: file)
                .background(.ultraThinMaterial)
        } else {
            HStack {
                Text("No file open")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }
    
    // MARK: - Single file bar
    
    @ViewBuilder
    private func singleFileBar(file: MediaFile) -> some View {
        HStack(spacing: 14) {
            if file.isLoading {
                statusChip(icon: "doc", text: file.fileName, color: .brandBlue)
                statusChip(icon: "internaldrive", text: file.fileSizeString, color: .brandViolet)
                Spacer()
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.brandViolet)
                    Text("Analysing…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.brandViolet)
                }
            } else {
                fileChips(file: file)
                Spacer()
                statusChip(icon: "internaldrive", text: file.fileSizeString, color: .brandPink)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    // MARK: - Compare mode: split at center
    
    private var compareStatusBar: some View {
        HStack(spacing: 0) {
            // Left half: File A
            HStack(spacing: 12) {
                fileBadge(label: "A", color: .brandBlue)
                if let fileA = store.currentFile, !fileA.isLoading {
                    fileChips(file: fileA)
                    Spacer(minLength: 4)
                    statusChip(icon: "internaldrive", text: fileA.fileSizeString, color: .brandPink)
                } else {
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            
            // Center divider
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 1, height: 18)
            
            // Right half: File B
            HStack(spacing: 12) {
                fileBadge(label: "B", color: .brandPink)
                if let fileB = store.compareFile, !fileB.isLoading {
                    fileChips(file: fileB)
                    Spacer(minLength: 4)
                    statusChip(icon: "internaldrive", text: fileB.fileSizeString, color: .brandPink)
                } else {
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
    }
    
    private func fileBadge(label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(color))
    }
    
    // MARK: - Shared file chips
    
    @ViewBuilder
    private func fileChips(file: MediaFile) -> some View {
        if let general = file.generalTrack {
            if let fmt = general.fields.first(where: { $0.key == "Format" })?.value {
                statusChip(icon: "doc.fill", text: fmt, color: .brandBlue)
            }
            
            if let dur = general.fields.first(where: { $0.key == "Duration_String3" })?.value
                ?? general.fields.first(where: { $0.key == "Duration_String" })?.value
                ?? general.fields.first(where: { $0.key == "Duration" })?.value {
                statusChip(icon: "clock.fill", text: dur, color: .brandViolet)
            }
            if let br = general.fields.first(where: { $0.key == "OverallBitRate_String" })?.value
                ?? general.fields.first(where: { $0.key == "OverallBitRate" })?.value {
                statusChip(icon: "bolt.fill", text: br, color: .brandPink)
            }
        }
        
        if let video = file.videoTracks.first {
            let w = video.fields.first(where: { $0.key == "Width"  })?.value ?? ""
            let h = video.fields.first(where: { $0.key == "Height" })?.value ?? ""
            if !w.isEmpty {
                statusChip(icon: "film.fill", text: "\(w)×\(h)", color: .brandBlue)
            }
            if let fps = video.fields.first(where: { $0.key == "FrameRate" })?.value {
                statusChip(icon: "speedometer", text: "\(fps) fps", color: .brandGreen)
            }
        }
        
        if !file.audioTracks.isEmpty {
            let n = file.audioTracks.count
            statusChip(
                icon: "waveform",
                text: "\(n) audio",
                color: .brandViolet
            )
        }
        
        if !file.textTracks.isEmpty {
            let n = file.textTracks.count
            statusChip(
                icon: "captions.bubble.fill",
                text: "\(n) sub\(n == 1 ? "" : "s")",
                color: .brandGreen
            )
        }
    }
    
    // MARK: - Status chip
    
    private func statusChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize()
        }
    }
    
    // MARK: - Missing dependencies warning
    
    private var missingDepsWarning: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                let names = missingDeps.map(\.name).joined(separator: ", ")
                Text("\(names) missing")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.red.opacity(0.85))
            )
            
            let system = missingDeps.filter { $0.brew == nil }
            if !system.isEmpty {
                let sysNames = system.map(\.name).joined(separator: ", ")
                Text("\(sysNames) should be in /usr/bin — reinstall macOS Command Line Tools.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            let brewable = missingDeps.filter { $0.brew != nil }
            if !brewable.isEmpty {
                Button(action: installMissingDeps) {
                    HStack(spacing: 5) {
                        if isInstalling {
                            ProgressView().scaleEffect(0.55)
                            Text("Installing \(installingTool)…")
                                .font(.system(size: 11, weight: .medium))
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(LinearGradient.brandBlueViolet)
                            let installNames = brewable.map(\.name).joined(separator: " + ")
                            Text("Install \(installNames) via Homebrew")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandViolet)
                .disabled(isInstalling)
            }
            
            if !system.isEmpty {
                Button(action: installXcodeSelect) {
                    HStack(spacing: 5) {
                        Image(systemName: "terminal")
                        Text("Install CLI Tools")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandBlue)
                .disabled(isInstalling)
            }
        }
        .padding(.horizontal, 14)
    }
    
    // MARK: - Install missing Homebrew deps
    
    private func installMissingDeps() {
        let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        guard let brewPath = brewPaths.first(where: {
            FileManager.default.fileExists(atPath: $0)
        }) else {
            if let url = URL(string: "https://brew.sh") { NSWorkspace.shared.open(url) }
            let a = NSAlert()
            a.messageText = "Homebrew Not Installed"
            a.informativeText = "Install Homebrew first (https://brew.sh), then try again."
            a.runModal()
            return
        }
        
        let toInstall = missingDeps.compactMap(\.brew)
        guard !toInstall.isEmpty else { return }
        
        isInstalling = true
        installingTool = toInstall.joined(separator: ", ")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var allSucceeded = true
            
            for pkg in toInstall {
                DispatchQueue.main.async { installingTool = pkg }
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: brewPath)
                process.arguments = ["install", pkg]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError  = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus != 0 { allSucceeded = false }
                } catch { allSucceeded = false }
            }
            
            DispatchQueue.main.async {
                isInstalling = false
                installingTool = ""
                let a = NSAlert()
                if allSucceeded {
                    a.messageText = "Dependencies Installed"
                    a.informativeText = "All missing tools were installed successfully."
                } else {
                    a.messageText = "Installation Issue"
                    a.informativeText = "Some tools may not have installed correctly. Try running manually:\n\(brewPath) install \(toInstall.joined(separator: " "))"
                }
                a.runModal()
            }
        }
    }
    
    // MARK: - Install Xcode Command Line Tools
    
    private func installXcodeSelect() {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
            process.arguments = ["--install"]
            process.standardOutput = Pipe()
            process.standardError  = Pipe()
            try? process.run()
            process.waitUntilExit()
        }
    }
}
