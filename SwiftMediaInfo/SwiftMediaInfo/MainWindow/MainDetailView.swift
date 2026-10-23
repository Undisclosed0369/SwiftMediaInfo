//
//  MainDetailView.swift
//  SwiftMediaInfo
//
//  The report area of the main window: Compare Mode, a folder tab (sidebar
//  plus the selected file's report), one file's report in the current view,
//  or — with nothing open — the start screen (EmptyStateView: Open, Favorites,
//  Recent Files and the time-spent card with its fun facts).
//
//  One call to ContentState.resolve decides what a pane shows; anything that
//  isn't `.ready` is drawn by ContentStateView. The checksum strip sits above
//  every view's content.
//

import SwiftUI

struct MainDetailView: View {
    @EnvironmentObject var store: MediaStore
    
    var body: some View {
        Group {
            if store.isCompareMode {
                CompareView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if let folder = store.currentFolder, let tabID = store.selectedTabID {
                // A folder tab: its files on the left, the selected
                // file's report on the right.
                HStack(spacing: 0) {
                    FolderSidebar(folder: folder, tabID: tabID)
                    Divider().opacity(0.5)
                    folderDetail(folder: folder)
                }
                .transition(.opacity)
            } else if let file = store.currentFile {
                paneContent(file: file)
            } else {
                EmptyStateView()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .smiAnimation(SMI.Motion.smooth, value: store.currentFile?.id)
        .smiAnimation(SMI.Motion.smooth, value: store.isCompareMode)
        .onChange(of: store.viewMode) { _, newMode in
            store.loadFormatIfNeeded(newMode, isCompare: false)
        }
        // A different file in the current tab: put the view on screen at the
        // front of its loader's queue, as a view change would.
        .onChange(of: store.currentFile?.id) { _, _ in
            store.loadFormatIfNeeded(store.viewMode, isCompare: false)
        }
        .onChange(of: store.currentFile?.isLoading) { _, isLoading in
            // Once the first format has landed, check the view on screen
            // again — its format may have dropped out of the queue (a
            // cancelled analysis, a cleared failure) and need requesting.
            if isLoading == false {
                store.loadFormatIfNeeded(store.viewMode, isCompare: false)
            }
        }
    }
    
    // MARK: - Pane router
    
    @ViewBuilder
    private func folderDetail(folder: FolderContents) -> some View {
        if folder.isScanning {
            FolderMessage(
                icon: "folder",
                title: "Reading \(folder.name)…",
                message: "Looking for media files in this folder.",
                showsProgress: true
            )
        } else if folder.items.isEmpty {
            FolderMessage(
                icon: "folder.badge.questionmark",
                title: "No media files",
                message: "Nothing in \(folder.name) looks like video, audio or an image.",
                showsProgress: false
            )
        } else if let file = store.currentFile {
            paneContent(file: file)
        }
    }
    
    @ViewBuilder
    private func paneContent(file: MediaFile) -> some View {
        let state = ContentState.resolve(file: file, mode: store.viewMode)
        
        Group {
            if state.isReady {
                readyContent(file: file)
                    .transition(.opacity)
            } else {
                ContentStateView(state: state, isCompare: false)
                    .transition(.opacity)
            }
        }
        .smiAnimation(SMI.Motion.fade, value: state)
    }
    
    private var isSearchActive: Bool {
        store.showSearchBar && !store.searchQuery.isEmpty
    }
    
    @ViewBuilder
    private func readyContent(file: MediaFile) -> some View {
        VStack(spacing: 0) {
            // The checksum strip. Above the view's content rather than inside
            // Easy View, so it survives the switch to the search and diff
            // variants and stays visible on the text views too. A checksum
            // that vanishes when you change view is one you cannot watch
            // finish.
            //
            // Renders nothing once the digest is ready — at that point the
            // store has injected it into the General track, where it behaves
            // like any other field.
            ChecksumCard(isCompare: false)
                .padding(.horizontal, SMI.Spacing.xLarge)
                .padding(.top, SMI.Spacing.large)
            
            tabContent(file: file)
        }
    }
    
    @ViewBuilder
    private func tabContent(file: MediaFile) -> some View {
        switch store.viewMode {
            
        case .easy:
            if isSearchActive {
                FilterableEasyView(file: file)
            } else {
                EasyView(file: file)
            }
            
        case .text:
            textualContent(file.rawText)
            
        case .rawText:
            textualContent(file.rawTextFull)
            
        case .xml:
            textualContent(file.rawXML, language: .xml)
            
        case .json:
            textualContent(file.rawJSON, language: .json)
            
        case .html:
            if let content = file.rawHTML {
                HTMLView(htmlString: content)
            }
        }
    }
    
    @ViewBuilder
    private func textualContent(_ content: String?, language: CodeLanguage? = nil) -> some View {
        if let content {
            if isSearchActive {
                FilterableRawTextView(content: content, language: language)
            } else {
                RawTextView(content: content, language: language)
            }
        }
    }
}

// MARK: - Reusable glass placeholder
//
// Retained for any caller outside the state system. New code should prefer
// ContentStateView so states stay consistent.

// MARK: - Empty state

/// What the empty screen shows. All three are Privacy settings: what you
/// favour, what you opened lately and how long you spend are your own
/// business, and someone glancing at your screen need not see any of them.
enum EmptyScreenPreference {
    static let showsFavoritesKey = "emptyScreenShowsFavorites"
    static let showsRecentsKey = "emptyScreenShowsRecents"
    static let showsTimeSpentKey = "emptyScreenShowsTimeSpent"
}

struct EmptyStateView: View {
    @EnvironmentObject var store: MediaStore
    @State private var hovered = false
    @AppStorage(EmptyScreenPreference.showsFavoritesKey) private var showsFavorites = true
    @AppStorage(EmptyScreenPreference.showsRecentsKey) private var showsRecents = true
    @AppStorage(EmptyScreenPreference.showsTimeSpentKey) private var showsTimeSpent = true
    
    private let chipColumns = [
        GridItem(.adaptive(minimum: 170, maximum: 260), spacing: SMI.Spacing.small)
    ]
    
    /// Favorites still on disk. A missing one stays in File → Favorites,
    /// marked, but a chip that cannot open would only be clutter here.
    private var visibleFavorites: [URL] {
        Array(store.favoriteURLs.filter(store.favoriteExists).prefix(Self.chipLimit))
    }
    
    /// Nine of each at most — three rows of three — so the screen stays a
    /// starting point rather than a file browser. The rest are a click away
    /// in File › Open Recent and File › Favorites.
    private static let chipLimit = 9
    
    private var visibleRecents: [URL] {
        Array(store.recentFileURLs.prefix(Self.chipLimit))
    }
    
    var body: some View {
        // Scrolls when the window is too short for everything, and is
        // centred when it is not.
        GeometryReader { geometry in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
    
    private var content: some View {
        VStack(spacing: SMI.Spacing.xxLarge) {
            
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.brandViolet.opacity(0.18),
                                Color.brandBlue.opacity(0.06)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 52
                        )
                    )
                    .frame(width: 104, height: 104)
                    .scaleEffect(hovered ? 1.06 : 1.0)
                
                Image(systemName: "film.stack")
                    .font(.system(size: 44, weight: .thin))
                    .foregroundStyle(LinearGradient.brandBlueViolet)
                    .scaleEffect(hovered ? 1.04 : 1.0)
            }
            .smiAnimation(SMI.Motion.flourish, value: hovered)
            // Illustration. It repeats what the headline underneath already
            // says, so it stays silent.
            .smiDecorativeChrome()
            
            VStack(spacing: SMI.Spacing.small) {
                Text("Drop a media file to get started")
                    .font(SMI.Typo.display)
                    .foregroundStyle(.primary)
                
                Text("Or press ⌘O, or use the Open button above.")
                    .font(SMI.Typo.body)
                    .foregroundStyle(.secondary)
            }
            
            Button("Open File…") { store.openFilePicker() }
                .buttonStyle(.borderedProminent)
                .tint(.brandViolet)
                .controlSize(.large)
            
            // ── Favorites ───────────────────────────────────────────────────
            if showsFavorites && !visibleFavorites.isEmpty {
                VStack(spacing: SMI.Spacing.medium) {
                    GlassSectionHeader(title: "Favorites", icon: "star")
                        .frame(maxWidth: 600)
                    
                    LazyVGrid(columns: chipColumns, spacing: SMI.Spacing.small) {
                        ForEach(visibleFavorites, id: \.self) { url in
                            RecentFileChip(url: url, store: store, isFavoriteChip: true) {
                                store.openURL(url)
                            }
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: 600)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
            
            // ── Recent files ───────────────────────────────────────────────
            if showsRecents && !store.recentFileURLs.isEmpty {
                VStack(spacing: SMI.Spacing.medium) {
                    GlassSectionHeader(title: "Recent Files", icon: "clock.arrow.circlepath")
                        .frame(maxWidth: 600)
                    
                    LazyVGrid(columns: chipColumns, spacing: SMI.Spacing.small) {
                        ForEach(visibleRecents, id: \.self) { url in
                            RecentFileChip(url: url, store: store) {
                                store.openURL(url)
                            }
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: 600)
                    
                    // A bordered, regular-size button rather than plain caption
                    // text: the old 11pt label was a hit target users kept
                    // missing.
                    Button(role: .destructive) {
                        store.clearRecentFiles()
                    } label: {
                        Label("Clear Recents", systemImage: "trash")
                            .font(SMI.Typo.label)
                            .padding(.horizontal, SMI.Spacing.small)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.top, SMI.Spacing.tight)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
            
            // ── Time spent ──────────────────────────────────────────────────
            //
            // In the flow, last, rather than pinned over the bottom of the
            // window: pinned, it sat on top of whatever had scrolled beneath
            // it — Clear Recents, at ordinary window sizes. Part of the same
            // column, it can never cover a button; at most it scrolls.
            if showsTimeSpent {
                TimeSpentCard(usage: store.usage)
                    .frame(maxWidth: 600)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .smiAnimation(SMI.Motion.smooth, value: showsTimeSpent)
        .smiAnimation(SMI.Motion.smooth, value: visibleFavorites)
        .smiAnimation(SMI.Motion.smooth, value: showsFavorites)
        .smiAnimation(SMI.Motion.smooth, value: showsRecents)
        // Driven by the list itself rather than by each call site, so every
        // way an entry can leave — Clear Recents here, in the menu bar or in
        // Settings, Remove from Recents, Move to Trash — animates the same way.
        .smiAnimation(SMI.Motion.smooth, value: store.recentFileURLs)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, SMI.Spacing.huge)
        .padding(.vertical, SMI.Spacing.xLarge)
        .onHover { hovered = $0 }
        .contentShape(Rectangle())
        .onTapGesture { store.openFilePicker() }
        // `onTapGesture` on a bare view is invisible to VoiceOver and
        // unreachable from the keyboard, so clicking anywhere in the empty
        // state to open the picker gets an explicit accessibility action too.
        // The Open File… button above remains the obvious route.
        .accessibilityAction(named: "Open a file") {
            store.openFilePicker()
        }
    }
}

// MARK: - Time spent card

/// How long you have spent in SwiftMediaInfo, and something to make of it.
///
/// One fact at a time, changing every so often with a soft cross-fade, or
/// straight away with the back and forward arrows. The order is shuffled each launch so
/// the same fact does not always come first.
struct TimeSpentCard: View {
    @ObservedObject var usage: UsageTracker
    
    @State private var order = FunFacts.all.shuffled()
    @State private var index = 0
    @State private var hoveredButton: Int? = nil
    
    /// Long enough to read a sentence twice.
    private let rotation: Duration = .seconds(14)
    
    /// Wraps both ways, so going back from the first fact reaches the last.
    private var fact: FunFact {
        let count = order.count
        return order[((index % count) + count) % count]
    }
    
    var body: some View {
        HStack(spacing: SMI.Spacing.medium) {
            // The total.
            HStack(spacing: SMI.Spacing.medium - 2) {
                Image(systemName: "hourglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(LinearGradient.brandBlueViolet)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.brandViolet.opacity(0.12)))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("TIME IN SWIFTMEDIAINFO")
                        .font(SMI.Typo.micro)
                        .foregroundStyle(.secondary)
                    Text(usage.formattedTotal)
                        .font(SMI.Typo.bodyStrong)
                        .contentTransition(.numericText())
                }
            }
            .fixedSize()
            
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: 32)
                .smiDecorativeChrome()
            
            // The fact.
            HStack(alignment: .center, spacing: SMI.Spacing.small) {
                Image(systemName: fact.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(fact.tint)
                    .frame(width: 18)
                
                Text(fact.text(usage.totalSeconds))
                    .font(SMI.Typo.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(fact.id)
                    .transition(.opacity)
                
                HStack(spacing: SMI.Spacing.tight) {
                    stepButton(-1, icon: "arrow.backward.circle", help: "Previous fact")
                    stepButton(1, icon: "arrow.forward.circle", help: "Next fact")
                }
            }
            .smiAnimation(SMI.Motion.fade, value: fact.id)
        }
        .padding(.horizontal, SMI.Spacing.large)
        .padding(.vertical, SMI.Spacing.medium)
        .liquidGlass(cornerRadius: SMI.Radius.card, tint: .brandViolet, borderOpacity: 0.2)
        .smiAnimation(SMI.Motion.smooth, value: usage.formattedTotal)
        // Rotates on its own while the card is on screen; stops when it is not.
        .task(id: index) {
            try? await Task.sleep(for: rotation)
            guard !Task.isCancelled else { return }
            advance()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Time spent in SwiftMediaInfo: \(usage.formattedTotal)")
    }
    
    private func advance(by step: Int = 1) {
        smiWithAnimation(SMI.Motion.fade) {
            index += step
        }
    }
    
    private func stepButton(_ step: Int, icon: String, help: String) -> some View {
        Button {
            advance(by: step)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(hoveredButton == step ? Color.brandViolet : Color.secondary)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredButton = $0 ? step : (hoveredButton == step ? nil : hoveredButton) }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Recent file chip

struct RecentFileChip: View {
    let url: URL
    /// Passed in rather than read from the environment: `contextMenu` builds
    /// its content in a detached presentation context, and an environment
    /// object does not reliably survive the trip. Observed, so the "open in a
    /// tab" marker follows tabs opening and closing.
    @ObservedObject var store: MediaStore
    /// Shown under Favorites: a star rather than a file icon, and the menu
    /// removes it from Favorites rather than from Recents.
    var isFavoriteChip = false
    let action: () -> Void
    
    @State private var hovered = false
    
    /// Already open in a tab — typically one just opened with a middle-click.
    private var isOpenInTab: Bool {
        store.tabs.contains { $0.identityURL == url.standardizedFileURL }
    }
    
    private var fileIcon: String {
        FileTabBar.symbol(for: url)
    }
    
    /// Recents can point at files that have since moved or been deleted.
    /// Marking them rather than hiding them keeps the list stable — a file on
    /// an unmounted drive shouldn't silently vanish from history.
    private var isReachable: Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: SMI.Spacing.small) {
                Image(systemName: isReachable ? (isFavoriteChip ? "star.fill" : fileIcon) : "questionmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(
                        isReachable
                        ? (isFavoriteChip ? Color.brandAmber : Color.brandViolet.opacity(0.8))
                        : Color.secondary.opacity(0.5)
                    )
                    .frame(width: 18)
                
                Text(url.lastPathComponent)
                    .font(SMI.Typo.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isReachable ? .primary : .secondary)
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SMI.Spacing.medium - 2)
            .padding(.vertical, SMI.Spacing.snug + 1)
            .background(
                RoundedRectangle(cornerRadius: SMI.Radius.control, style: .continuous)
                    .fill(
                        hovered
                        ? Color.brandViolet.opacity(0.12)
                        : Color.primary.opacity(0.05)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: SMI.Radius.control, style: .continuous)
                            .strokeBorder(
                                Color.brandViolet.opacity(hovered ? 0.30 : 0.10),
                                lineWidth: 0.7
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle(scale: 0.98))
        // Middle-click opens in a background tab, as in a browser, so
        // several recents can be queued without leaving this screen.
        .onMiddleClick {
            guard isReachable else { return }
            smiWithAnimation(SMI.Motion.smooth) { store.openInBackgroundTab(url) }
        }
        .overlay(alignment: .topTrailing) {
            if isOpenInTab {
                Circle()
                    .fill(Color.brandViolet)
                    .frame(width: 7, height: 7)
                    .padding(5)
                    .transition(.scale.combined(with: .opacity))
                    .help("Open in a tab")
                    .accessibilityHidden(true)
            }
        }
        .smiAnimation(SMI.Motion.snap, value: isOpenInTab)
        .onHover { hovered = $0 }
        .smiAnimation(SMI.Motion.fade, value: hovered)
        .help(isReachable
              ? "\(url.lastPathComponent)\nMiddle-click to open in a background tab"
              : "\(url.lastPathComponent) — not currently available")
        // A missing file is marked by a question-mark glyph and grey text,
        // neither of which is audible. The state goes into the spoken value
        // too, so the chip says why it will not open.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(url.lastPathComponent)
        .accessibilityValue(isReachable ? (isOpenInTab ? "Open in a tab" : "") : "Not currently available")
        .accessibilityHint(isReachable ? "Opens this file" : "This file has moved or been deleted")
        .accessibilityAddTraits(.isButton)
        // Rename and Move to Trash are deliberately absent: a chip
        // points at a file that is usually *not* the one on screen, and a
        // destructive action two rows below "Open" in a list of history is a
        // mis-click waiting to happen. Removing the entry is offered instead,
        // which affects the list and not the disk.
        .contextMenu {
            FileActionsMenuItems(
                store: store,
                url: url,
                isCompare: false,
                excluding: [.rename, .trash]
            )
            
            Divider()
            
            if isFavoriteChip {
                Button(role: .destructive) {
                    store.removeFavorite(url)
                } label: {
                    Label("Remove from Favorites", systemImage: "star.slash")
                }
            } else {
                // Star or unstar straight from the list.
                let starred = store.isFavorite(url)
                Button {
                    store.toggleFavorite(url)
                } label: {
                    Label(starred ? "Remove from Favorites" : "Add to Favorites",
                          systemImage: starred ? "star.slash" : "star")
                }
                
                Button(role: .destructive) {
                    store.removeFromRecents(url)
                } label: {
                    Label("Remove from Recents", systemImage: "xmark.circle")
                }
            }
        }
    }
}
