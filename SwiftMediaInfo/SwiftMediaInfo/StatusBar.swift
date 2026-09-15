//
//  StatusBar.swift
//  SwiftMediaInfo
//
//  PHASE 9 — the dependency strip rebuilt on DependencyInstaller.
//
//  WHAT WAS HERE BEFORE
//
//  A second copy of the Homebrew install logic, written before
//  DependencyInstaller existed and left in place deliberately until this
//  phase. It ran `brew` on a global queue, reported the outcome in an NSAlert,
//  and had no idea whether Settings was running an install at the same time.
//  Two copies of an installer is exactly how they drift into behaving
//  differently, and this one had already drifted: it looped over a list of
//  packages that can only ever contain one entry, because `mediainfo` is the
//  only dependency Homebrew can supply.
//
//  WHAT IT DOES NOW
//
//  Nothing. It asks the shared installer, and draws whatever the installer
//  says. An install started in Settings shows its spinner here too, and
//  neither window can start a second `brew` against the same lock.
//
//  NO PROGRESS BAR
//
//  Homebrew emits no parseable percentage. A bar drawn here would be a
//  fiction, and a fiction is worse than a spinner because it invites the user
//  to predict a finish time that nothing is measuring. The spinner is paired
//  with wording that says what is happening instead.
//
//  THE SCAN RUNS ON EVERY RENDER, ON PURPOSE
//
//  Someone can install or remove mediainfo in Terminal while the app is open,
//  and a bar that only checked on appearance would go on insisting the tool is
//  missing — or, worse, insisting it is present — until something else
//  happened to redraw it. Re-checking is the cheapest possible guard against
//  failing silently, so it stays.
//
//  The cost is a handful of `stat` calls. The expensive case — a lookup that
//  fails and therefore walks every directory in PATH — is bounded by a short
//  negative-result window inside MediaEngine, so a rapid burst of renders
//  cannot turn into a burst of filesystem scans. See
//  MediaEngine.negativeLookupWindow.
//

import SwiftUI
import AppKit

// MARK: - A missing dependency

struct MissingDependency: Identifiable, Equatable {
    let id: String
    let name: String
    
    /// The Homebrew formula that supplies it, or nil for a tool that ships
    /// with macOS and should never be missing in the first place.
    let brewFormula: String?
    
    var isSystemTool: Bool { brewFormula == nil }
}

struct StatusBar: View {
    @EnvironmentObject var store: MediaStore
    
    // PHASE 9 — shared, so this strip reflects an install started in Settings.
    @ObservedObject private var installer = DependencyInstaller.shared
    
    // MARK: - Dependency scan
    
    /// Recomputed on every render, deliberately — see the note at the top of
    /// this file.
    private var missing: [MissingDependency] {
        Self.scanDependencies()
    }
    
    private static func scanDependencies() -> [MissingDependency] {
        var result: [MissingDependency] = []
        let fm = FileManager.default
        
        // MediaEngine caches successful lookups only, so a path that resolves
        // here is genuinely present.
        let mediaInfoPath = MediaEngine.binaryPath
        let mediaInfoFound = mediaInfoPath.hasPrefix("/")
        && fm.fileExists(atPath: mediaInfoPath)
        
        if !mediaInfoFound {
            result.append(
                MissingDependency(id: "mediainfo", name: "mediainfo", brewFormula: "mediainfo")
            )
        }
        
        if !fm.fileExists(atPath: "/usr/bin/curl") {
            result.append(MissingDependency(id: "curl", name: "curl", brewFormula: nil))
        }
        
        if !fm.fileExists(atPath: "/usr/bin/zip") {
            result.append(MissingDependency(id: "zip", name: "zip", brewFormula: nil))
        }
        
        return result
    }
    
    /// The one formula Homebrew can supply, if it is missing.
    private var brewableFormula: String? {
        missing.compactMap(\.brewFormula).first
    }
    
    private var systemTools: [MissingDependency] {
        missing.filter(\.isSystemTool)
    }
    
    /// Whether the dependency strip should be showing at all.
    ///
    /// An install in progress, or a finished one with something to say, keeps
    /// the strip up even once the dependency is satisfied — otherwise the bar
    /// would vanish at the exact moment it had good news to deliver.
    private var showsDependencyBar: Bool {
        !missing.isEmpty || installer.isInstalling || installer.hasOutcome
    }
    
