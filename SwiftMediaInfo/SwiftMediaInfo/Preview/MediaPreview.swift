//
//  MediaPreview.swift
//  SwiftMediaInfo
//
//  The SwiftMediaInfo preview's engine, for files Quick Look can't open:
//  ffmpeg (run and stopped), what to preview (PreviewSource and its ffmpeg
//  arguments), the playback settings it remembers (PreviewPlayback), and
//  the session that cuts clips, loads the filmstrip and manages subtitles
//  (PreviewSession). The window is MediaPreviewView; the subtitles' details
//  are PreviewSubtitles.
//
//  macOS previews and plays only what AVFoundation can read, and AVFoundation
//  cannot read Matroska at all — so for most files this app sees (MKV
//  remuxes, plus AVI, WebM, TS and friends) Quick Look shows nothing but an
//  icon. This builds a preview from the file itself with ffmpeg:
//
//    • A short clip (20 seconds), cut from the original into a temporary MP4
//      that AVFoundation can play. The video is copied untouched when macOS
//      can decode it — H.264, and HEVC including HDR10 and Dolby Vision — so
//      cutting a clip from a 70 GB 4K remux takes under a second. Anything
//      else is converted with the Mac's hardware encoder. The main audio
//      track becomes stereo AAC, because DTS and TrueHD don't play on macOS.
//    • A filmstrip of keyframes across the whole file. Each keyframe is
//      copied out as a one-frame clip and decoded by AVFoundation, so HDR
//      frames come out with their colours mapped properly instead of the
//      washed-out grey a plain ffmpeg snapshot gives.
//
//  Seeking cuts a new clip at the chosen point. The file's text subtitles
//  are carried into each clip; picture subtitles are drawn for it
//  (PreviewSubtitles). Volume, mute, speed, zoom and subtitle choices are
//  remembered across clips, files and launches.
//
//  TEMPORARY FILES
//
//  Nothing is written next to the original. Everything lives in one private
//  folder, $TMPDIR/SwiftMediaInfo/Preview-<pid>-<uuid>: the playing clip
//  (each replaced clip is deleted), filmstrip frames and subtitle pictures
//  (deleted as soon as they're read). Closing the preview — or quitting —
//  stops any ffmpeg still running and deletes the folder at once
//  (`discardFiles`); a folder left by a crash is cleared at the next launch
//  (PreviewLeftovers).
//
//  ffmpeg is a separate install (Homebrew), like MediaInfo itself. Without
//  it the preview says so and offers to install it.
//

import AppKit
import AVFoundation
internal import Combine

// MARK: - ffmpeg

nonisolated enum FFmpeg {
    private static let candidates = [
        "/opt/homebrew/bin/ffmpeg",   // Homebrew – Apple silicon
        "/usr/local/bin/ffmpeg",      // Homebrew – Intel
        "/opt/local/bin/ffmpeg"       // MacPorts
    ]

    static var path: String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// ffprobe, installed beside ffmpeg.
    static var probePath: String? {
        guard let path else { return nil }
        let probe = (path as NSString).deletingLastPathComponent + "/ffprobe"
        return FileManager.default.isExecutableFile(atPath: probe) ? probe : nil
    }

    /// Runs ffmpeg with no shell, draining both pipes before waiting (the
    /// large-output deadlock MediaEngine documents). Returns the exit status.
    ///
    /// Cancelling the task that awaits it stops ffmpeg there and then, so a
    /// clip or filmstrip frame nobody wants any more isn't left being written
    /// — after the preview has closed, or into a folder already deleted.
    static func run(_ arguments: [String]) async -> Int32 {
        guard let path else { return -1 }
        return await execute(path, ["-nostdin", "-hide_banner", "-loglevel", "error", "-y"] + arguments).status
    }

    /// Runs ffprobe and returns what it printed, or nil if it failed.
    static func probe(_ arguments: [String]) async -> Data? {
        guard let probePath else { return nil }
        let result = await execute(probePath, ["-v", "error"] + arguments)
        return result.status == 0 ? result.output : nil
    }

    private static func execute(_ executable: String, _ arguments: [String]) async -> (status: Int32, output: Data) {
        let running = RunningProcess()
        return await withTaskCancellationHandler {
            await Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                process.standardInput = FileHandle.nullDevice
                guard running.launch(process) else { return (-1, Data()) }
                let output = out.fileHandleForReading.readDataToEndOfFile()
                _ = err.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return (process.terminationStatus, output)
            }.value
        } onCancel: {
            running.cancel()
        }
    }
}

