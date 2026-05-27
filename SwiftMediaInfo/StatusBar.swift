//
//  StatusBar.swift
//  SwiftMediaInfo
//

import SwiftUI
import AppKit

struct StatusBar: View {
    
    @EnvironmentObject var store: MediaStore
    
    @State private var isInstalling = false
    
    // MARK: - Check mediainfo
    
    private var isMediaInfoMissing: Bool {
        let path = MediaEngine.binaryPath
        
        if path.hasPrefix("/") {
            return !FileManager.default.fileExists(atPath: path)
        }
        
        return true
    }
    
    // MARK: - UI
    
    var body: some View {
        
        HStack(spacing: 16) {
            
            if isMediaInfoMissing {
                
                missingMediaInfoWarning
                
            } else if let file = store.currentFile {
                
                if file.isLoading {
                    
                    statusItem(icon: "doc", text: file.fileName)
                    statusItem(icon: "internaldrive", text: file.fileSizeString)
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                        
                        Text("Analysing…")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                } else {
                    
                    if let general = file.generalTrack {
                        
                        statusItem(
                            icon: "doc",
                            text: general.fields.first(where: {
                                $0.key == "Format"
                            })?.value ?? ""
                        )
                        
                        if let duration = general.fields.first(where: {
                            $0.key == "Duration/String"
                        })?.value {
                            statusItem(icon: "clock", text: duration)
                        }
                        
                        if let bitrate = general.fields.first(where: {
                            $0.key == "OverallBitRate/String"
                        })?.value {
                            statusItem(icon: "waveform.path", text: bitrate)
                        }
                    }
                    
                    if let video = file.videoTracks.first {
                        
                        Divider()
                            .frame(height: 12)
                        
                        let width = video.fields.first(where: {
                            $0.key == "Width"
                        })?.value ?? ""
                        
                        let height = video.fields.first(where: {
                            $0.key == "Height"
                        })?.value ?? ""
                        
                        if !width.isEmpty {
                            statusItem(icon: "film", text: "\(width)×\(height)")
                        }
                        
                        if let fps = video.fields.first(where: {
                            $0.key == "FrameRate"
                        })?.value {
                            statusItem(icon: "speedometer", text: "\(fps) fps")
                        }
                    }
                    
                    if !file.audioTracks.isEmpty {
                        
                        Divider()
                            .frame(height: 12)
                        
                        statusItem(
                            icon: "waveform",
                            text: "\(file.audioTracks.count) audio stream\(file.audioTracks.count == 1 ? "" : "s")"
                        )
                    }
                    
                    if !file.textTracks.isEmpty {
                        statusItem(
                            icon: "captions.bubble",
                            text: "\(file.textTracks.count) subtitle\(file.textTracks.count == 1 ? "" : "s")"
                        )
                    }
                    
                    Spacer()
                    
                    statusItem(icon: "internaldrive", text: file.fileSizeString)
                }
                
            } else {
                
                Text("No file open")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Missing Warning
    
    private var missingMediaInfoWarning: some View {
        
        HStack(spacing: 10) {
            
            HStack(spacing: 5) {
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                
                Text("mediainfo not installed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.red.opacity(0.85))
            .cornerRadius(5)
            
            Text("SwiftMediaInfo requires MediaInfo CLI.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: installMediaInfo) {
                
                HStack(spacing: 5) {
                    
                    if isInstalling {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                    
                    Text(isInstalling ? "Installing…" : "Install via Homebrew")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isInstalling)
        }
    }
    
    // MARK: - REAL FIX
    
    private func installMediaInfo() {
        
        isInstalling = true
        
        let brewPaths = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]
        
        guard let brewPath = brewPaths.first(where: {
            FileManager.default.fileExists(atPath: $0)
        }) else {
            
            isInstalling = false
            
            if let url = URL(string: "https://brew.sh") {
                NSWorkspace.shared.open(url)
            }
            
            let alert = NSAlert()
            alert.messageText = "Homebrew Not Installed"
            alert.informativeText = """
            Install Homebrew first, then try again.
            """
            alert.runModal()
            
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            
            let process = Process()
            
            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments = ["install", "mediainfo"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                
                try process.run()
                process.waitUntilExit()
                
                DispatchQueue.main.async {
                    
                    isInstalling = false
                    
                    if process.terminationStatus == 0 {
                        
                        let alert = NSAlert()
                        alert.messageText = "MediaInfo Installed"
                        alert.informativeText = """
                        mediainfo was successfully installed.
                        
                        You can now use SwiftMediaInfo normally.
                        """
                        alert.runModal()
                        
                    } else {
                        
                        let alert = NSAlert()
                        alert.messageText = "Installation Failed"
                        alert.informativeText = """
                        Homebrew could not install mediainfo.
                        
                        Try running manually:
                        
                        \(brewPath) install mediainfo
                        """
                        alert.runModal()
                    }
                }
                
            } catch {
                
                DispatchQueue.main.async {
                    
                    isInstalling = false
                    
                    let alert = NSAlert()
                    alert.messageText = "Failed to Start Installation"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }
    
    // MARK: - Helper
    
    private func statusItem(icon: String, text: String) -> some View {
        
        HStack(spacing: 4) {
            
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}
