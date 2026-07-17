//
//  MediaEngine.swift
//  SwiftMediaInfo
//

import Foundation

final class MediaEngine {
    
    // MARK: - Binary path
    //
    // Searches common install locations for the mediainfo CLI binary.
    // Covers Homebrew (Apple Silicon + Intel), MacPorts, system paths, and
    // a fallback that lets the shell resolve it via PATH.
    
    static var binaryPath: String {
        let candidates = [
            "/opt/homebrew/bin/mediainfo",   // Homebrew – Apple Silicon
            "/usr/local/bin/mediainfo",      // Homebrew – Intel
            "/opt/local/bin/mediainfo",      // MacPorts
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        // Last resort: hope it's on PATH (won't work for GUI apps without a
        // login shell, but better than hard-failing with a cryptic error)
        return "mediainfo"
    }
    
    // MARK: - Individual format fetchers
    
    static func fetchText(_ url: URL) async -> String {
        await run(path: url.filePath, args: ["--Output=TEXT"])
    }
    
    static func fetchRawText(_ url: URL) async -> String {
        await run(path: url.filePath, args: ["--Output=TEXT", "--Full"])
    }
    
    static func fetchJSON(_ url: URL) async -> String {
        // --Full is essential: without it, mediainfo omits the _String variants
        // (like Duration_String3) that Easy View relies on for human-readable values.
        await run(path: url.filePath, args: ["--Output=JSON", "--Full"])
    }
    
    static func fetchHTML(_ url: URL) async -> String {
        await run(path: url.filePath, args: ["--Output=HTML"])
    }
    
    static func fetchXML(_ url: URL) async -> String {
        await run(path: url.filePath, args: ["--Output=XML", "--Full"])
    }
    
    // MARK: - Parser
    
    static func parseTracks(from jsonString: String) -> [MediaTrack] {
        guard
            let data       = jsonString.data(using: .utf8),
            let root       = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let media      = root["media"] as? [String: Any],
            let trackArray = media["track"] as? [[String: Any]]
        else { return [] }
        
        var typeCounters: [String: Int] = [:]
        var result: [MediaTrack] = []
        
        for trackDict in trackArray {
            let type  = (trackDict["@type"] as? String) ?? "Unknown"
            let index = typeCounters[type] ?? 0
            typeCounters[type] = index + 1
            
            let sortedKeys = trackDict.keys
                .filter { !$0.hasPrefix("@") }
                .sorted { priorityOrder($0) < priorityOrder($1) }
            
            var fields: [(key: String, value: String)] = []
            for key in sortedKeys {
                if let val = trackDict[key] {
                    let strVal: String
                    if let s = val as? String        { strVal = s }
                    else if let n = val as? NSNumber { strVal = n.stringValue }
                    else                             { strVal = "\(val)" }
                    if !strVal.isEmpty { fields.append((key: key, value: strVal)) }
                }
            }
            result.append(MediaTrack(type: type, streamIndex: index, fields: fields))
        }
        return result
    }
    
    // MARK: - Process runner
    //
    // FIX: Special characters in filenames (ü, é, ñ, etc.) were causing failures.
    // Two changes make this robust:
    //
    // 1. We set LANG and LC_ALL to "en_US.UTF-8" in the process environment so
    //    the mediainfo binary treats all input/output as UTF-8. Without this,
    //    the process inherits a potentially broken locale from the GUI app context
    //    and can't read filenames with non-ASCII characters.
    //
    // 2. We pass the URL itself to the process as a file-descriptor-backed argument
    //    rather than a plain string path. Actually — the cleanest fix is to use the
    //    URL's absoluteURL.path which SwiftUI/AppKit has already resolved and
    //    percent-decoded correctly, and pair that with the explicit UTF-8 environment.
    //
    // Reads ALL output FIRST (draining the pipe so mediainfo never deadlocks on
    // a full kernel buffer), then waits for the process to exit.
    
    static func run(path: String, args: [String]) async -> String {
        // Hold process reference outside so onCancel can terminate it.
        let holder = ProcessHolder()
        
        return await withTaskCancellationHandler {
            await Task.detached(priority: .userInitiated) {
                let process = Process()
                let pipe    = Pipe()
                
                await holder.set(process)
                
                // FIX: Inherit the current environment and force UTF-8 locale.
                // This is what makes filenames with special characters (ü, é, ñ …)
                // work correctly — without it the process can't decode the path.
                var env = ProcessInfo.processInfo.environment
                env["LANG"]   = "en_US.UTF-8"
                env["LC_ALL"] = "en_US.UTF-8"
                process.environment = env
                
                // Use /usr/bin/env so the shell PATH is consulted when binaryPath
                // falls back to a bare "mediainfo" name.
                let binary = await binaryPath
                if binary == "mediainfo" {
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.arguments     = ["mediainfo"] + args + [path]
                } else {
                    process.executableURL = URL(fileURLWithPath: binary)
                    process.arguments     = args + [path]
                }
                process.standardOutput = pipe
                process.standardError  = Pipe()   // discard stderr
                
                guard (try? process.run()) != nil else { return "" }
                
                // READ FIRST — drains the pipe; child process can finish writing.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                
                await holder.set(nil)
                
                guard !Task.isCancelled else { return "" }
                return String(data: data, encoding: .utf8) ?? ""
            }.value
        } onCancel: {
            // Kill the mediainfo subprocess immediately so cancelled analyses
            // don't keep burning CPU in the background.
            Task { @MainActor in
                holder.terminateIfRunning()
            }
        }
    }
    
    /// Thread-safe holder so `onCancel` can reach the running `Process`.
    private final class ProcessHolder: @unchecked Sendable {
        private let lock = NSLock()
        private var _process: Process?
        
        func set(_ p: Process?) {
            lock.lock()
            _process = p
            lock.unlock()
        }
        
        func terminateIfRunning() {
            lock.lock()
            let p = _process
            lock.unlock()
            p?.terminate()
        }
    }
    
    // MARK: - Field ordering
    
    private static let knownPriority: [String] = [
        "Format", "Format_Profile", "Format_Version", "Format_Commercial_IfAny",
        "Duration", "Duration/String", "FileSize", "OverallBitRate",
        "Width", "Height", "DisplayAspectRatio", "FrameRate",
        "BitRate", "BitRate_Mode", "Channels", "SamplingRate",
        "ColorSpace", "ChromaSubsampling", "BitDepth", "ScanType",
        "Encoded_Date", "Tagged_Date", "Writing_Application", "Writing_Library"
    ]
    
    private static func priorityOrder(_ key: String) -> Int {
        knownPriority.firstIndex(of: key) ?? (knownPriority.count + key.hashValue)
    }
}

// MARK: - URL helper

private extension URL {
    /// Returns the file-system path suitable for passing as a process argument.
    var filePath: String {
        self.path(percentEncoded: false)
    }
}