/// A process that can be stopped from any thread, before or after it starts.
private nonisolated final class RunningProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var isCancelled = false

    /// Starts `process`, unless it has already been cancelled.
    func launch(_ process: Process) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !isCancelled, (try? process.run()) != nil else { return false }
        self.process = process
        return true
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        isCancelled = true
        if let process, process.isRunning { process.terminate() }
    }
}

// MARK: - What to preview

/// The facts a preview needs, read from the analysis already done.
nonisolated struct PreviewSource: Sendable {
    let url: URL
    let fileName: String
    let details: [String]
    /// Seconds.
    let duration: Double
    let hasVideo: Bool
    let hasAudio: Bool
    /// "AVC", "HEVC", "VC-1"… from MediaInfo.
    let videoFormat: String?
    /// Dolby Vision without an HDR10 base layer (profile 5) needs the "dvh1"
    /// tag to play with the right colours; everything else plays as HEVC.
    let needsDolbyVisionTag: Bool
    /// ffmpeg's index among the audio streams for the main audio track.
    let audioStreamIndex: Int
    /// "24000/1001" — needed when a raw video stream is re-wrapped, since a
    /// raw stream carries no timing of its own.
    let frameRate: String?
    /// Width over height of the picture as shown — the display aspect ratio,
    /// turned for a rotated video. Sizes the preview window to the picture.
    let aspectRatio: Double?

    @MainActor
    init(file: MediaFile) {
        let summary = MediaSummary(tracks: file.tracks, fileURL: file.url)
        url = file.url
        fileName = file.url.lastPathComponent
        details = summary.fileDetails

        let general = file.tracks.first { $0.type == "General" }
        duration = general?.seconds ?? file.tracks.first { $0.type == "Video" }?.seconds ?? 0

        hasVideo = summary.video != nil
        hasAudio = !summary.audio.isEmpty
        videoFormat = summary.video?.format

        let hdr = summary.video?.hdr ?? ""
        needsDolbyVisionTag = hdr.contains("Dolby Vision") && !hdr.contains("Compatible")

        let mainIndex = summary.audio.firstIndex(where: \.isDefault) ?? 0
        audioStreamIndex = summary.audio.isEmpty ? 0 : mainIndex
        
        let video = file.tracks.first { $0.type == "Video" }
        if let num = video?.value(for: "FrameRate_Num"), let den = video?.value(for: "FrameRate_Den") {
            frameRate = "\(num)/\(den)"
        } else {
            frameRate = video?.value(for: "FrameRate")
        }

        // The display aspect ratio already allows for non-square pixels; the
        // pixel dimensions are the fallback when it is missing.
        var aspect = video?.value(for: "DisplayAspectRatio").flatMap(Double.init)
        if aspect == nil, let width = video?.value(for: "Width").flatMap(Double.init),
           let height = video?.value(for: "Height").flatMap(Double.init), height > 0 {
            aspect = width / height
        }
        let rotation = video?.value(for: "Rotation").flatMap(Double.init) ?? 0
        if let ratio = aspect, ratio > 0, abs(rotation.truncatingRemainder(dividingBy: 180)) == 90 {
            aspect = 1 / ratio
        }
        aspectRatio = aspect.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
    }

    /// Whether the video can be copied into the clip as it is.
    var copiesVideo: Bool {
        videoFormat == "AVC" || videoFormat == "HEVC"
    }

    private var videoTag: String? {
        switch videoFormat {
        case "AVC":  return "avc1"
        case "HEVC": return needsDolbyVisionTag ? "dvh1" : "hvc1"
        default:     return nil
        }
    }

    // MARK: ffmpeg arguments

    /// `subtitles` are ffmpeg's indices of the text subtitle tracks to carry
    /// over, as the text tracks macOS's player shows.
    func clipArguments(start: Double, length: Double, output: URL, convertVideo: Bool, subtitles: [Int] = []) -> [String] {
        var args = ["-ss", Self.format(start), "-i", url.path(percentEncoded: false), "-t", Self.format(length)]
        if hasVideo { args += ["-map", "0:v:0"] }
        if hasAudio { args += ["-map", "0:a:\(audioStreamIndex)?"] }
        for index in subtitles { args += ["-map", "0:s:\(index)"] }

        if hasVideo {
            if copiesVideo && !convertVideo, let tag = videoTag {
                args += ["-c:v", "copy", "-tag:v", tag]
            } else {
                // Hardware H.264, at most 1080p — a preview, not a transcode.
                args += ["-c:v", "h264_videotoolbox", "-b:v", "12M",
                         "-vf", "scale='min(1920,iw)':-2,format=yuv420p", "-tag:v", "avc1"]
            }
        }
        if hasAudio {
            args += ["-c:a", "aac", "-ac", "2", "-b:a", "192k"]
        }
        args += Self.subtitleArguments(subtitles)
        args += ["-dn", "-movflags", "+faststart", output.path(percentEncoded: false)]
        return args
    }

    /// Text subtitles as MP4 text tracks, none of them marked default — which
    /// one shows is the preview's choice, made once the clip is ready. None
    /// at all when there are none to carry.
    private static func subtitleArguments(_ subtitles: [Int]) -> [String] {
        subtitles.isEmpty ? ["-sn"] : ["-c:s", "mov_text", "-disposition:s", "0"]
    }

    /// Step one of the re-wrap: the HEVC stream on its own, as a raw stream.
    ///
    /// Some MKVs (web releases especially) keep HEVC's parameter sets inside
    /// the stream instead of in the file header. Copied straight into an MP4
    /// they leave it without the header box macOS needs, and the clip won't
    /// play. Going through a raw stream makes ffmpeg rebuild that box from
    /// the parameter sets — still a copy, still well under a second.
    func rawVideoArguments(start: Double, length: Double, output: URL) -> [String] {
        ["-ss", Self.format(start), "-i", url.path(percentEncoded: false), "-t", Self.format(length),
         "-map", "0:v:0", "-c:v", "copy", "-bsf:v", "hevc_mp4toannexb", "-f", "hevc",
         output.path(percentEncoded: false)]
    }
    
    /// Step two: the raw stream wrapped as MP4, with the audio and the text
    /// subtitles added from the original.
    func rewrapArguments(rawVideo: URL, start: Double, length: Double, output: URL, subtitles: [Int] = []) -> [String] {
        var args: [String] = []
        if let frameRate { args += ["-r", frameRate] }
        args += ["-i", rawVideo.path(percentEncoded: false)]
        if hasAudio || !subtitles.isEmpty {
            args += ["-ss", Self.format(start), "-t", Self.format(length), "-i", url.path(percentEncoded: false)]
        }
        args += ["-map", "0:v:0"]
        if hasAudio {
            args += ["-map", "1:a:\(audioStreamIndex)?", "-c:a", "aac", "-ac", "2", "-b:a", "192k"]
        }
        for index in subtitles { args += ["-map", "1:s:\(index)"] }
        args += Self.subtitleArguments(subtitles)
        args += ["-c:v", "copy", "-tag:v", needsDolbyVisionTag ? "dvh1" : "hvc1",
                 "-movflags", "+faststart", output.path(percentEncoded: false)]
        return args
    }
    
    /// One keyframe, copied untouched, for AVFoundation to decode.
    func keyframeArguments(at time: Double, output: URL) -> [String] {
        var args = ["-ss", Self.format(time), "-i", url.path(percentEncoded: false),
                    "-map", "0:v:0", "-frames:v", "1"]
        if copiesVideo, let tag = videoTag {
            args += ["-c:v", "copy", "-tag:v", tag]
        } else {
            args += ["-c:v", "h264_videotoolbox", "-b:v", "8M",
                     "-vf", "scale='min(960,iw)':-2,format=yuv420p", "-tag:v", "avc1"]
        }
        args += ["-an", "-sn", "-dn", output.path(percentEncoded: false)]
        return args
    }

    /// Fallback snapshot when the keyframe can't be decoded by AVFoundation.
    func snapshotArguments(at time: Double, output: URL) -> [String] {
        ["-skip_frame", "nokey", "-ss", Self.format(time), "-i", url.path(percentEncoded: false),
         "-frames:v", "1", "-vf", "scale=480:-2", output.path(percentEncoded: false)]
    }

    private static func format(_ seconds: Double) -> String {
        String(format: "%.3f", max(0, seconds))
    }
}