    var body: some View {
        Group {
            if showsDependencyBar {
                dependencyBar
                    .padding(.vertical, 7)
            } else if store.isCompareMode {
                compareStatusBar
            } else if let file = store.currentFile {
                singleFileBar(file: file)
            } else {
                HStack {
                    Text("No file open")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(.ultraThinMaterial)
        .smiAnimation(SMI.Motion.smooth, value: installer.state)
        .smiAnimation(SMI.Motion.smooth, value: missing)
    }
    
    // MARK: - Single file bar
    
    @ViewBuilder
    private func singleFileBar(file: MediaFile) -> some View {
        HStack(spacing: 14) {
            if file.isLoading {
                statusChip(icon: "doc", text: file.fileName, color: .brandBlue, meaning: "File")
                statusChip(icon: "internaldrive", text: file.fileSizeString, color: .brandViolet, meaning: "File size")
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
                statusChip(icon: "internaldrive", text: file.fileSizeString, color: .brandPink, meaning: "File size")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        // Phase 8b. The status bar is the one strip that is always about the
        // open file, whichever tab is showing — including the tabs that are
        // AppKit text views and swallow right-clicks of their own.
        .contextMenu {
            FileActionsMenuItems(store: store, url: file.url, isCompare: false)
        }
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
                    statusChip(icon: "internaldrive", text: fileA.fileSizeString, color: .brandPink, meaning: "File size")
                } else {
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            // Each half carries its own menu, so which file an action applies
            // to is decided by where you clicked rather than by a mode the
            // menu would have to explain.
            .contextMenu {
                if let fileA = store.currentFile {
                    FileActionsMenuItems(store: store, url: fileA.url, isCompare: false)
                }
            }
            
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
                    statusChip(icon: "internaldrive", text: fileB.fileSizeString, color: .brandPink, meaning: "File size")
                } else {
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .contextMenu {
                if let fileB = store.compareFile {
                    FileActionsMenuItems(store: store, url: fileB.url, isCompare: true)
                }
            }
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
        // "A" spoken on its own is a letter. "File A" is a heading for
        // everything that follows it in this half of the bar.
            .smiReadAsOne("File \(label)")
    }
    
    // MARK: - Shared file chips
    
    @ViewBuilder
    private func fileChips(file: MediaFile) -> some View {
        if let general = file.generalTrack {
            if let fmt = general.fields.first(where: { $0.key == "Format" })?.value {
                statusChip(icon: "doc.fill", text: fmt, color: .brandBlue, meaning: "Format")
            }
            
            if let dur = general.fields.first(where: { $0.key == "Duration_String3" })?.value
                ?? general.fields.first(where: { $0.key == "Duration_String" })?.value
                ?? general.fields.first(where: { $0.key == "Duration" })?.value {
                statusChip(icon: "clock.fill", text: dur, color: .brandViolet, meaning: "Duration")
            }
            if let br = general.fields.first(where: { $0.key == "OverallBitRate_String" })?.value
                ?? general.fields.first(where: { $0.key == "OverallBitRate" })?.value {
                statusChip(icon: "bolt.fill", text: br, color: .brandPink, meaning: "Overall bit rate")
            }
        }
        
        if let video = file.videoTracks.first {
            let w = video.fields.first(where: { $0.key == "Width"  })?.value ?? ""
            let h = video.fields.first(where: { $0.key == "Height" })?.value ?? ""
            if !w.isEmpty {
                statusChip(
                    icon: "film.fill",
                    text: "\(w)×\(h)",
                    color: .brandBlue,
                    meaning: "Resolution"
                )
            }
            if let fps = video.fields.first(where: { $0.key == "FrameRate" })?.value {
                statusChip(
                    icon: "speedometer",
                    text: "\(fps) fps",
                    color: .brandGreen,
                    meaning: "Frame rate"
                )
            }
        }
        
        if !file.audioTracks.isEmpty {
            let n = file.audioTracks.count
            statusChip(
                icon: "waveform",
                text: "\(n) audio",
                color: .brandViolet,
                meaning: "Audio tracks"
            )
        }
        
        if !file.textTracks.isEmpty {
            let n = file.textTracks.count
            statusChip(
                icon: "captions.bubble.fill",
                text: "\(n) sub\(n == 1 ? "" : "s")",
                color: .brandGreen,
                meaning: "Subtitle tracks"
            )
        }
    }
    
    // MARK: - Status chip
    //
    // PHASE 11. Every chip is one idea drawn as two views, and left alone
    // VoiceOver stopped on each half — "image", then "1920×1080". Combined and
    // named, it is one stop that says "Resolution, 1920×1080".
    //
    // The name has to come from the caller, because the icon is the only thing
    // that says what the number means and an icon cannot be read aloud. That is
    // exactly the gap this closes.
    
    private func statusChip(
        icon: String,
        text: String,
        color: Color,
        meaning: String? = nil
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize()
        }
        .smiReadAsOne(meaning.map { "\($0), \(text)" } ?? text)
    }
    
    // MARK: - Dependency strip
    //
    // Four states, drawn by one function so they read as one element changing
    // rather than four different bars taking turns.
    
    @ViewBuilder
    private var dependencyBar: some View {
        HStack(spacing: 10) {
            switch installer.state {
            case .installing(let package):
                installingContent(package: package)
                
            case .succeeded(let package):
                succeededContent(package: package)
                
            case .failed(let reason):
                failedContent(reason: reason)
                
            case .idle:
                missingContent
            }
        }
        .padding(.horizontal, 14)
        // PHASE 11. This strip changes on its own — an install finishing, a
        // `brew uninstall` in Terminal — with no user action to move focus.
        // `.updatesFrequently` is what tells VoiceOver to re-read it rather
        // than trusting the sentence it heard when focus first arrived.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dependency status")
        .accessibilityAddTraits(.updatesFrequently)
    }
    
    // MARK: Idle — what is missing and how to get it
    
    @ViewBuilder
    private var missingContent: some View {
        pill(
            icon: "exclamationmark.triangle.fill",
            text: "\(missing.map(\.name).joined(separator: ", ")) missing",
            background: SMI.Palette.danger
        )
        
        if !systemTools.isEmpty {
            Text("\(systemTools.map(\.name).joined(separator: ", ")) should be in /usr/bin — reinstall the macOS Command Line Tools.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        
        Spacer(minLength: 8)
        
        if let formula = brewableFormula {
            if DependencyInstaller.isHomebrewInstalled {
                Button {
                    installer.install(formula) {
                        // The open file failed for exactly one reason, and that
                        // reason has just gone away. Re-reading it is the whole
                        // point of having installed anything.
                        //
                        // No rescan call: the installer clears MediaEngine's
                        // cached location itself, and `missing` is recomputed on
                        // the next render anyway.
                        store.retryAfterDependencyInstall()
                    }
                } label: {
                    Label("Install \(formula) via Homebrew", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandViolet)
            } else {
                // Homebrew itself is the missing piece. Offering "Install
                // mediainfo" here would open brew.sh and look like a failure;
                // naming the actual next step is more honest.
                Button {
                    if let url = URL(string: "https://brew.sh") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Get Homebrew", systemImage: "arrow.up.right.square")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandViolet)
                .help("Homebrew isn’t installed. It’s the easiest way to get MediaInfo.")
            }
        }
        
        if !systemTools.isEmpty {
            Button(action: installCommandLineTools) {
                Label("Install CLI Tools", systemImage: "terminal")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandBlue)
        }
    }
    
    // MARK: Installing
    
    @ViewBuilder
    private func installingContent(package: String) -> some View {
        ProgressView()
            .controlSize(.small)
            .tint(.brandViolet)
        
        Text("Installing \(package)…")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.brandViolet)
        
        // Said plainly rather than drawn as a bar that would be guessing.
        Text("Homebrew doesn’t report progress. This can take a few minutes.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
        
        Spacer(minLength: 8)
    }
    
    // MARK: Succeeded
    
    @ViewBuilder
    private func succeededContent(package: String) -> some View {
        pill(
            icon: "checkmark.circle.fill",
            text: "\(package) installed",
            background: SMI.Palette.success
        )
        
        // The file is reopened automatically on success, so this says what
        // happened rather than handing out homework.
        Text("Your file has been re-read with MediaInfo available.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
        
        Spacer(minLength: 8)
        
        Button("Done") { installer.reset() }
            .buttonStyle(.bordered)
            .font(.system(size: 11, weight: .medium))
    }
    
    // MARK: Failed
    
    @ViewBuilder
    private func failedContent(reason: String) -> some View {
        pill(
            icon: "xmark.octagon.fill",
            text: "Install failed",
            background: SMI.Palette.danger
        )
        
        // Homebrew's own last words, truncated to one line. The full text is
        // in Settings › MediaInfo, where there is room to read it.
        Text(reason.replacingOccurrences(of: "\n", with: " "))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .help(reason)
        
        Spacer(minLength: 8)
        
        Button("Retry") {
            installer.retry {
                store.retryAfterDependencyInstall()
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.brandViolet)
        .font(.system(size: 11, weight: .medium))
        
        Button("Dismiss") { installer.reset() }
            .buttonStyle(.bordered)
            .font(.system(size: 11, weight: .medium))
    }
    
    // MARK: Shared pill
    
    private func pill(icon: String, text: String, background: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundStyle(.white)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(background.opacity(0.85))
        )
        .smiReadAsOne(text)
    }
    
    // MARK: - Install Xcode Command Line Tools
    //
    // Not routed through DependencyInstaller: this is not Homebrew, it hands
    // off to the system's own installer panel, and there is nothing to wait
    // for or report on afterwards.
    
    private func installCommandLineTools() {
        Task.detached(priority: .userInitiated) {
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
