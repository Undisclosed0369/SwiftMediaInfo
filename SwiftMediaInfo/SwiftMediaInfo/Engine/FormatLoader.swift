//
//  FormatLoader.swift
//  SwiftMediaInfo
//
//  One mediainfo process at a time per open file, starting with the view
//  you are looking at (Easy, Text, Raw Text, HTML, XML, JSON).
//
//  WHY
//
//  Several mediainfo processes reading the same large file compete for the
//  same disk and cores, so the view on screen waits for work it didn't ask
//  for. On a 50 GB Matroska with forty subtitle tracks that wait was the
//  whole experience of opening a file.
//
//  HOW
//
//  Each open file gets one loader (owned by MediaStore, keyed by the file's
//  session id), and the loader runs one process at a time:
//
//    1. The format behind the current view goes first, alone, so it arrives
//       as fast as the machine allows.
//    2. Everything else follows in the background, one after another — JSON
//       first if it is not already loaded, because tracks drive Compare's
//       diff, search, CSV and the status bar.
//    3. Switching to a view that has not loaded yet moves its format to the
//       front. If a background fetch is in flight for a format nobody is
//       looking at, it is stopped and put back in the queue.
//    4. A file in a background tab is paused while another file needs the
//       machine; export and share can wait on a format (`wait(for:)`), which is
//       then never pre-empted.
//
//  WHAT IT DOES NOT DO
//
//  It does not touch MediaFile. Results are handed back to the store, which
//  checks the session id and applies them — the same rule every other result
//  in the app follows, so a loader that outlives its file can never write into
//  whichever file replaced it.
//

import Foundation

// MARK: - Format

/// One of the five things mediainfo can be asked for.
///
/// Distinct from `ViewMode` because two views share one: Easy View and JSON
/// are both drawn from the JSON output.
enum MediaFormat: String, CaseIterable {
    case json, text, rawText, html, xml

    /// The order the background pass works through whatever the current view
    /// does not need. JSON leads because parsed tracks feed the most features;
    /// HTML and XML trail because they are the least visited.
    static let backgroundOrder: [MediaFormat] = [.json, .text, .rawText, .html, .xml]

    nonisolated fileprivate static func fetch(
        _ format: MediaFormat,
        url: URL,
        timeout: TimeInterval
    ) async -> Result<String, MediaInfoError> {
        switch format {
        case .json:    return await MediaEngine.fetchJSONResult(url, timeout: timeout)
        case .text:    return await MediaEngine.fetchTextResult(url, timeout: timeout)
        case .rawText: return await MediaEngine.fetchRawTextResult(url, timeout: timeout)
        case .html:    return await MediaEngine.fetchHTMLResult(url, timeout: timeout)
        case .xml:     return await MediaEngine.fetchXMLResult(url, timeout: timeout)
        }
    }
}

// MARK: - Loader

final class FormatLoader {

    typealias Delivery = (
        _ format: MediaFormat,
        _ result: Result<String, MediaInfoError>,
        _ tracks: [MediaTrack]
    ) -> Void

    let url: URL
    let sessionID: UUID

    private let timeout: TimeInterval
    private let deliver: Delivery

    /// Formats still to fetch, in background order.
    private var queue: [MediaFormat]

    /// The one fetch in flight, if any.
    private var running: (format: MediaFormat, task: Task<Void, Never>)?

    /// The format behind the view on screen. Jumps the queue.
    private var preferred: MediaFormat?

    /// Callers waiting for a specific format — export and share, which need
    /// content that may still be on its way. A format someone is waiting for
    /// is never pre-empted.
    private var waiters: [MediaFormat: [CheckedContinuation<Void, Never>]] = [:]

    private var isCancelled = false

    /// Called once the queue is empty and nothing is running.
    var onIdle: (() -> Void)?

    /// Whether there is anything left to do.
    var hasWork: Bool { running != nil || !queue.isEmpty }