// MARK: - Playback settings

/// How the preview plays: volume, mute, speed and zoom. Set once in the
/// player's controls and kept from clip to clip, from file to file and from
/// one launch to the next, as QuickTime Player keeps them.
@MainActor
enum PreviewPlayback {
    private static let volumeKey = "previewVolume"
    private static let mutedKey = "previewMuted"
    private static let speedKey = "previewSpeed"
    private static let gravityKey = "previewVideoGravity"

    private static var defaults: UserDefaults { .standard }

    /// Applies the saved settings to a new player, before it starts. An audio
    /// preview has no volume or speed controls of its own, so it gets only
    /// the volume — never a mute or a speed that couldn't be undone there.
    static func apply(to player: AVPlayer, hasControls: Bool) {
        if let volume = defaults.object(forKey: volumeKey) as? Float, (0...1).contains(volume) {
            player.volume = (!hasControls && volume == 0) ? 1 : volume
        }
        guard hasControls else { return }
        player.isMuted = defaults.bool(forKey: mutedKey)
        if let speed = defaults.object(forKey: speedKey) as? Float, speed > 0 {
            player.defaultRate = speed
        }
    }

    /// Keeps a player's settings for the next clip, file or launch.
    static func remember(_ player: AVPlayer, hasControls: Bool) {
        guard hasControls else { return }
        defaults.set(player.volume, forKey: volumeKey)
        defaults.set(player.isMuted, forKey: mutedKey)
        // Only a speed chosen in the speed menu; fast-forwarding changes the
        // rate, never this.
        if player.defaultRate > 0 { defaults.set(player.defaultRate, forKey: speedKey) }
    }

