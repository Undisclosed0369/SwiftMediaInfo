//
//  MediaPreviewView.swift
//  SwiftMediaInfo
//
//  The preview window for files Quick Look can't open, and the rule for which
//  preview Space shows (PreviewRouter).
//
//  It behaves like Quick Look: Space or Escape closes it, it floats over the
//  main window (stepping back while the video is full screen), and switching
//  tabs or entering Compare Mode closes it. ← / → skip 10 seconds. The window
//  holds AVKit's player (with the picture-subtitle overlay), the filmstrip
//  timeline, the Subtitles menu and "Open with <app>" in the title bar.
//

import SwiftUI
import AVKit
import Quartz
internal import Combine

// MARK: - Which preview

@MainActor
enum PreviewRouter {
    /// Files Quick Look itself previews well. Anything else — MKV above all,
    /// and AVI, WebM, TS, M2TS, WMV, FLV, OGG, MKA, MPEG… — gets the
    /// SwiftMediaInfo preview.
    private static let nativeExtensions: Set<String> = [
        "mp4", "m4v", "mov", "qt", "3gp", "3g2",
        "m4a", "m4b", "mp3", "wav", "aif", "aiff", "aifc", "caf", "aac", "flac",
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp", "avif", "pdf"
    ]

    static func usesNativeQuickLook(_ url: URL) -> Bool {
        nativeExtensions.contains(url.pathExtension.lowercased())
    }

    /// Space: show the right preview for `file`, or close whichever is open.
    static func toggle(file: MediaFile) {
        if QuickLookController.shared.isVisible {
            QLPreviewPanel.shared().orderOut(nil)
        } else if MediaPreviewController.shared.isVisible {
            MediaPreviewController.shared.close()
        } else if usesNativeQuickLook(file.url) {
            QuickLookController.shared.toggle(url: file.url)
        } else {
            MediaPreviewController.shared.show(file: file)
        }
    }

    /// The file on screen changed (another tab, or Compare Mode began).
    static func screenChanged(to url: URL?) {
        QuickLookController.shared.follow(url)
        MediaPreviewController.shared.close()
    }
}

// MARK: - Window

@MainActor
final class MediaPreviewController: NSObject, NSWindowDelegate {

    static let shared = MediaPreviewController()

    private var window: NSWindow?
    private var session: PreviewSession?
    private var keyMonitor: Any?

    var isVisible: Bool { window?.isVisible ?? false }

    /// Restore Defaults: the open preview, if there is one, goes back to the
    /// default playback settings.
    func restoreDefaultPlayback() {
        session?.restoreDefaultPlayback()
    }

    func show(file: MediaFile) {
        close()

        let session = PreviewSession(source: PreviewSource(file: file))
        self.session = session

        // A standard titled window with a unified toolbar, so the title bar,
        // its glass and the toolbar button are the system's own — the same
        // chrome as Quick Look and QuickTime Player on this macOS.
        //
        // Not miniaturizable, like About, Settings and Keyboard Shortcuts:
        // ⌘M does nothing here, Window › Minimize is greyed out and the
        // yellow button is dimmed (see PanelWindowBehaviour in WindowChrome).
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 480)
        window.level = .floating
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
        window.delegate = self

        // The view's .navigationTitle, .navigationSubtitle and .toolbar become
        // the window's.
        let host = NSHostingController(rootView: MediaPreviewView(session: session))
        host.sceneBridgingOptions = .all
        // The window keeps the size it opens at (and the user's resizing);
        // only the minimum comes from the view.
        host.sizingOptions = [.minSize]
        window.contentViewController = host
        window.setContentSize(NSSize(width: 980, height: 700))
        window.layoutIfNeeded()
        Self.fit(window, to: session, on: (NSApp.mainWindow ?? NSApp.keyWindow)?.screen)
        Self.center(window, over: NSApp.mainWindow ?? NSApp.keyWindow)
        self.window = window
        // The window server's own open and close animation — the GPU zoom
        // and fade that system windows use, run on a snapshot of the window
        // rather than by resizing it, so it stays perfectly smooth while the
        // player and filmstrip load behind it. Reduce Motion is honoured by
        // the system.
        window.animationBehavior = .documentWindow
        window.makeKeyAndOrderFront(nil)

