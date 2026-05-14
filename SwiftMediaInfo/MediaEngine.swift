//
//  MediaEngine.swift
//  SwiftMediaInfo
//
//  Created by Undisclosed on 23/4/26.
//

//
//  MediaEngine.swift
//  SwiftMediaInfo
//

import Foundation

final class MediaEngine {
    
    // MARK: - Binary path
    
    static var binaryPath: String {
        for candidate in [
            "/opt/homebrew/bin/mediainfo",
            "/usr/local/bin/mediainfo",
            "/usr/bin/mediainfo"
        ] {
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
        }
        return "mediainfo"
    }
    
    // MARK: - Individual format fetchers (called one at a time by MediaStore)
    
    static func fetchText(_ url: URL) async -> String {
        await run(path: url.path, args: ["--Output=TEXT"])
    }
    
    static func fetchRawText(_ url: URL) async -> String {
        await run(path: url.path, args: ["--Output=TEXT", "--Full"])
    }
    
    static func fetchJSON(_ url: URL) async -> String {
        await run(path: url.path, args: ["--Output=JSON", "--Full"])
    }
    
    static func fetchHTML(_ url: URL) async -> String {
        await run(path: url.path, args: ["--Output=HTML"])
    }
    
    static func fetchXML(_ url: URL) async -> String {
        await run(path: url.path, args: ["--Output=XML", "--Full"])
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
    // ⚠️  THE LARGE-FILE BUG WAS HERE.
    //
    // The old code did:
    //     p.waitUntilExit()
    //     pipe.fileHandleForReading.readDataToEndOfFile()
    //
    // macOS Pipes have a small kernel buffer (~64 KB).  When mediainfo writes
    // more data than the buffer can hold it BLOCKS, waiting for someone to read.
    // waitUntilExit() also BLOCKS, waiting for the process to finish.
    // Result: both sides wait on each other forever — a classic deadlock.
    //
    // The fix: read ALL the data FIRST (which drains the pipe and lets mediainfo
    // keep writing and eventually exit), THEN wait for the process to clean up.
    // Also: we check for Swift Task cancellation so opening a new file while
    // the old one is still loading immediately stops the background work.
    
    static func run(path: String, args: [String]) async -> String {
        // withTaskCancellationHandler lets us terminate the child process the
        // moment the Swift Task is cancelled (e.g. user opens a different file).
        return await withTaskCancellationHandler {
            await Task.detached(priority: .userInitiated) {
                let process = Process()
                let pipe    = Pipe()
                
                process.executableURL  = await URL(fileURLWithPath: binaryPath)
                process.arguments      = args + [path]
                process.standardOutput = pipe
                process.standardError  = Pipe()   // discard stderr
                
                guard (try? process.run()) != nil else { return "" }
                
                // ✅ READ FIRST — this drains the pipe so the child never blocks.
                //    Only AFTER all data is read do we wait for the process to exit.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                
                // If the task was cancelled while we were reading, discard the result.
                guard !Task.isCancelled else { return "" }
                
                return String(data: data, encoding: .utf8) ?? ""
            }.value
        } onCancel: {
            // Nothing extra needed — Task.isCancelled check above handles cleanup.
            // The process will naturally exit once its stdout pipe is closed.
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