    // MARK: Subtitles
    //
    // Clips carry no subtitle tracks of their own. On macOS 27 the player
    // offers subtitles transcribed on the Mac from the clip's speech ("English
    // (US) Transcribed" in the subtitles menu); the choice made there is kept
    // like the others. Saved as "off", or as the option's language and
    // whether it is transcribed.

    private static let subtitlesKey = "previewSubtitles"

    /// Selects the saved subtitles in a new clip. Nothing is saved until a
    /// choice is made, so until then the player's own default stands.
    static func applySubtitles(to item: AVPlayerItem, in group: AVMediaSelectionGroup) {
        guard let saved = defaults.string(forKey: subtitlesKey) else { return }
        guard saved != "off" else {
            if group.allowsEmptySelection { item.select(nil, in: group) }
            return
        }
        let parts = saved.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return }
        let language = parts[0], transcribed = parts[1] == "transcribed"
        let sameKind = group.options.filter { $0.hasMediaCharacteristic(.machineGenerated) == transcribed }
        // The same language first; otherwise the same kind in the clip's own
        // language — subtitles left on stay on for a film in another language.
        if let option = sameKind.first(where: { ($0.extendedLanguageTag ?? "") == language }) ?? sameKind.first {
            item.select(option, in: group)
        }
    }

    static func rememberSubtitles(_ option: AVMediaSelectionOption?) {
        let value = option.map {
            "\($0.extendedLanguageTag ?? "")|\($0.hasMediaCharacteristic(.machineGenerated) ? "transcribed" : "track")"
        } ?? "off"
        defaults.set(value, forKey: subtitlesKey)
    }

    /// Fit or fill, from the zoom button in full screen.
    static var videoGravity: AVLayerVideoGravity {
        get {
            let saved = defaults.string(forKey: gravityKey).map(AVLayerVideoGravity.init(rawValue:))
            let known: [AVLayerVideoGravity] = [.resizeAspect, .resizeAspectFill, .resize]
            return saved.flatMap { known.contains($0) ? $0 : nil } ?? .resizeAspect
        }
        set { defaults.set(newValue.rawValue, forKey: gravityKey) }
    }

    // MARK: Restore Defaults

    /// Forgets all of it — volume, mute, speed, zoom, the clips' subtitles
    /// and each file's subtitle choice — so the next preview plays as on a
    /// new install. A preview open at the time is set back first (see
    /// `PreviewSession.restoreDefaultPlayback`).
    static func restoreDefaults() {
        MediaPreviewController.shared.restoreDefaultPlayback()
        for key in [volumeKey, mutedKey, speedKey, gravityKey, subtitlesKey] {
            defaults.removeObject(forKey: key)
        }
        PreviewSubtitleMemory.forgetAll()
    }
}

// MARK: - Session

@MainActor
final class PreviewSession: ObservableObject {

    struct Thumbnail: Identifiable {
        let id: Int
        let time: Double
        var image: NSImage?
    }

    nonisolated static let clipLength: Double = 20
    static let thumbnailCount = 12

    let source: PreviewSource

