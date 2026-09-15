//
//  MediaEngine.swift
//  SwiftMediaInfo
//
//  PHASE 1 — Engine foundation.
//
//  This file is the boundary between SwiftMediaInfo and the mediainfo CLI.
//  Everything below exists to make that boundary honest: when something goes
//  wrong, the app now knows *what* went wrong instead of receiving an empty
//  string and guessing.
//
//  What changed from the previous version:
//
//    • Typed errors (MediaInfoError) instead of returning "" for every failure.
//    • stderr is captured and read on its own thread, so it can never deadlock
//      and its contents are available for diagnostics.
//    • The process exit code is checked.
//    • Cancellation terminates the subprocess synchronously and safely, closing
//      the race where a process launched *after* cancellation was never killed.
//    • Timeout support with a configurable duration.
//    • The binary location is resolved once and cached (successful lookups only,
//      so installing mediainfo mid-session is still detected).
//    • Field ordering no longer depends on `hashValue`, which is randomised on
//      every launch and made Easy View field order change between runs.
//
//  What deliberately did NOT change:
//
//    • The three-parallel-subprocess design on file open.
//    • Read-stdout-before-waitUntilExit ordering (the large-file deadlock fix).
//    • The UTF-8 locale environment (the special-characters-in-filenames fix).
//    • Output formats, parsing results, and every visible behaviour.
//

import Foundation

// MARK: - Operation

/// Identifies which kind of mediainfo invocation an error came from.
/// Kept internal — used for diagnostics, never shown raw to the user.
nonisolated enum MediaInfoOperation: String, Sendable {
    case text
    case rawText
    case json
    case html
    case xml
    case version
    
    var displayName: String {
        switch self {
        case .text:    return "Text"
        case .rawText: return "Raw Text"
        case .json:    return "Metadata"
        case .html:    return "HTML"
        case .xml:     return "XML"
        case .version: return "Version check"
        }
    }
}

// MARK: - Error model

/// Strongly typed failure model for every mediainfo interaction.
///
/// `errorDescription` is what the user sees — it never contains a full local
/// path, and never contains raw stderr, because both can leak information the
/// user did not ask to expose.
///
/// `diagnosticDetail` is the internal version, used later by Settings →
/// Advanced. It is not surfaced in normal UI.
nonisolated enum MediaInfoError: LocalizedError, Equatable, Sendable {
    
    /// mediainfo is not installed anywhere we know to look.
    case executableNotFound
    
    /// We found a file at the expected location but it isn't runnable.
    case executableNotExecutable
    
    /// The process object refused to start at all.
    case processLaunchFailed(reason: String)
    
    /// mediainfo ran but exited with a non-zero status.
    case processFailed(exitCode: Int32, stderr: String)
    
    /// The file is gone, was moved, or lives on a volume that went away.
    case fileUnavailable
    
    /// The file exists but we are not permitted to read it.
    case permissionDenied
    
    /// mediainfo produced bytes that are not valid UTF-8.
    case invalidUTF8
    
    /// mediainfo exited cleanly but produced nothing.
    case emptyOutput
    
    /// The operation exceeded the configured time limit.
    case timeout(seconds: Int)
    
    /// The operation was cancelled (user opened another file, closed the window…).
    case cancelled
    
    /// Anything we could not classify.
    case unknown(reason: String)
    
    // MARK: User-facing text
    
    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "MediaInfo isn’t installed."
            
        case .executableNotExecutable:
            return "MediaInfo was found but can’t be run."
            
        case .processLaunchFailed:
            return "MediaInfo couldn’t be started."
            
        case .processFailed:
            return "MediaInfo couldn’t analyse this file."
            
        case .fileUnavailable:
            return "This file is no longer available."
            
        case .permissionDenied:
            return "SwiftMediaInfo doesn’t have permission to read this file."
            
        case .invalidUTF8:
            return "MediaInfo returned output that couldn’t be read."
            
        case .emptyOutput:
            return "MediaInfo returned no information for this file."
            
        case .timeout(let seconds):
            return "Analysis timed out after \(seconds) seconds."
            
        case .cancelled:
            return "Analysis was cancelled."
            
        case .unknown:
            return "Something went wrong while analysing this file."
        }
    }
    
    /// A short second line suggesting what the user can do next.
    var recoverySuggestion: String? {
        switch self {
        case .executableNotFound, .executableNotExecutable:
            return "Install it with Homebrew using the button in the status bar."
            
        case .fileUnavailable:
            return "It may have been moved, renamed, or its drive disconnected."
            
        case .permissionDenied:
            return "Grant access in System Settings › Privacy & Security › Files and Folders."
            
        case .processFailed:
            return "The file may be corrupt or in a format MediaInfo doesn’t recognise."
            
        case .emptyOutput:
            return "This may not be a media file."
            
        case .timeout:
            return "You can raise the time limit in Settings, or try again."
            
        case .processLaunchFailed, .invalidUTF8, .unknown:
            return "Try opening the file again."
            
        case .cancelled:
            return nil
        }
    }
    
    /// Whether offering the user a "Try Again" button makes sense.
    var isRetryable: Bool {
        switch self {
        case .cancelled, .executableNotFound, .executableNotExecutable:
            return false
        default:
            return true
        }
    }
    
    /// True for the one case that should never be rendered as an error at all.
    var isCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }
    
    // MARK: Internal diagnostics
    
    /// Detailed description for Settings → Advanced. Not shown in normal UI.
    var diagnosticDetail: String {
        switch self {
        case .executableNotFound:
            return "executableNotFound"
            
        case .executableNotExecutable:
            return "executableNotExecutable"
            
        case .processLaunchFailed(let reason):
            return "processLaunchFailed: \(reason)"
            
        case .processFailed(let code, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
            ? "processFailed: exit \(code)"
            : "processFailed: exit \(code) — \(trimmed.prefix(500))"
            
        case .fileUnavailable:
            return "fileUnavailable"
            
        case .permissionDenied:
            return "permissionDenied"
            
        case .invalidUTF8:
            return "invalidUTF8"
            
        case .emptyOutput:
            return "emptyOutput"
            
        case .timeout(let seconds):
            return "timeout: \(seconds)s"
            
        case .cancelled:
            return "cancelled"
            
        case .unknown(let reason):
            return "unknown: \(reason)"
        }
    }
}