        // Space and Escape close it, as in Quick Look; ← and → skip 10
        // seconds back or forward.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            else { return event }
            switch event.keyCode {
            case 49, 53:
                self.close()
            case 123 where !(self.session?.ffmpegMissing ?? true):
                self.session?.skip(by: -PreviewSession.skipLength)
            case 124 where !(self.session?.ffmpegMissing ?? true):
                self.session?.skip(by: PreviewSession.skipLength)
            default:
                return event
            }
            return nil
        }

        session.start()
    }

    /// Opens at the shape of the picture, as Quick Look does: the video
    /// fills the space between the title bar and the timeline, with no black
    /// beyond what is in the file itself. 980 points wide, unless that would
    /// be taller than the screen allows; audio and files whose shape is not
    /// known keep the standard size.
    private static func fit(_ window: NSWindow, to session: PreviewSession, on screen: NSScreen?) {
        guard session.source.hasVideo, !session.ffmpegMissing,
              let aspect = session.source.aspectRatio else { return }

        // What is not picture: the title bar above, the timeline below.
        let titleBar = window.frame.height - window.contentLayoutRect.height
        let timeline = NSHostingView(rootView: PreviewTimeline(session: session).frame(width: 980))
            .fittingSize.height
        let chrome = titleBar + timeline

        let available = ((screen ?? NSScreen.main)?.visibleFrame.height ?? 900) * 0.85
        var width: CGFloat = 980
        var height = width / aspect + chrome
        if height > available {
            height = available
            width = (height - chrome) * aspect
        }
        width = max(width, window.minSize.width)
        height = max(height, window.minSize.height)
        window.setContentSize(NSSize(width: width.rounded(), height: height.rounded()))
    }

    /// Centred on the app's window, as a sheet would be — not on the
    /// screen, which with a window off to one side opens it somewhere else
    /// entirely. Kept on the screen that window is on.
    private static func center(_ window: NSWindow, over parent: NSWindow?) {
        guard let parent, parent.isVisible else { window.center(); return }
        let size = window.frame.size
        var origin = NSPoint(x: parent.frame.midX - size.width / 2,
                             y: parent.frame.midY - size.height / 2)
        if let visible = (parent.screen ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        window.setFrameOrigin(NSPoint(x: origin.x.rounded(), y: origin.y.rounded()))
    }

    /// Closes with the system's shrink-and-fade. The controller lets go of
    /// the window at once — Space, a tab switch or a new preview can follow
    /// straight away — and the window finishes animating out on its own.
    func close() {
        guard let window else { return }
        self.window = nil
        window.delegate = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil

        let session = self.session
        self.session = nil
        // Silence first — the sound stopping is what says "closed" — and
        // every temporary clip, frame and subtitle picture deleted there and
        // then, with any ffmpeg still at work stopped. The playback settings
        // are kept now, for a preview opened before this one has finished
        // closing.
        session?.discardFiles()

        window.close()
        // The player is let go once the animation has finished with the
        // window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            window.contentViewController = nil
            session?.close()
        }
    }

    /// The close button animates too, rather than vanishing.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close()
        return false
    }

    /// Closed without asking (the app quitting): no animation, but the
    /// temporary clips still go.
    func windowWillClose(_ notification: Notification) {
        window = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        session?.close()
        session = nil
    }
}

// MARK: - View

struct MediaPreviewView: View {
    @ObservedObject var session: PreviewSession

    @ObservedObject private var installer = DependencyInstaller.shared
    @State private var isPlaying = false

    private var source: PreviewSource { session.source }