    @Published private(set) var player: AVPlayer?
    @Published private(set) var clipStart: Double = 0
    @Published private(set) var isCutting = false
    @Published private(set) var failure: String?
    @Published private(set) var thumbnails: [Thumbnail] = []
    @Published private(set) var ffmpegMissing = FFmpeg.path == nil

    /// The file's own subtitle tracks that can be shown, once read.
    @Published private(set) var subtitleTracks: [PreviewSubtitleTrack] = []
    /// What shows for subtitles: chosen in the window's Subtitles menu, or
    /// in the player's own menu.
    @Published private(set) var subtitleChoice: PreviewSubtitleChoice = .off
    /// Whether the clip playing offers macOS's transcription.
    @Published private(set) var offersTranscription = false
    /// The chosen picture-subtitle track's pictures, for the clip they were
    /// drawn for.
    @Published private(set) var pictureSubtitles: PictureSubtitles?
    /// The clip playing, numbered as cut.
    @Published private(set) var playingClip = 0

    private var workspace: SecureTemporaryDirectory?
    private var clipCounter = 0
    private var cutTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    private var pictureTask: Task<Void, Never>?
    private var previousClip: URL?
    /// Whether the text subtitles made it into the clip playing. They are
    /// left out of a clip if converting one of them failed.
    private var clipHasTextSubtitles = false
    /// The player's subtitle choices for the clip playing.
    private var legibleGroup: AVMediaSelectionGroup?
    private var isClosed = false

    init(source: PreviewSource) {
        self.source = source
    }

    var clipEnd: Double {
        min(source.duration > 0 ? source.duration : clipStart + Self.clipLength, clipStart + Self.clipLength)
    }

    /// The picture subtitles to draw over the clip playing, if any.
    var shownPictureSubtitles: PictureSubtitles? {
        pictureSubtitles?.clipID == playingClip ? pictureSubtitles : nil
    }

    private var textTracks: [PreviewSubtitleTrack] {
        subtitleTracks.filter { $0.kind == .text }
    }

    /// Starts the first clip a tenth of the way in — past studio logos and
    /// black leaders, where a preview says more about the file. The file's
    /// subtitles are read first, since the clip carries the text ones.
    func start() {
        guard !isClosed else { return }
        ffmpegMissing = FFmpeg.path == nil
        guard !ffmpegMissing else { return }
        if workspace == nil { workspace = try? SecureTemporaryDirectory(prefix: "Preview") }

        let opening = source.duration > Self.clipLength * 3 ? source.duration * 0.1 : 0
        if source.hasVideo { loadThumbnails(in: workspace) }
        guard source.hasVideo else {
            cut(at: opening)
            return
        }
        isCutting = true
        clipStart = opening
        let url = source.url
        cutTask = Task { [weak self] in
            let tracks = await PreviewSubtitleTrack.probe(url)
            guard !Task.isCancelled, let self else { return }
            self.subtitleTracks = tracks
            if !tracks.isEmpty {
                self.subtitleChoice = PreviewSubtitleMemory.initialChoice(for: url, tracks: tracks)
            }
            self.cut(at: opening)
        }
    }

    /// Cuts and plays a clip starting at `time`. A newer request replaces one
    /// still being cut.
    func cut(at time: Double) {
        guard let workspace, !isClosed else { return }
        let start = max(0, min(time, max(0, source.duration - Self.clipLength)))
        cutTask?.cancel()
        isCutting = true
        failure = nil
        clipStart = start

        clipCounter += 1
        let clipID = clipCounter
        let output = workspace.file(named: "clip-\(clipID).\(source.hasVideo ? "mp4" : "m4a")")
        let source = self.source
        let subtitles = textTracks.map(\.index)
        drawPictureSubtitles(for: clipID, start: start)

        cutTask = Task { [weak self] in
            var withSubtitles = !subtitles.isEmpty
            var playable = await Self.makeClip(source, start: start, output: output, subtitles: subtitles)
            if !playable, withSubtitles, !Task.isCancelled {
                // A subtitle that won't convert mustn't cost the preview.
                withSubtitles = false
                playable = await Self.makeClip(source, start: start, output: output, subtitles: [])
            }

            guard !Task.isCancelled, let self else {
                // Replaced by a newer clip, or the window closed: nothing of
                // it is kept.
                try? FileManager.default.removeItem(at: output)
                return
            }
            self.isCutting = false
            guard playable else {
                try? FileManager.default.removeItem(at: output)
                self.failure = "This part of the file couldn’t be turned into a preview."
                return
            }

            let old = self.previousClip
            self.previousClip = output
            // The next clip plays the way the last one was left.
            self.rememberPlayback()
            let player = AVPlayer(url: output)
            PreviewPlayback.apply(to: player, hasControls: source.hasVideo)
            // A file with subtitles of its own shows the preview's choice
            // (its default track, or the one last chosen) — not one the
            // player would otherwise pick by language as playback starts.
            if !self.subtitleTracks.isEmpty { player.appliesMediaSelectionCriteriaAutomatically = false }
            self.player?.pause()
            self.clipHasTextSubtitles = withSubtitles
            self.playingClip = clipID
            self.player = player
            self.watchPlayback(of: player)
            player.play()

            // The clip it replaces is deleted, so a long session of seeking
            // through a 4K remux never piles up gigabytes of clips.
            if let old { try? FileManager.default.removeItem(at: old) }
        }
    }

