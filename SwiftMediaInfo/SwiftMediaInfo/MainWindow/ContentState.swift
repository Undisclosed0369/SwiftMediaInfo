//
//  ContentState.swift
//  SwiftMediaInfo
//
//  What a report pane shows when it isn't the report itself: analysing,
//  loading, not loaded, empty, failed, cancelled, a folder, or nothing open.
//
//  `ContentState.resolve` turns a MediaFile plus a ViewMode into exactly one
//  state, and ContentStateView draws it — with Try Again, Cancel, "Show
//  details" for the technical error, and an Install button when MediaInfo is
//  missing. Every pane (MainDetailView, both Compare panes) routes through
//  both, so a nil format never shows as a blank pane: the user can always
//  tell whether to wait, retry or give up.
//

import SwiftUI
import AppKit

// MARK: - State model

/// What a content pane should currently be showing.
enum ContentState: Equatable {
    
    /// No file open.
    case idle
    
    /// Initial analysis running — the first format hasn't arrived yet.
    case analysing(name: String)
    
    /// Analysis was stopped by the user.
    case cancelled
    
    /// This format loads on demand and hasn't been requested yet.
    case notLoaded(ViewMode)
    
    /// This format is being fetched right now.
    case loading(ViewMode)
    
    /// Content is present and should be rendered.
    case ready
    
    /// MediaInfo ran successfully but returned nothing usable.
    case empty(ViewMode)
    
    /// A folder was opened and this tab can't represent one.
    case folderUnsupported
    
    /// This format failed.
    case failed(MediaInfoError, ViewMode)
    
    /// MediaInfo isn't installed. Distinct from a generic failure because the
    /// remedy is completely different — install it, don't retry.
    case dependencyMissing
    
    // MARK: Derivation
    
    /// Reduce a file and the selected tab to a single state.
    ///
    /// Order matters here. Cancellation and dependency problems outrank
    /// everything, because retrying or waiting won't help in either case.
    static func resolve(file: MediaFile?, mode: ViewMode) -> ContentState {
        guard let file else { return .idle }
        
        if let error = file.loadError, error.isCancellation {
            return .cancelled
        }
        
        if file.isLoading {
            return .analysing(name: file.fileName)
        }
        
        // A missing binary surfaces on whichever format asked for it first.
        let anyError = file.error(for: mode) ?? file.loadError
        if let anyError {
            switch anyError {
            case .executableNotFound, .executableNotExecutable:
                return .dependencyMissing
            default:
                if file.error(for: mode) != nil {
                    return .failed(anyError, mode)
                }
            }
        }
        
        switch mode {
        case .easy:
            if file.tracks.isEmpty {
                // Formats now load one at a time, so arriving on Easy View
                // while its JSON is still queued behind another tab is normal.
                if file.isLoadingJSON { return .loading(mode) }
                if let error = file.jsonError { return .failed(error, mode) }
                // Folders are a legitimate thing to open — mediainfo will
                // happily describe their contents in Text or JSON — they just
                // have no track structure for Easy View to lay out. Saying so
                // is far more useful than "no tracks found".
                if file.isDirectory { return .folderUnsupported }
                return .empty(mode)
            }
            return .ready
            
        case .text:
            return resolveString(file.rawText, loading: file.isLoadingText, mode: mode)
            
        case .rawText:
            return resolveString(file.rawTextFull, loading: file.isLoadingRawText, mode: mode)
            
        case .json:
            return resolveString(file.rawJSON, loading: file.isLoadingJSON, mode: mode)
            
        case .html:
            return resolveString(file.rawHTML, loading: file.isLoadingHTML, mode: mode)
            
        case .xml:
            return resolveString(file.rawXML, loading: file.isLoadingXML, mode: mode)
        }
    }
    
    private static func resolveString(
        _ content: String?,
        loading: Bool,
        mode: ViewMode
    ) -> ContentState {
        if loading { return .loading(mode) }
        guard let content else { return .notLoaded(mode) }
        return content.isEmpty ? .empty(mode) : .ready
    }
    
    /// True when the pane should render actual content rather than a state view.
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

// MARK: - State presentation

/// The single component that draws every non-content state.
///
/// Structure is deliberately identical across states — halo, symbol, title,
/// message, action — so switching between them reads as one element changing
/// rather than different screens appearing.
struct ContentStateView: View {
    let state: ContentState
    var isCompare: Bool = false
    