// MARK: - Engine

/// `nonisolated` is required, not cosmetic.
///
/// This target builds with Default Actor Isolation set to `MainActor`, so every
/// unannotated type is inferred `@MainActor`. MediaEngine must run off the main
/// actor — it blocks on subprocess pipes — and its cancellation and timeout
/// handlers are called from nonisolated contexts. Marking the whole type
/// `nonisolated` opts it out of that inference in one place.
nonisolated enum MediaEngine {
    
    // MARK: - Timeout
    
    /// Default analysis time limit, in seconds.
    ///
    /// Chosen so it can never fire on a legitimate large-file analysis. An 89 GB
    /// 4K remux on a fast external SSD completes in seconds; the slowest observed
    /// real-world case is around 40 seconds. 120 gives a 3× margin over that.
    static let defaultTimeout: TimeInterval = 120
    
    /// Hard ceiling for the user-configurable timeout (1 hour).
    static let maximumTimeout: TimeInterval = 3600
    
    /// Short timeout used for cheap metadata-free calls such as `--Version`.
    static let versionTimeout: TimeInterval = 10
    
    // MARK: - Binary location
    
    private static let binaryLock = NSLock()
    
    // Protected by binaryLock on every access, so the compiler's concurrency
    // check is opted out of explicitly rather than left as a warning.
    nonisolated(unsafe) private static var cachedBinaryPath: String?
    
    /// Locations mediainfo is commonly installed to, in preference order.
    private static let candidatePaths = [
        "/opt/homebrew/bin/mediainfo",   // Homebrew – Apple Silicon
        "/usr/local/bin/mediainfo",      // Homebrew – Intel
        "/opt/local/bin/mediainfo",      // MacPorts
        "/usr/bin/mediainfo",            // system
    ]
    
    /// Resolved absolute path to the mediainfo binary, or nil if it isn't installed.
    ///
    /// Successful lookups are cached, because this used to be recomputed on every
    /// SwiftUI render. Failures are deliberately *not* cached, so that installing
    /// mediainfo while the app is running is picked up without a relaunch.
    static func resolveBinaryPath() -> String? {
        binaryLock.lock()
        
        if let cached = cachedBinaryPath {
            binaryLock.unlock()
            return cached
        }
        
        // A very recent failure is trusted for a moment. See the note on
        // negativeLookupWindow.
        if let expiry = negativeLookupExpiry, expiry > Date() {
            binaryLock.unlock()
            return nil
        }
        
        binaryLock.unlock()
        
        let found = searchForBinary()
        
        binaryLock.lock()
        if let found {
            cachedBinaryPath = found
            negativeLookupExpiry = nil
        } else {
            negativeLookupExpiry = Date().addingTimeInterval(negativeLookupWindow)
        }
        binaryLock.unlock()
        
        return found
    }
    
    /// How long a failed lookup is trusted before searching again.
    ///
    /// PHASE 9. Failures are still not cached permanently — installing
    /// mediainfo while the app is running must be picked up without a
    /// relaunch, and that is why the status bar re-checks on every render.
    /// But a failed lookup is the expensive one: it tries four fixed paths and
    /// then walks every directory in PATH, and it does all of that again on
    /// the next render, and the next.
    ///
    /// Three quarters of a second bounds that cost no matter how often the
    /// view redraws, while staying far below the point where a person would
    /// notice a delay. An install performed inside the app clears it outright
    /// via refreshBinaryLocation, so the only thing this ever defers is
    /// noticing an install someone did in Terminal — by at most one blink.
    private static let negativeLookupWindow: TimeInterval = 0.75
    
    nonisolated(unsafe) private static var negativeLookupExpiry: Date?
    
    /// Forget the cached location. Call after a Homebrew install, or from the
    /// "Re-detect" control in Settings.
    static func refreshBinaryLocation() {
        binaryLock.lock()
        cachedBinaryPath = nil
        negativeLookupExpiry = nil
        binaryLock.unlock()
    }
    
    private static func searchForBinary() -> String? {
        let fm = FileManager.default
        
        for path in candidatePaths where fm.isExecutableFile(atPath: path) {
            return path
        }
        
        // Fall back to scanning PATH ourselves. This replaces the old
        // "/usr/bin/env mediainfo" trick — resolving the path directly means we
        // always launch a known absolute executable rather than delegating the
        // lookup to another process.
        let rawPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in rawPath.split(separator: ":") {
            let candidate = String(directory) + "/mediainfo"
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        
        return nil
    }
    
    /// Legacy accessor kept so existing call sites (StatusBar's dependency check)
    /// keep working unchanged. Returns the bare name when nothing was found,
    /// which those call sites already treat as "missing".
    static var binaryPath: String {
        resolveBinaryPath() ?? "mediainfo"
    }
    
    // MARK: - Format fetchers (throwing)
    
    static func fetchText(_ url: URL, timeout: TimeInterval = defaultTimeout) async throws -> String {
        try await run(url: url, arguments: ["--Output=TEXT"], operation: .text, timeout: timeout)
    }
    
    static func fetchRawText(_ url: URL, timeout: TimeInterval = defaultTimeout) async throws -> String {
        try await run(url: url, arguments: ["--Output=TEXT", "--Full"], operation: .rawText, timeout: timeout)
    }
    
    static func fetchJSON(_ url: URL, timeout: TimeInterval = defaultTimeout) async throws -> String {
        // --Full is essential: without it, mediainfo omits the _String variants
        // (like Duration_String3) that Easy View relies on for readable values.
        try await run(url: url, arguments: ["--Output=JSON", "--Full"], operation: .json, timeout: timeout)
    }
    
    static func fetchHTML(_ url: URL, timeout: TimeInterval = defaultTimeout) async throws -> String {
        try await run(url: url, arguments: ["--Output=HTML"], operation: .html, timeout: timeout)
    }
    
    static func fetchXML(_ url: URL, timeout: TimeInterval = defaultTimeout) async throws -> String {
        try await run(url: url, arguments: ["--Output=XML", "--Full"], operation: .xml, timeout: timeout)
    }
    
    // MARK: - Format fetchers (Result-returning)
    //
    // These exist so several formats can be loaded concurrently with `async let`
    // while each one keeps its own success/failure state. A single throwing
    // `await` of three concurrent calls would discard two of the three outcomes.
    
    static func fetchTextResult(_ url: URL, timeout: TimeInterval) async -> Result<String, MediaInfoError> {
        await capture { try await fetchText(url, timeout: timeout) }
    }
    
    static func fetchRawTextResult(_ url: URL, timeout: TimeInterval) async -> Result<String, MediaInfoError> {
        await capture { try await fetchRawText(url, timeout: timeout) }
    }
    
    static func fetchJSONResult(_ url: URL, timeout: TimeInterval) async -> Result<String, MediaInfoError> {
        await capture { try await fetchJSON(url, timeout: timeout) }
    }
    
    static func fetchHTMLResult(_ url: URL, timeout: TimeInterval) async -> Result<String, MediaInfoError> {
        await capture { try await fetchHTML(url, timeout: timeout) }
    }
    
    static func fetchXMLResult(_ url: URL, timeout: TimeInterval) async -> Result<String, MediaInfoError> {
        await capture { try await fetchXML(url, timeout: timeout) }
    }
    
    private static func capture(
        _ work: () async throws -> String
    ) async -> Result<String, MediaInfoError> {
        do {
            return .success(try await work())
        } catch let error as MediaInfoError {
            return .failure(error)
        } catch {
            return .failure(.unknown(reason: String(describing: error)))
        }
    }
    
    // MARK: - Version
    
    /// Installed mediainfo version string, e.g. "MediaInfoLib - v25.04".
    /// Returns nil when mediainfo isn't installed or the call fails.
    /// Used by Settings; safe to call at any time.
    static func fetchVersion() async -> String? {
        guard let binary = resolveBinaryPath() else { return nil }
        
        do {
            let output = try await execute(
                binary: binary,
                arguments: ["--Version"],
                operation: .version,
                timeout: versionTimeout
            )
            // THE FIRST LINE IS NOT THE VERSION
            //
            // `mediainfo --Version` prints two lines:
            //
            //     MediaInfo Command line,
            //     MediaInfoLib - v25.04
            //
            // Taking the first non-empty one therefore produced a settings row
            // headed "Version" whose value was the words "MediaInfo Command
            // line," — a row that answered a different question than the one
            // it asked.
            //
            // The line that matters is whichever one carries a version number,
            // so that is what is searched for rather than assumed by position.
            // Position is exactly the sort of thing that changes when the tool
            // is updated.
            let lines = output
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            
            let pattern = try? NSRegularExpression(pattern: "v?([0-9]+(?:\\.[0-9]+)+)")
            
            for line in lines {
                let range = NSRange(line.startIndex..., in: line)
                guard let match = pattern?.firstMatch(in: line, range: range),
                      let numbers = Range(match.range(at: 1), in: line) else { continue }
                return String(line[numbers])
            }
            
            // No version number anywhere. Better to show whatever it did say
            // than to claim nothing was installed.
            return lines.first
        } catch {
            return nil
        }
    }
    
    // MARK: - Run (with file pre-flight)
    
    /// Runs mediainfo against a file URL.
    ///
    /// Pre-flight checks run before the process is launched so that a deleted
    /// file, a disconnected volume, or a permissions problem is reported as
    /// itself rather than as a generic process failure.
    static func run(
        url: URL,
        arguments: [String],
        operation: MediaInfoOperation,
        timeout: TimeInterval
    ) async throws -> String {
        
        guard let binary = resolveBinaryPath() else {
            // Distinguish "not installed" from "installed but not runnable".
            let existsButNotExecutable = candidatePaths.contains {
                FileManager.default.fileExists(atPath: $0)
            }
            throw existsButNotExecutable
            ? MediaInfoError.executableNotExecutable
            : MediaInfoError.executableNotFound
        }
        
        // Always an absolute path. Because it begins with "/", mediainfo can
        // never mistake a filename for a command-line option, and no shell is
        // involved at any point.
        let path = url.standardizedFileURL.path(percentEncoded: false)
        
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            throw MediaInfoError.fileUnavailable
        }
        guard fm.isReadableFile(atPath: path) else {
            throw MediaInfoError.permissionDenied
        }
        
        return try await execute(
            binary: binary,
            arguments: arguments + [path],
            operation: operation,
            timeout: timeout
        )
    }
    
    // MARK: - Core executor
    
    private static func execute(
        binary: String,
        arguments: [String],
        operation: MediaInfoOperation,
        timeout: TimeInterval
    ) async throws -> String {
        
        let box = ProcessBox()
        
        // Fires once if the process outlives the time limit. Terminating the
        // process closes its pipes, which unblocks the readers below.
        let timeoutTask = Task.detached(priority: .utility) {
            let nanoseconds = UInt64(max(1, timeout) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            box.requestStop(.timedOut)
        }
        defer { timeoutTask.cancel() }
        
        let outcome: RunOutcome
        
        do {
            outcome = try await withTaskCancellationHandler {
                try await Task.detached(priority: .userInitiated) {
                    try spawn(binary: binary, arguments: arguments, box: box)
                }.value
            } onCancel: {
                // Synchronous, unlike the previous version which hopped to the
                // main actor first. That hop is what allowed a cancelled
                // analysis to leave mediainfo running in the background.
                box.requestStop(.cancelled)
            }
        } catch let error as MediaInfoError {
            throw error
        } catch {
            throw MediaInfoError.unknown(reason: String(describing: error))
        }
        
        // A stop request always wins over whatever exit status we observed,
        // because terminating the process is what produced that status.
        if let stop = box.stopReason {
            switch stop {
            case .cancelled: throw MediaInfoError.cancelled
            case .timedOut:  throw MediaInfoError.timeout(seconds: Int(timeout))
            }
        }
        
        if Task.isCancelled {
            throw MediaInfoError.cancelled
        }
        
        let stderrText = String(data: outcome.stderr, encoding: .utf8) ?? ""
        
        guard outcome.exitCode == 0 else {
            // mediainfo reports missing/unreadable input on stderr. Re-classify
            // those so the user gets a meaningful message rather than an exit code.
            let lowered = stderrText.lowercased()
            if lowered.contains("permission denied") {
                throw MediaInfoError.permissionDenied
            }
            if lowered.contains("no such file") || lowered.contains("cannot be opened") {
                throw MediaInfoError.fileUnavailable
            }
            throw MediaInfoError.processFailed(exitCode: outcome.exitCode, stderr: stderrText)
        }
        
        guard !outcome.stdout.isEmpty else {
            throw MediaInfoError.emptyOutput
        }
        
        guard let text = String(data: outcome.stdout, encoding: .utf8) else {
            throw MediaInfoError.invalidUTF8
        }
        
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MediaInfoError.emptyOutput
        }
        
        return text
    }
    
    // MARK: - Process spawning
    
    private struct RunOutcome: Sendable {
        let exitCode: Int32
        let stdout: Data
        let stderr: Data
    }
    
    /// Launches the process and drains both pipes concurrently.
    ///
    /// Deadlock safety: stdout and stderr are read on two separate queues, and
    /// both reads complete before `waitUntilExit()` is called. If either pipe
    /// were left undrained, a child writing more than the kernel buffer holds
    /// would block forever — which is exactly the large-file hang that was
    /// fixed for stdout previously. stderr now gets the same treatment instead
    /// of being routed to a pipe nobody ever read.
    private static func spawn(
        binary: String,
        arguments: [String],
        box: ProcessBox
    ) throws -> RunOutcome {
        
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        
        // Force UTF-8 so filenames containing ü, é, ñ … are handled correctly.
        // Without this the process inherits a possibly broken locale from the
        // GUI app context and fails to read those paths.
        var environment = ProcessInfo.processInfo.environment
        environment["LANG"]   = "en_US.UTF-8"
        environment["LC_ALL"] = "en_US.UTF-8"
        
        process.environment    = environment
        process.executableURL  = URL(fileURLWithPath: binary)
        process.arguments      = arguments
        process.standardOutput = outPipe
        process.standardError  = errPipe
        process.standardInput  = FileHandle.nullDevice
        
        // Register before launching. If a stop was already requested, we never
        // start the process at all — closing the window where a just-launched
        // process could escape cancellation entirely.
        guard box.attach(process) else {
            switch box.stopReason {
            case .timedOut: throw MediaInfoError.timeout(seconds: 0)
            default:        throw MediaInfoError.cancelled
            }
        }
        
        do {
            try process.run()
        } catch {
            box.markFinished()
            throw MediaInfoError.processLaunchFailed(
                reason: (error as NSError).localizedDescription
            )
        }
        
        let outBuffer = DataBuffer()
        let errBuffer = DataBuffer()
        let group = DispatchGroup()
        
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outBuffer.value = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errBuffer.value = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        
        group.wait()
        process.waitUntilExit()
        
        try? outPipe.fileHandleForReading.close()
        try? errPipe.fileHandleForReading.close()
        
        box.markFinished()
        
        return RunOutcome(
            exitCode: process.terminationStatus,
            stdout: outBuffer.value,
            stderr: errBuffer.value
        )
    }
    
    /// Plain mutable box so the two reader queues can hand data back without
    /// mutating a captured local variable.
    private final class DataBuffer: @unchecked Sendable {
        var value = Data()
    }
    
    // MARK: - Process lifecycle box
    
    private enum StopReason: Sendable {
        case cancelled
        case timedOut
    }
    
    /// Thread-safe holder linking the running `Process` to cancellation and
    /// timeout, with no window in which a stop request can be lost.
    private final class ProcessBox: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var finished = false
        private var _stopReason: StopReason?
        
        var stopReason: StopReason? {
            lock.lock()
            defer { lock.unlock() }
            return _stopReason
        }
        
        /// Returns false when a stop was already requested — in which case the
        /// caller must not launch the process.
        func attach(_ newProcess: Process) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard _stopReason == nil else { return false }
            process = newProcess
            return true
        }
        
        func requestStop(_ reason: StopReason) {
            lock.lock()
            if _stopReason == nil { _stopReason = reason }
            let target = finished ? nil : process
            lock.unlock()
            
            // terminate() on an already-exited process is harmless.
            target?.terminate()
        }
        
        func markFinished() {
            lock.lock()
            finished = true
            process = nil
            lock.unlock()
        }
    }
    
    // MARK: - Parser
    
    /// Converts mediainfo's JSON into the app's track model.
    ///
    /// Deliberately tolerant: every field mediainfo emits is preserved, including
    /// ones this app has never heard of. New MediaInfo releases can add fields
    /// freely without anything here needing to change.
    static func parseTracks(from jsonString: String) -> [MediaTrack] {
        guard let data = jsonString.data(using: .utf8) else { return [] }
        
        let parsed = try? JSONSerialization.jsonObject(with: data)
        
        guard
            let root       = parsed as? [String: Any],
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
                .sorted { lhs, rhs in
                    let lp = priorityOrder(lhs)
                    let rp = priorityOrder(rhs)
                    if lp != rp { return lp < rp }
                    // Stable tiebreak. The previous version fell back to
                    // `hashValue`, which macOS randomises per launch — so Easy
                    // View's field order silently changed between runs.
                    return lhs < rhs
                }
            
            var fields: [(key: String, value: String)] = []
            for key in sortedKeys {
                guard let raw = trackDict[key] else { continue }
                guard let stringValue = stringify(raw) else { continue }
                guard !stringValue.isEmpty else { continue }
                fields.append((key: key, value: stringValue))
            }
            
            result.append(MediaTrack(type: type, streamIndex: index, fields: fields))
        }
        
        return result
    }
    
    /// Flattens any JSON value mediainfo might emit into a display string.
    /// Returns nil for values that shouldn't be shown at all (null, empty
    /// containers), so the caller can skip them.
    private static func stringify(_ value: Any) -> String? {
        switch value {
        case is NSNull:
            return nil
            
        case let string as String:
            return string
            
        case let number as NSNumber:
            // Distinguish real booleans from 0/1 integers.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "Yes" : "No"
            }
            return number.stringValue
            
        case let array as [Any]:
            let parts = array.compactMap { stringify($0) }.filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
            
        case let dictionary as [String: Any]:
            // Nested objects are rare but do occur. Render them compactly rather
            // than dropping the information entirely.
            let parts = dictionary
                .sorted { $0.key < $1.key }
                .compactMap { key, nested -> String? in
                    guard let rendered = stringify(nested), !rendered.isEmpty else { return nil }
                    return "\(key): \(rendered)"
                }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
            
        default:
            return String(describing: value)
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
    
    /// Index lookup built once rather than a linear scan per comparison.
    private static let priorityIndex: [String: Int] = {
        var map: [String: Int] = [:]
        for (offset, key) in knownPriority.enumerated() { map[key] = offset }
        return map
    }()
    
    private static func priorityOrder(_ key: String) -> Int {
        priorityIndex[key] ?? knownPriority.count
    }
}