    /// Makes the clip the quickest way that plays: the video copied as it is;
    /// for HEVC that keeps its parameter sets in the stream, re-wrapped;
    /// failing both (an unusual profile, a damaged stream), converted.
    nonisolated private static func makeClip(_ source: PreviewSource, start: Double, output: URL,
                                             subtitles: [Int]) async -> Bool {
        var status = await FFmpeg.run(source.clipArguments(start: start, length: clipLength, output: output,
                                                           convertVideo: false, subtitles: subtitles))
        var playable = status == 0 ? await isPlayable(output) : false

        if !playable, source.hasVideo, source.videoFormat == "HEVC", !Task.isCancelled {
            let raw = output.deletingPathExtension().appendingPathExtension("hevc")
            if await FFmpeg.run(source.rawVideoArguments(start: start, length: clipLength, output: raw)) == 0 {
                status = await FFmpeg.run(source.rewrapArguments(rawVideo: raw, start: start, length: clipLength,
                                                                 output: output, subtitles: subtitles))
                playable = status == 0 ? await isPlayable(output) : false
            }
            try? FileManager.default.removeItem(at: raw)
        }

        if !playable, source.hasVideo, source.copiesVideo, !Task.isCancelled {
            status = await FFmpeg.run(source.clipArguments(start: start, length: clipLength, output: output,
                                                           convertVideo: true, subtitles: subtitles))
            playable = status == 0 ? await isPlayable(output) : false
        }
        return playable && !Task.isCancelled
    }

    static let skipLength: Double = 10

    /// Where playback is in the whole file, in seconds.
    var position: Double {
        let played = player.map { $0.currentTime().seconds } ?? 0
        return clipStart + (played.isFinite ? max(0, played) : 0)
    }

    /// ±10 s from where playback is. Inside the clip that is playing it is an
    /// ordinary seek, so it is instant; past either end a new clip is cut
    /// starting there.
    func skip(by seconds: Double) {
        let target = min(max(position + seconds, 0), max(0, source.duration))
        if let player, !isCutting, target >= clipStart, target < clipEnd - 0.5 {
            player.seek(to: CMTime(seconds: target - clipStart, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
            if player.timeControlStatus == .paused { player.play() }
            objectWillChange.send()
        } else {
            cut(at: target)
        }
    }

    private func loadThumbnails(in workspace: SecureTemporaryDirectory?) {
        guard let workspace, source.duration > 0 else { return }
        let count = Self.thumbnailCount
        let times = (0..<count).map { source.duration * (Double($0) + 0.5) / Double(count) }
        thumbnails = times.enumerated().map { Thumbnail(id: $0.offset, time: $0.element) }
        let source = self.source
        let frames = (0..<count).map { workspace.file(named: "frame-\($0).mp4") }
        let jpegs = (0..<count).map { workspace.file(named: "frame-\($0).jpg") }

        thumbnailTask = Task { [weak self] in
            // Four at a time: enough to keep a fast drive busy without
            // flooding a spinning disk with seeks.
            await withTaskGroup(of: (Int, NSImage?).self) { group in
                var next = 0
                func add() {
                    guard next < times.count else { return }
                    let index = next, time = times[index]
                    let frame = frames[index], jpeg = jpegs[index]
                    next += 1
                    group.addTask {
                        (index, await Self.thumbnail(source: source, time: time, frame: frame, jpeg: jpeg))
                    }
                }
                for _ in 0..<4 { add() }
                for await (index, image) in group {
                    await MainActor.run {
                        guard let self, self.thumbnails.indices.contains(index) else { return }
                        self.thumbnails[index].image = image
                    }
                    add()
                }
            }
        }
    }

    nonisolated private static func thumbnail(source: PreviewSource, time: Double, frame: URL, jpeg: URL) async -> NSImage? {
        defer { try? FileManager.default.removeItem(at: frame) }

        if await FFmpeg.run(source.keyframeArguments(at: time, output: frame)) == 0 {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: frame))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 480)
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity
            if let (image, _) = try? await generator.image(at: .zero) {
                return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            }
        }