    /// Held while the file is in a background tab and another file has the
    /// machine. Pausing stops a running fetch and requeues it — unless
    /// something is waiting on it — so the file you switch to gets the disk to
    /// itself.
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }

            if isPaused {
                if let running, waiters[running.format] == nil {
                    running.task.cancel()
                    self.running = nil
                    queue.insert(running.format, at: 0)
                }
            } else {
                pump()
            }
        }
    }

    init(
        url: URL,
        sessionID: UUID,
        timeout: TimeInterval,
        formats: [MediaFormat],
        preferred: MediaFormat?,
        deliver: @escaping Delivery
    ) {
        self.url       = url
        self.sessionID = sessionID
        self.timeout   = timeout
        self.preferred = preferred
        self.deliver   = deliver
        self.queue     = MediaFormat.backgroundOrder.filter(formats.contains)
    }

    // MARK: Control

    func start() {
        pump()
    }

    /// Whether a format is queued or in flight.
    func isScheduled(_ format: MediaFormat) -> Bool {
        running?.format == format || queue.contains(format)
    }

    /// Record which format comes next without disturbing a fetch in flight.
    /// Used for files in background tabs when the view changes.
    func setPreferred(_ format: MediaFormat) {
        preferred = format
    }

    /// Make a format the next one fetched — the user has switched to its view.
    ///
    /// When a fetch for some other format is running, and nobody is waiting on
    /// it, it is stopped and requeued. Throwing away part of a background fetch
    /// is a better trade than making someone stare at a spinner for a view
    /// they never opened.
    func prefer(_ format: MediaFormat) {
        preferred = format

        guard queue.contains(format) else { return }

        if let running, running.format != format, waiters[running.format] == nil {
            running.task.cancel()
            self.running = nil
            queue.insert(running.format, at: 0)
        }

        pump()
    }

    /// Add a format back after it failed or was never asked for, then fetch it
    /// next.
    func enqueue(_ format: MediaFormat) {
        guard !isCancelled, !isScheduled(format) else { return }
        queue.insert(format, at: 0)
        prefer(format)
    }

    /// Suspend until a format has either arrived or failed. Returns at once if
    /// it is not scheduled — there is nothing to wait for.
    func wait(for format: MediaFormat) async {
        guard !isCancelled, isScheduled(format) else { return }

        // Deliberately not `prefer`: an export waiting in the background must
        // not take priority away from the view on screen. A waited-for format
        // simply goes ahead of the rest of the background queue.
        await withCheckedContinuation { continuation in
            waiters[format, default: []].append(continuation)
        }
    }

    /// Stop everything. The running process is terminated by MediaEngine's
    /// own cancellation handling, which cancelling the task triggers.
    func cancel() {
        isCancelled = true
        running?.task.cancel()
        running = nil
        queue = []
        resumeAllWaiters()
    }

    // MARK: Scheduling

    private func nextFormat() -> MediaFormat? {
        if let preferred, queue.contains(preferred) { return preferred }
        if let waited = queue.first(where: { waiters[$0] != nil }) { return waited }
        return queue.first
    }

    private func pump() {
        guard !isCancelled, !isPaused, running == nil else { return }

        guard let next = nextFormat() else {
            onIdle?()
            return
        }

        queue.removeAll { $0 == next }

        let url = url
        let timeout = timeout

        let task = Task { [weak self] in
            let result = await MediaFormat.fetch(next, url: url, timeout: timeout)

            // Parsed off the main thread: a file with hundreds of tracks
            // produces megabytes of JSON.
            var tracks: [MediaTrack] = []
            if next == .json, let json = result.value {
                tracks = await Task.detached(priority: .userInitiated) {
                    MediaEngine.parseTracks(from: json)
                }.value
            }

            guard !Task.isCancelled else { return }

            self?.finish(next, result: result, tracks: tracks)
        }

        running = (next, task)
    }

    private func finish(
        _ format: MediaFormat,
        result: Result<String, MediaInfoError>,
        tracks: [MediaTrack]
    ) {
        guard !isCancelled, running?.format == format else { return }

        running = nil
        deliver(format, result, tracks)
        resume(format)

        // Some failures are about the file or the tool, not the format: every
        // remaining fetch would fail the same way, one timeout at a time.
        // Report them all at once instead of discovering it five times.
        if case .failure(let error) = result, error.failsEveryFormat {
            let remaining = queue
            queue = []

            for format in remaining {
                deliver(format, .failure(error), [])
                resume(format)
            }
        }

        // With the queue empty this reports idle.
        pump()
    }

    private func resume(_ format: MediaFormat) {
        waiters.removeValue(forKey: format)?.forEach { $0.resume() }
    }

    private func resumeAllWaiters() {
        let all = waiters
        waiters = [:]
        all.values.flatMap { $0 }.forEach { $0.resume() }
    }
}

// MARK: - Error classification

private extension MediaInfoError {
    /// True when the cause is outside any one format: mediainfo is missing or
    /// unrunnable, or the file itself cannot be reached. A timeout is not in
    /// this list — Text can time out on a file whose JSON is quick.
    var failsEveryFormat: Bool {
        switch self {
        case .executableNotFound, .executableNotExecutable,
             .processLaunchFailed, .fileUnavailable, .permissionDenied:
            return true
        default:
            return false
        }
    }
}
