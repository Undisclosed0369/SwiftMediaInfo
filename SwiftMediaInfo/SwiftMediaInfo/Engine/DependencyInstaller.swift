//
//  DependencyInstaller.swift
//  SwiftMediaInfo
//
//  Installs command-line tools with Homebrew: mediainfo (required) and
//  ffmpeg (optional, for the preview). The one installer in the app — the
//  status bar, Settings › Tools and the preview window all use `shared`, so
//  either window shows an install the other started.
//
//  When Homebrew itself is missing, it says so and opens brew.sh
//  (ProjectLinks.homebrew).
//
//  Deliberately not a progress bar. Homebrew emits no parseable percentage, so
//  any bar drawn here would be a fiction — and a fake progress bar is worse
//  than an honest spinner, because it invites the user to predict a finish time
//  that nothing is actually measuring.
//

import Foundation
import AppKit
import SwiftUI
internal import Combine

@MainActor
final class DependencyInstaller: ObservableObject {
    
    /// The one installer in the app. The "one install at a time" guard is per
    /// instance, so a second instance would let two `brew` processes fight
    /// over the same lock.
    static let shared = DependencyInstaller()
    
    private init() {}
    
    enum State: Equatable {
        case idle
        case installing(package: String)
        case succeeded(package: String)
        case failed(reason: String)
    }
    
    @Published private(set) var state: State = .idle
    
    /// The last package an install was attempted for, so Retry knows what to
    /// try again without the caller having to remember.
    @Published private(set) var lastPackage: String? = nil
    
    var isInstalling: Bool {
        if case .installing = state { return true }
        return false
    }
    
    /// True while a finished install still has something to say — a success
    /// worth confirming or a failure worth explaining.
    var hasOutcome: Bool {
        switch state {
        case .succeeded, .failed: return true
        case .idle, .installing:  return false
        }
    }
    
    private static let brewPaths = [
        "/opt/homebrew/bin/brew",   // Apple silicon
        "/usr/local/bin/brew"       // Intel
    ]
    
    static var brewPath: String? {
        brewPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    
    static var isHomebrewInstalled: Bool { brewPath != nil }
    
    /// Installs a Homebrew formula.
    ///
    /// A single install runs at a time. Without that guard, an impatient second
    /// click starts a second `brew` against the same lock and both fail in ways
    /// that are hard to explain afterwards.
    func install(_ package: String, onCompletion: (() -> Void)? = nil) {
        guard !isInstalling else { return }
        
        lastPackage = package
        
        guard let brew = Self.brewPath else {
            state = .failed(reason: "Homebrew isn’t installed. Install it from brew.sh, then try again.")
            ProjectLinks.open(ProjectLinks.homebrew)
            return
        }
        
        state = .installing(package: package)
        
        Task {
            let result = await Self.runBrew(brew, arguments: ["install", package])
            
            await MainActor.run {
                switch result {
                case .success:
                    // The binary location is cached, so it has to be forgotten
                    // or the app keeps reporting the tool as missing until
                    // relaunch.
                    MediaEngine.refreshBinaryLocation()
                    self.state = .succeeded(package: package)
                    onCompletion?()
                    
                case .failure(let message):
                    self.state = .failed(reason: message)
                }
            }
        }
    }
    
    /// Try the same package again after a failure.
    ///
    /// The state is cleared first because `install` refuses to start while one
    /// is already running, and a stale `.failed` alongside a fresh
    /// `.installing` would make the UI show both at once.
    func retry(onCompletion: (() -> Void)? = nil) {
        guard !isInstalling, let package = lastPackage else { return }
        
        state = .idle
        install(package, onCompletion: onCompletion)
    }
    
    func reset() {
        guard !isInstalling else { return }
        state = .idle
    }
    
    // MARK: - Process
    
    private enum RunResult {
        case success
        case failure(String)
    }
    
    private static func runBrew(_ brew: String, arguments: [String]) async -> RunResult {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let outPipe = Pipe()
            let errPipe = Pipe()
            
            process.executableURL  = URL(fileURLWithPath: brew)
            process.arguments      = arguments
            process.standardOutput = outPipe
            process.standardError  = errPipe
            process.standardInput  = FileHandle.nullDevice
            
            do {
                try process.run()
            } catch {
                return .failure("Couldn’t start Homebrew: \(error.localizedDescription)")
            }
            
            // Both pipes drained before waiting, for the same reason documented
            // in MediaEngine: an undrained pipe deadlocks a chatty child, and
            // brew is very chatty.
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else {
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let detail = (stderr.isEmpty ? stdout : stderr)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                return .failure(
                    detail.isEmpty
                    ? "Homebrew exited with code \(process.terminationStatus)."
                    : String(detail.suffix(300))
                )
            }
            
            return .success
        }.value
    }
}