        // AVFoundation couldn't decode it: let ffmpeg draw the frame.
        defer { try? FileManager.default.removeItem(at: jpeg) }
        guard await FFmpeg.run(source.snapshotArguments(at: time, output: jpeg)) == 0 else { return nil }
        return NSImage(contentsOf: jpeg)
    }

    nonisolated private static func isPlayable(_ url: URL) async -> Bool {
        (try? await AVURLAsset(url: url).load(.isPlayable)) ?? false
    }

    // MARK: ffmpeg install

    func installFFmpeg() {
        DependencyInstaller.shared.install("ffmpeg") { [weak self] in
            Task { @MainActor in self?.start() }
        }
    }

    // MARK: Playback settings

    /// Keeps the volume, mute and speed the player has now.
    func rememberPlayback() {
        if let player { PreviewPlayback.remember(player, hasControls: source.hasVideo) }
    }

    /// Restore Defaults while this preview is open: full volume, unmuted,
    /// normal speed, there and then — otherwise closing it, or its next
    /// clip, would save the old ones again. Zoom and subtitles stay as they
    /// are on screen; they are only saved when changed.
    func restoreDefaultPlayback() {
        guard let player, source.hasVideo else { return }
        player.isMuted = false
        player.volume = 1
        player.defaultRate = 1
        if player.rate > 0 { player.rate = 1 }
    }

    private var playbackObservers: [NSKeyValueObservation] = []

    /// Saves each change as it is made, so it is kept even if the app quits
    /// with the preview open.
    private func watchPlayback(of player: AVPlayer) {
        let hasControls = source.hasVideo
        let save: @Sendable (AVPlayer) -> Void = { player in
            Task { @MainActor in PreviewPlayback.remember(player, hasControls: hasControls) }
        }
        playbackObservers = [
            player.observe(\.volume) { player, _ in save(player) },
            player.observe(\.isMuted) { player, _ in save(player) },
            player.observe(\.defaultRate) { player, _ in save(player) },
        ]
        watchSubtitles(of: player)
    }

    // MARK: Subtitles

    private var subtitleObserver: NSObjectProtocol?

    /// Puts the subtitle choice into effect on a new clip once it is ready,
    /// then follows choices made in the player's own menu. Video only: an
    /// audio preview has no menu.
    private func watchSubtitles(of player: AVPlayer) {
        if let subtitleObserver { NotificationCenter.default.removeObserver(subtitleObserver) }
        subtitleObserver = nil
        legibleGroup = nil
        offersTranscription = false
        guard source.hasVideo, let item = player.currentItem else { return }
        Task { [weak self] in
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) else { return }
            // The player makes its own pick as the clip becomes ready to
            // play, replacing any made earlier — so the preview's goes in
            // after that.
            var waited = 0
            while item.status == .unknown, waited < 200 {
                try? await Task.sleep(for: .milliseconds(50))
                waited += 1
            }
            guard item.status == .readyToPlay, let self, self.player === player else { return }
            self.legibleGroup = group
            self.offersTranscription = group.options.contains { $0.hasMediaCharacteristic(.machineGenerated) }
            if self.subtitleTracks.isEmpty {
                // No subtitles of its own: macOS's transcription, on or off
                // as last chosen for any such file.
                PreviewPlayback.applySubtitles(to: item, in: group)
            } else {
                self.applySubtitleChoice()
            }
            // Watching starts only now, so the player's own first pick can't
            // overwrite the choice. The notification arrives on the main
            // queue, where the group is only ever read.
            nonisolated(unsafe) let legible = group
            self.subtitleObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.mediaSelectionDidChangeNotification, object: item, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.player === player else { return }
                    self.playerChoseSubtitles(item.currentMediaSelection.selectedMediaOption(in: legible))
                }
            }
        }
    }

    /// The text tracks in the clip playing, in the order of `textTracks` —
    /// or nil where they didn't make it into this clip. The player lists a
    /// forced-only version of each beside it, and its transcription; neither
    /// is one of the file's tracks.
    private var clipTextOptions: [AVMediaSelectionOption]? {
        guard clipHasTextSubtitles, let legibleGroup else { return nil }
        let options = legibleGroup.options.filter {
            !$0.hasMediaCharacteristic(.machineGenerated) && !$0.hasMediaCharacteristic(.containsOnlyForcedSubtitles)
        }
        return options.count == textTracks.count ? options : nil
    }

    /// The window's Subtitles menu.
    func chooseSubtitles(_ choice: PreviewSubtitleChoice) {
        guard choice != subtitleChoice else { return }
        subtitleChoice = choice
        PreviewSubtitleMemory.remember(choice, for: source.url)
        applySubtitleChoice()
        // A picture track is drawn for the clip playing — or, while one is
        // being cut, for that clip.
        drawPictureSubtitles(for: clipCounter, start: clipStart)
    }

    private func applySubtitleChoice() {
        guard let item = player?.currentItem, let group = legibleGroup else { return }
        switch subtitleChoice {
        case .off:
            item.select(nil, in: group)
        case .transcribed:
            item.select(group.options.first { $0.hasMediaCharacteristic(.machineGenerated) }, in: group)
        case .track(let index):
            // A text track is the player's to show; a picture track is drawn
            // over the video, with the player's own subtitles off.
            if let position = textTracks.firstIndex(where: { $0.index == index }), let options = clipTextOptions {
                item.select(options[position], in: group)
            } else {
                item.select(nil, in: group)
            }
        }
    }

    /// A choice made in the player's own subtitles menu.
    private func playerChoseSubtitles(_ option: AVMediaSelectionOption?) {
        guard !subtitleTracks.isEmpty else {
            PreviewPlayback.rememberSubtitles(option)
            return
        }
        let choice: PreviewSubtitleChoice
        if let option {
            if option.hasMediaCharacteristic(.machineGenerated) {
                choice = .transcribed
            } else if let position = clipTextOptions?.firstIndex(of: option) {
                choice = .track(textTracks[position].index)
            } else {
                return
            }
        } else {
            // The player's subtitles go off while a picture track is drawn,
            // or a text track this clip lacks is chosen — the preview's own
            // doing, not a choice.
            if case .track(let index) = subtitleChoice,
               let track = subtitleTracks.first(where: { $0.index == index }),
               track.kind == .picture || clipTextOptions == nil {
                return
            }
            choice = .off
        }
        guard choice != subtitleChoice else { return }
        subtitleChoice = choice
        PreviewSubtitleMemory.remember(choice, for: source.url)
        drawPictureSubtitles(for: clipCounter, start: clipStart)
    }

    /// For a picture track: its pictures for a clip, drawn alongside the cut.
    /// Anything else clears them.
    private func drawPictureSubtitles(for clipID: Int, start: Double) {
        pictureTask?.cancel()
        pictureTask = nil
        guard case .track(let index) = subtitleChoice,
              let track = subtitleTracks.first(where: { $0.index == index }), track.kind == .picture,
              let workspace
        else {
            pictureSubtitles = nil
            return
        }
        if pictureSubtitles?.track != track { pictureSubtitles = nil }
        let folder = workspace.file(named: "subtitles-\(clipID)")
        let url = source.url
        pictureTask = Task { [weak self] in
            let result = await PictureSubtitles.extract(clipID: clipID, from: url, track: track, start: start,
                                                        length: Self.clipLength, folder: folder)
            guard !Task.isCancelled, let self else { return }
            self.pictureSubtitles = result
        }
    }

    // MARK: Closing

    /// Stops every ffmpeg run and deletes every temporary file, there and
    /// then. Playback stops; the player itself is let go in `close()`, once
    /// the window has finished animating out.
    func discardFiles() {
        isClosed = true
        rememberPlayback()
        cutTask?.cancel()
        cutTask = nil
        thumbnailTask?.cancel()
        thumbnailTask = nil
        pictureTask?.cancel()
        pictureTask = nil
        player?.pause()
        workspace?.cleanUp()
        workspace = nil
    }

    /// Stops playback and removes every temporary file.
    func close() {
        discardFiles()
        playbackObservers = []
        if let subtitleObserver { NotificationCenter.default.removeObserver(subtitleObserver) }
        subtitleObserver = nil
        legibleGroup = nil
        pictureSubtitles = nil
        player = nil
    }
}