    @EnvironmentObject var store: MediaStore
    @State private var showDiagnostics = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    // The same installer the status bar and Settings use, so an install
    // started from any of the three is reflected in all of them.
    @ObservedObject private var installer = DependencyInstaller.shared
    
    var body: some View {
        VStack(spacing: SMI.Spacing.large) {
            halo
            titles
            diagnostics
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(SMI.Spacing.huge)
        .smiAnimation(SMI.Motion.smooth, value: showDiagnostics)
    }
    
    // MARK: Halo
    
    private var halo: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accent.opacity(0.20), accent.opacity(0.04)],
                        center: .center,
                        startRadius: 4,
                        endRadius: 54
                    )
                )
                .frame(width: 96, height: 96)
            
            if isBusy {
                ProgressView()
                    .tint(accent)
                    .scaleEffect(1.25)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(LinearGradient.brandSweep(accent))
            }
        }
        .smiAnimation(SMI.Motion.flourish, value: symbol)
    }
    
    // MARK: Text
    
    private var titles: some View {
        VStack(spacing: SMI.Spacing.snug) {
            Text(title)
                .font(SMI.Typo.title)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            
            if let message {
                Text(message)
                    .font(SMI.Typo.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    // MARK: Diagnostics disclosure
    //
    // Technical detail is available but never in the way. Normal users see a
    // plain sentence; anyone filing a bug report can open this and copy the
    // exact failure.
    
    @ViewBuilder
    private var diagnostics: some View {
        if let detail = diagnosticDetail {
            VStack(spacing: SMI.Spacing.small) {
                Button {
                    showDiagnostics.toggle()
                } label: {
                    HStack(spacing: SMI.Spacing.tight) {
                        Image(systemName: showDiagnostics ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(showDiagnostics ? "Hide details" : "Show details")
                            .font(SMI.Typo.caption)
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                if showDiagnostics {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.leading)
                        .padding(SMI.Spacing.medium)
                        .frame(maxWidth: 460, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: SMI.Radius.control, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
    
    // MARK: Actions
    
    @ViewBuilder
    private var actions: some View {
        switch state {
        case .idle, .ready:
            EmptyView()
            
        case .analysing:
            Button("Cancel") {
                store.cancelLoading(isCompare: isCompare)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            
        case .cancelled:
            Button("Analyse Again") {
                store.retry(isCompare: isCompare)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .controlSize(.large)
            
        case .notLoaded(let mode):
            Button("Load \(mode.label)") {
                store.loadFormatIfNeeded(mode, isCompare: isCompare)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .controlSize(.large)
            
        case .loading:
            EmptyView()
            
        case .empty:
            Button("Try Again") {
                store.retry(isCompare: isCompare)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            
        case .folderUnsupported:
            Button("Show Text View") {
                smiWithAnimation(SMI.Motion.smooth) { store.viewMode = .text }
            }
            .buttonStyle(.borderedProminent)
            .tint(SMI.Palette.viewMode(.text))
            .controlSize(.large)
            
        case .failed(let error, let mode):
            HStack(spacing: SMI.Spacing.medium) {
                if error.isRetryable {
                    // Every format can now be fetched on its own, so retrying
                    // one tab no longer throws away the others.
                    Button("Try Again") {
                        store.clearError(for: mode, isCompare: isCompare)
                        store.loadFormatIfNeeded(mode, isCompare: isCompare)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.large)
                }
            }
            
        case .dependencyMissing:
            dependencyActions
        }
    }
    
    // MARK: Dependency actions
    //
    // One question — is Homebrew here? — and exactly one next step for the
    // answer: install MediaInfo with it, or get Homebrew. Never both, and never
    // a link when a button would do.
    
    @ViewBuilder
    private var dependencyActions: some View {
        switch installer.state {
        case .installing(let package):
            HStack(spacing: SMI.Spacing.small) {
                ProgressView().controlSize(.small)
                Text("Installing \(package)…")
                    .font(SMI.Typo.callout)
                    .foregroundStyle(.secondary)
            }
            
        case .failed(let reason):
            VStack(spacing: SMI.Spacing.medium) {
                Text(reason)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
                
                HStack(spacing: SMI.Spacing.medium) {
                    Button("Try Again") { beginInstall() }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .controlSize(.large)
                    
                    Button("Dismiss") { installer.reset() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
            }
            
        case .idle, .succeeded:
            if DependencyInstaller.isHomebrewInstalled {
                Button("Install MediaInfo") { beginInstall() }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.large)
                    .help("Runs brew install mediainfo, then reopens this file")
            } else {
                // Homebrew is the missing piece, so it is the only thing worth
                // offering. An "Install MediaInfo" button here would open a web
                // page and read as a failure.
                Button("Get Homebrew") {
                    ProjectLinks.open(ProjectLinks.homebrew)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.large)
                .help("Homebrew isn’t installed. It’s the easiest way to get MediaInfo.")
            }
        }
    }
    
    /// Install, then re-read the file that could not be read.
    ///
    /// Without the reopen the user is left looking at "MediaInfo isn't
    /// installed" immediately after installing it, with no indication that the
    /// only thing left to do is open the file again. The app knows which file
    /// it failed on, so it should just do it.
    private func beginInstall() {
        installer.install("mediainfo") {
            store.retryAfterDependencyInstall()
        }
    }
    
    // MARK: Presentation mapping
    
    private var isBusy: Bool {
        switch state {
        case .analysing, .loading: return true
        default: return false
        }
    }
    
    private var accent: Color {
        switch state {
        case .idle:              return .brandViolet
        case .analysing:         return .brandViolet
        case .cancelled:         return .secondary
        case .notLoaded(let m):  return SMI.Palette.viewMode(m)
        case .loading(let m):    return SMI.Palette.viewMode(m)
        case .ready:             return .brandViolet
        case .empty:             return SMI.Palette.warning
        case .failed:            return SMI.Palette.danger
        case .dependencyMissing: return SMI.Palette.warning
        case .folderUnsupported: return .brandTeal
        }
    }
    
    private var symbol: String {
        switch state {
        case .idle:              return "film.stack"
        case .analysing:         return "waveform"
        case .cancelled:         return "stop.circle"
        case .notLoaded:         return "arrow.down.circle"
        case .loading:           return "waveform"
        case .ready:             return "checkmark.circle"
        case .empty:             return "doc.questionmark"
        case .failed:            return "exclamationmark.triangle"
        case .dependencyMissing: return "shippingbox"
        case .folderUnsupported: return "folder.badge.questionmark"
        }
    }
    
    private var title: String {
        switch state {
        case .idle:
            return "No file open"
        case .analysing(let name):
            return "Analysing \(name)"
        case .cancelled:
            return "Analysis cancelled"
        case .notLoaded(let mode):
            return "\(mode.label) not loaded yet"
        case .loading(let mode):
            return "Loading \(mode.label)…"
        case .ready:
            return ""
        case .empty(let mode):
            return mode == .easy ? "No media tracks found" : "Nothing to show"
        case .failed(let error, _):
            return error.errorDescription ?? "Something went wrong"
        case .dependencyMissing:
            return "MediaInfo isn’t installed"
        case .folderUnsupported:
            return "Easy View doesn’t support folders"
        }
    }
    
    private var message: String? {
        switch state {
        case .idle:
            return nil
        case .analysing:
            return "Reading metadata in every format at once."
        case .cancelled:
            return "You stopped this before it finished."
        case .notLoaded:
            return "This format loads on demand so opening files stays fast."
        case .loading:
            return nil
        case .ready:
            return nil
        case .empty(let mode):
            return mode == .easy
            ? "MediaInfo didn’t report any tracks. Try the Text tab — it may still show raw output."
            : "MediaInfo ran successfully but produced no output for this file."
        case .failed(let error, _):
            return error.recoverySuggestion
        case .dependencyMissing:
            return DependencyInstaller.isHomebrewInstalled
            ? "SwiftMediaInfo reads metadata by running the MediaInfo command-line tool. Homebrew is already here, so this is one click."
            : "SwiftMediaInfo reads metadata by running the MediaInfo command-line tool. Homebrew installs it in one step — get Homebrew first, then come back."
        case .folderUnsupported:
            return "Easy View lays out media tracks, and a folder doesn’t have any. Switch to Text, Raw Text, XML, or JSON to see what MediaInfo reports about its contents."
        }
    }
    
    private var diagnosticDetail: String? {
        guard case .failed(let error, let mode) = state else { return nil }
        return "\(mode.displayNameForDiagnostics): \(error.diagnosticDetail)"
    }
}

// MARK: - Helpers

private extension ViewMode {
    var displayNameForDiagnostics: String {
        switch self {
        case .easy:    return "Metadata"
        case .text:    return "Text"
        case .rawText: return "Raw Text"
        case .html:    return "HTML"
        case .xml:     return "XML"
        case .json:    return "JSON"
        }
    }
}