    var body: some View {
        Group {
            if session.ffmpegMissing {
                ffmpegMissing
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
            } else {
                VStack(spacing: 0) {
                    stage
                    PreviewTimeline(session: session)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .navigationTitle(source.fileName)
        .navigationSubtitle(source.details.joined(separator: " · "))
        .toolbar {
            if !session.subtitleTracks.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    PreviewSubtitlesMenu(session: session)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    OpenInDefaultAppButton.openInDefaultApp(source.url)
                } label: {
                    Text(Self.openTitle(for: source.url))
                }
                .help("Open the original file")
            }
        }
    }

    // MARK: Stage

    /// The video, edge to edge on black, with any status floating over it on
    /// glass.
    private var stage: some View {
        ZStack {
            // Black reaches up under the title bar's glass; the picture itself
            // starts below it, so none of it is hidden and the window can be
            // sized to it exactly.
            Color.black
                .ignoresSafeArea(.container, edges: .top)

            if source.hasVideo {
                if let player = session.player {
                    PlayerView(player: player, style: .floating, subtitles: session.shownPictureSubtitles)
                }
            } else {
                // Audio: AVKit's own artwork is QuickTime's logo, so the stage
                // shows the file and one play/pause button instead. Where in
                // the file it is playing is on the timeline below.
                VStack(spacing: 18) {
                    Image(systemName: "waveform")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(.white.opacity(0.45))
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                    Text(source.fileName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 40)
                    if let player = session.player {
                        Button {
                            if player.timeControlStatus == .paused { player.play() } else { player.pause() }
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .help(isPlaying ? "Pause" : "Play")
                    }
                }
                .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
                    let playing = session.player.map { $0.timeControlStatus != .paused } ?? false
                    if playing != isPlaying { isPlaying = playing }
                }
                // Centred on the whole stage, title bar included, as before.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .top)
            }

            if session.isCutting {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Preparing \(Self.clock(session.clipStart))…")
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if let failure = session.failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
            }
        }
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.2), value: session.isCutting)
    }

    // MARK: ffmpeg missing

    private var ffmpegMissing: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text("Preview Needs ffmpeg")
                .font(.title2.weight(.semibold))
            Text("macOS can’t play \(source.url.pathExtension.uppercased()) files by itself. SwiftMediaInfo uses ffmpeg to cut short preview clips from the original — the file itself is never changed.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Group {
                switch installer.state {
                case .installing:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Installing ffmpeg… this can take a few minutes.")
                            .foregroundStyle(.secondary)
                    }
                case .failed(let reason):
                    VStack(spacing: 10) {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: 420)
                        Button("Try Again") { session.installFFmpeg() }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                    }
                default:
                    if DependencyInstaller.isHomebrewInstalled {
                        Button("Install ffmpeg") { session.installFFmpeg() }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                            .help("Runs brew install ffmpeg")
                    } else {
                        Button("Get Homebrew") {
                            ProjectLinks.open(ProjectLinks.homebrew)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .help("Homebrew isn’t installed. It’s the easiest way to get ffmpeg.")
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding(40)
    }

    // MARK: Helpers

    /// "Open with IINA", as Quick Look names it.
    static func openTitle(for url: URL) -> String {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return "Open" }
        let name = FileManager.default.displayName(atPath: app.path)
        return "Open with \((name as NSString).deletingPathExtension)"
    }

    static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Timeline

/// The whole file as one filmstrip, as in QuickTime Player's trim bar. The
/// clip that is playing is outlined; the playhead moves through it. Point at
/// any moment to see its time, click or drag to play from there; the glass
/// buttons below step a clip at a time.
private struct PreviewTimeline: View {
    @ObservedObject var session: PreviewSession

    @State private var hoverX: CGFloat?
    @State private var dragTime: Double?

    private var duration: Double { max(session.source.duration, 0.001) }
    private let stripHeight: CGFloat = 46
    private let corner: CGFloat = 10

    var body: some View {
        VStack(spacing: 12) {
            if session.source.duration > 0 { strip }

            HStack(spacing: 0) {
                Text(MediaPreviewView.clock(dragTime ?? session.clipStart))
                    .frame(width: 80, alignment: .leading)
                Spacer()
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        stepButton(-1)
                        Text("\(MediaPreviewView.clock(session.clipStart)) – \(MediaPreviewView.clock(session.clipEnd))")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .glassEffect(.regular, in: .capsule)
                            .help("The \(Int(PreviewSession.clipLength))-second clip playing now")
                        stepButton(1)
                    }
                }
                Spacer()
                Text(MediaPreviewView.clock(session.source.duration))
                    .frame(width: 80, alignment: .trailing)
            }
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    private func stepButton(_ direction: Double) -> some View {
        let seconds = Int(PreviewSession.skipLength)
        return Button {
            session.skip(by: direction * PreviewSession.skipLength)
        } label: {
            Image(systemName: direction < 0 ? "gobackward.10" : "goforward.10")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help(direction < 0 ? "Back \(seconds) seconds (←)" : "Forward \(seconds) seconds (→)")
    }

    // MARK: Strip

    private var strip: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                frames(width: width)

                // Outside the clip is dimmed a little, so the clip reads as
                // the lit part of the strip.
                clipWindow(width: width)

                playhead(width: width)

                if let x = hoverX ?? dragTime.map({ CGFloat($0 / duration) * width }) {
                    hoverMarker(x: x, width: width)
                }
            }
            .frame(height: stripHeight)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hoverX = min(max(point.x, 0), width)
                case .ended: hoverX = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragTime = time(at: value.location.x, width: width)
                    }
                    .onEnded { value in
                        session.cut(at: time(at: value.location.x, width: width))
                        dragTime = nil
                    }
            )
            .overlay(alignment: .topLeading) {
                if let x = hoverX ?? dragTime.map({ CGFloat($0 / duration) * width }) {
                    timeBubble(x: x, width: width)
                }
            }
        }
        .frame(height: stripHeight)
        .help("Click or drag to play from any point")
    }

    @ViewBuilder
    private func frames(width: CGFloat) -> some View {
        if session.source.hasVideo, !session.thumbnails.isEmpty {
            let tile = width / CGFloat(session.thumbnails.count)
            HStack(spacing: 0) {
                ForEach(session.thumbnails) { thumb in
                    ZStack {
                        Color.primary.opacity(0.06)
                        if let image = thumb.image {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: tile, height: stripHeight)
                    .clipped()
                    .animation(.easeOut(duration: 0.25), value: thumb.image != nil)
                }
            }
        } else {
            // Audio: a plain track.
            Rectangle().fill(.primary.opacity(0.08))
        }
    }

    private func clipWindow(width: CGFloat) -> some View {
        let x = CGFloat(session.clipStart / duration) * width
        let w = max(8, CGFloat((session.clipEnd - session.clipStart) / duration) * width)
        let left = min(x, width - w)
        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(.black.opacity(0.35))
                .mask(
                    ZStack(alignment: .leading) {
                        Rectangle()
                        Rectangle()
                            .frame(width: w)
                            .offset(x: left)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                )
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2.5)
                .frame(width: w, height: stripHeight)
                .offset(x: left)
        }
        .allowsHitTesting(false)
        .animation(.smooth(duration: 0.3), value: session.clipStart)
    }

    /// Where playback is within the whole file.
    private func playhead(width: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let played = session.player.map { max(0, $0.currentTime().seconds) } ?? 0
            let t = session.clipStart + (played.isFinite ? played : 0)
            Capsule()
                .fill(.white)
                .shadow(color: .black.opacity(0.5), radius: 1.5)
                .frame(width: 3, height: stripHeight + 2)
                .offset(x: min(max(CGFloat(t / duration) * width - 1.5, 0), width - 3))
                .opacity(session.isCutting || session.player == nil ? 0 : 1)
        }
        .allowsHitTesting(false)
    }

    private func hoverMarker(x: CGFloat, width: CGFloat) -> some View {
        Rectangle()
            .fill(.white.opacity(0.85))
            .frame(width: 1, height: stripHeight)
            .offset(x: min(max(x, 0), width - 1))
            .allowsHitTesting(false)
    }

    private func timeBubble(x: CGFloat, width: CGFloat) -> some View {
        let label = MediaPreviewView.clock(time(at: x, width: width))
        let bubbleWidth: CGFloat = 72
        return Text(label)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .frame(width: bubbleWidth, height: 24)
            .glassEffect(.regular, in: .capsule)
            .offset(x: min(max(x - bubbleWidth / 2, 0), width - bubbleWidth), y: -32)
            .allowsHitTesting(false)
    }

    private func time(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1)) * session.source.duration
    }
}

/// The window's Subtitles menu: every subtitle track in the file, text and
/// picture alike, and macOS's transcription where the clip offers it.
private struct PreviewSubtitlesMenu: View {
    @ObservedObject var session: PreviewSession

    var body: some View {
        Menu {
            Picker("Subtitles", selection: Binding(
                get: { session.subtitleChoice },
                set: { session.chooseSubtitles($0) }
            )) {
                Text("Off").tag(PreviewSubtitleChoice.off)
                Section {
                    ForEach(session.subtitleTracks) { track in
                        Text(names[track.index] ?? track.name).tag(PreviewSubtitleChoice.track(track.index))
                    }
                }
                if session.offersTranscription || session.subtitleChoice == .transcribed {
                    Section {
                        Text("Transcribed by macOS").tag(PreviewSubtitleChoice.transcribed)
                    }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label("Subtitles", systemImage: session.subtitleChoice == .off ? "captions.bubble" : "captions.bubble.fill")
        }
        .help("Subtitles")
    }

    /// Track names, with the format added where two would read the same
    /// ("English (PGS)", "English (SRT)"), and a number if they still do.
    private var names: [Int: String] {
        let tracks = session.subtitleTracks
        var result: [Int: String] = [:]
        let plain = Dictionary(grouping: tracks, by: \.name)
        for track in tracks {
            result[track.index] = (plain[track.name]?.count ?? 0) > 1 ? "\(track.name) (\(track.formatName))" : track.name
        }
        let withFormat = Dictionary(grouping: tracks, by: { result[$0.index] ?? "" })
        for (name, group) in withFormat where group.count > 1 {
            for (number, track) in group.enumerated() { result[track.index] = "\(name) \(number + 1)" }
        }
        return result
    }
}

/// AVKit's own player view: the system's floating playback controls, HDR and
/// Dolby Vision output, Picture in Picture.
private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    let style: AVPlayerViewControlsStyle
    /// Picture subtitles to draw over the video.
    let subtitles: PictureSubtitles?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = style
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        view.videoGravity = PreviewPlayback.videoGravity
        view.delegate = context.coordinator
        view.player = player
        context.coordinator.watchZoom(of: view)
        if let overlay = view.contentOverlayView {
            let subtitleView = PictureSubtitleView(frame: overlay.bounds)
            subtitleView.autoresizingMask = [.width, .height]
            subtitleView.playerView = view
            overlay.addSubview(subtitleView)
            context.coordinator.subtitleView = subtitleView
        }
        context.coordinator.subtitleView?.show(subtitles, playing: player)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
        context.coordinator.subtitleView?.show(subtitles, playing: player)
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        coordinator.subtitleView?.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, AVPlayerViewDelegate {
        var subtitleView: PictureSubtitleView?
        private var zoomObserver: NSKeyValueObservation?
        private weak var previewWindow: NSWindow?
        private var previewLevel: NSWindow.Level = .floating

        /// Fit or fill, kept for the next preview.
        func watchZoom(of view: AVPlayerView) {
            zoomObserver = view.observe(\.videoGravity) { view, _ in
                let gravity = view.videoGravity
                Task { @MainActor in PreviewPlayback.videoGravity = gravity }
            }
        }

        // The preview window floats above other windows, as Quick Look's
        // does — above the player's own full-screen window too, which it
        // covered. While the video is full screen the preview window steps
        // back to an ordinary window, behind it, and floats again after.

        func playerViewWillEnterFullScreen(_ playerView: AVPlayerView) {
            guard let window = playerView.window else { return }
            previewWindow = window
            previewLevel = window.level
            window.level = .normal
        }

        func playerViewDidExitFullScreen(_ playerView: AVPlayerView) {
            guard let window = previewWindow else { return }
            previewWindow = nil
            window.level = previewLevel
            window.makeKeyAndOrderFront(nil)
        }
    }
}
