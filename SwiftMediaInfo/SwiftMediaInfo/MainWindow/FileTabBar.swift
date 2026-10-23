//
//  FileTabBar.swift
//  SwiftMediaInfo
//
//  The strip of open files under the toolbar: Safari-style tabs sharing the
//  width (scrolling past a minimum width), the + button, drag to reorder or
//  out to other apps, the tab context menu (close, compare, favorites), A/B
//  badges in Compare Mode, ⌘-click to compare, middle-click to close. Tab
//  operations themselves are in MediaStore+Tabs.
//
//  Always visible, even with nothing open, so the window's layout does not
//  jump the moment the first file arrives and the + button is always where
//  you left it.
//
//  Not to be confused with LiquidGlassTabBar, which picks the *view* (Easy,
//  Text, JSON…). This one picks the *file*.
//

import SwiftUI
import UniformTypeIdentifiers

struct FileTabBar: View {
    @EnvironmentObject var store: MediaStore
    @Namespace private var selection


    /// Narrowest a Safari-style tab may get before the strip scrolls instead.
    private let minimumSafariWidth: CGFloat = 150

    var body: some View {
        HStack(spacing: SMI.Spacing.small) {
            if store.tabs.isEmpty {
                Text("No open files")
                    .font(SMI.Typo.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, SMI.Spacing.snug)
                    .transition(.opacity)

                Spacer(minLength: 0)
            } else {
                GeometryReader { geo in
                    tabStrip(available: geo.size.width)
                }
            }

            newTabButton
        }
        .padding(.horizontal, SMI.Spacing.medium)
        .padding(.vertical, SMI.Spacing.snug)
        .frame(height: 40)
        .background(barBackground)
        .smiAnimation(SMI.Motion.smooth, value: store.tabs.map(\.id))
        .smiAnimation(SMI.Motion.smooth, value: store.selectedTabID)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open files")
    }

    /// Safari sets its tab strip slightly apart from the toolbar above it.
    /// Drawn whether or not anything is open, so the first tab arriving
    /// changes nothing about the bar itself.
    private var barBackground: some View {
        Color.primary.opacity(0.035)
    }

    // MARK: Strip

    private func tabStrip(available: CGFloat) -> some View {
        let count = CGFloat(store.tabStripIDs.count)
        let spacing: CGFloat = 0
        let safariWidth = max(minimumSafariWidth, (available - spacing * (count - 1)) / max(count, 1))

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(Array(store.tabStripIDs.enumerated()), id: \.element) { index, id in
                        if let tab = store.tabs.first(where: { $0.id == id }) {
                            fileTab(tab, index: index, safariWidth: safariWidth)
                        } else if id == store.newTab?.id {
                            newTabItem(id: id, index: index, safariWidth: safariWidth)
                        }
                    }
                }
                .padding(.vertical, 1)
                // Fills the bar when the tabs fit; scrolls when they do not.
                .frame(minWidth: available, alignment: .leading)
            }
            // A dragged tab released past the last one still has to clear the
            // dragging state, or it would stay half-transparent.
            .onDrop(of: [.fileURL], isTargeted: nil) { _ in
                guard store.draggingTabID != nil else { return false }
                store.endTabDrag()
                return true
            }
            .onChange(of: store.selectedTabID) { _, id in
                guard let id else { return }
                smiWithAnimation(SMI.Motion.smooth) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func fileTab(_ tab: DocumentTab, index: Int, safariWidth: CGFloat) -> some View {
        FileTabItem(
            tabID: tab.id,
            fileName: tab.title,
            url: tab.identityURL,
            isLoading: tab.file.isLoading,
            hasProblem: tab.file.loadError.map { !$0.isCancellation } ?? false,
            position: index + 1,
            count: store.tabStripIDs.count,
            isSelected: tab.id == store.selectedTabID,
            compareRole: compareRole(of: tab.id),
            isFavorite: store.isFavorite(tab.identityURL),
            safariWidth: safariWidth,
            showsSeparator: showsSeparator(after: index),
            namespace: selection
        )
        .id(tab.id)
        .opacity(store.draggingTabID == tab.id ? 0.5 : 1)
        // The drag carries the tab's actual file
        // (the folder, for a folder tab), so dropping it on
        // the Dock or another app opens the original. Inside
        // the bar the same drag reorders: which tab is moving
        // is known from the store, not from the payload.
        .onDrag {
            store.beginTabDrag(tab.id)
            // A file URL, not the file's contents: the app
            // receiving it opens the original in place, never
            // a copy made for the drag.
            return NSItemProvider(object: tab.identityURL as NSURL)
        }
        .onDrop(
            of: [.fileURL],
            delegate: TabReorderDropDelegate(target: tab.id, store: store)
        )
        .transition(
            .scale(scale: 0.85, anchor: .leading)
            .combined(with: .opacity)
        )
    }

    /// The empty tab ⌘T opens. Looks like any other tab; it just has
    /// no file to drag, star or offer a context menu for.
    private func newTabItem(id: UUID, index: Int, safariWidth: CGFloat) -> some View {
        FileTabItem(
            tabID: id,
            fileName: "New Tab",
            url: URL(fileURLWithPath: "/"),
            isLoading: false,
            hasProblem: false,
            position: index + 1,
            count: store.tabStripIDs.count,
            isSelected: id == store.selectedTabID,
            compareRole: nil,
            isFavorite: false,
            safariWidth: safariWidth,
            showsSeparator: showsSeparator(after: index),
            namespace: selection,
            isNewTab: true
        )
        .id(id)
        .transition(
            .scale(scale: 0.85, anchor: .leading)
            .combined(with: .opacity)
        )
    }

    /// Safari draws a hairline between neighbouring tabs, but never beside
    /// a raised one — the selected tab, or File B — whose own shape already
    /// separates it.
    private func showsSeparator(after index: Int) -> Bool {
        let ids = store.tabStripIDs
        guard index < ids.count - 1 else { return false }
        let raised = [ids[index], ids[index + 1]].contains {
            $0 == store.selectedTabID || compareRole(of: $0) != nil
        }
        return !raised
    }

    private func compareRole(of id: UUID) -> CompareRole? {
        guard store.isCompareMode else { return nil }
        if id == store.selectedTabID { return .fileA }
        if id == store.compareTabID  { return .fileB }
        return nil
    }

    /// Favorites, recent files, then "Choose a File…" — so reopening something
    /// you had a moment ago is one click, not a trip through a file panel.
    /// Click: a New Tab showing the start screen, as in Safari.
    /// Right-click: favorites, recent files and "Choose a File…".
    private var newTabButton: some View {
        Button {
            store.openNewTab()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .contextMenu { newTabMenuItems }
        .help("New Tab (⌘T) — right-click for favorites and recent files")
        .accessibilityLabel("New Tab")
        .accessibilityHint("Opens an empty tab. The context menu lists favorites and recent files.")
    }
    
    @ViewBuilder
    private var newTabMenuItems: some View {
        // Favorites first — they are the files you chose to keep at hand.
        // Ones already open are still listed; choosing one switches to it.
        let favorites = store.favoriteURLs.filter(store.favoriteExists)
        FoldingMenuSection(title: "Favorites", urls: favorites) { url in
            Button {
                store.openURL(url)
            } label: {
                Label(url.lastPathComponent, systemImage: "star.fill")
            }
        }
        
        // Every recent file, favorite or not — each list is complete.
        let recents = store.recentCompareCandidates
        FoldingMenuSection(title: "Recent Files", urls: recents) { url in
            Button {
                store.openURL(url)
            } label: {
                Label(url.lastPathComponent, systemImage: FileTabBar.symbol(for: url))
            }
        }
        
        if !favorites.isEmpty || !recents.isEmpty { Divider() }
        
        Button {
            store.openFilePicker()
        } label: {
            Label("Choose a File…", systemImage: "folder")
        }
    }
}

/// Which side of a comparison a tab is on.
enum CompareRole {
    case fileA, fileB

    var letter: String { self == .fileA ? "A" : "B" }
    /// The same colours Compare Mode's panes and status bar use.
    var tint: Color { self == .fileA ? .brandBlue : .brandPink }
}

// MARK: - One tab

private struct FileTabItem: View {
    // Plain values rather than the tab itself. MediaFile's equality compares
    // identity only, so SwiftUI judged a tab whose file had just finished
    // loading to be unchanged and left its spinner turning.
    let tabID: UUID
    let fileName: String
    let url: URL
    let isLoading: Bool
    /// A failure worth flagging on the tab itself, so a broken file is visible
    /// without switching to it. Cancellation is the user's own choice and is
    /// not flagged.
    let hasProblem: Bool
    let position: Int
    let count: Int
    let isSelected: Bool
    let compareRole: CompareRole?
    let isFavorite: Bool
    let safariWidth: CGFloat
    let showsSeparator: Bool
    let namespace: Namespace.ID
    /// The empty tab ⌘T opens: no star, no file path, no context menu.
    var isNewTab: Bool = false

    @EnvironmentObject var store: MediaStore
    @State private var isHovering = false
    @State private var isHoveringClose = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    /// Room kept clear for the close button on a Safari tab, on both sides so
    /// the title stays centred.
    private let closeInset: CGFloat = 26

    var body: some View {
        content
            .background(backdrop)
            .overlay(alignment: .trailing) { separator }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // ⌘-click makes this tab File B — the quickest way to compare
            // two open files. A plain click shows it (in Compare Mode: as
            // File A).
            .onTapGesture {
                if NSEvent.modifierFlags.contains(.command) {
                    store.toggleCompare(withTab: tabID)
                } else {
                    store.selectTab(tabID)
                }
            }
            // Middle-click closes, as in every browser.
            .onMiddleClick { store.closeTab(tabID) }
            .onHover { isHovering = $0 }
            .smiAnimation(SMI.Motion.fade, value: isHovering)
            .help(isNewTab ? "New Tab" : url.path(percentEncoded: false))
            .contextMenu {
                if !isNewTab { TabContextMenu(tabID: tabID, store: store) }
            }
        // One stop per tab, announced like a native tab: name, position, and
        // whether it is the one showing.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(fileName)
            .accessibilityValue(spokenValue)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { store.selectTab(tabID) }
            .accessibilityAction(named: "Close Tab") { store.closeTab(tabID) }
            .accessibilityAction(named: isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                store.toggleFavorite(url)
            }
    }

    // MARK: Layout

    /// Safari's layout, whatever the count: tabs share the bar's width
    /// equally, icon and title centred as a pair, and the close button at the
    /// leading edge, shown on hover. One layout for one tab and for twenty, so
    /// opening a second file moves nothing — the first tab simply makes room.
    private var content: some View {
        HStack(spacing: SMI.Spacing.snug) {
            if let compareRole {
                roleBadge(compareRole)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
            leadingIcon
                .frame(width: 16, height: 16)
            title(maxWidth: safariTitleRoom - (compareRole == nil ? 0 : badgeWidth + SMI.Spacing.snug))
        }
        .smiAnimation(SMI.Motion.snap, value: compareRole)
        .padding(.horizontal, closeInset)
        .frame(width: safariWidth, height: 28)
        .overlay(alignment: .leading) {
            closeButton(visible: isHovering)
                .padding(.leading, SMI.Spacing.snug)
        }
        // The Favorites star, on the right as the close button is on
        // the left. Always there once starred; offered on hover otherwise.
        .overlay(alignment: .trailing) {
            if !isNewTab {
            FavoriteStarButton(
                isFavorite: isFavorite,
                isVisible: isFavorite || isHovering,
                fileName: fileName
            ) {
                store.toggleFavorite(url)
            }
            .padding(.trailing, SMI.Spacing.snug)
            }
        }
    }

    private let badgeWidth: CGFloat = 16

    private func roleBadge(_ role: CompareRole) -> some View {
        Text(role.letter)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: badgeWidth, height: 16)
            .background(Circle().fill(role.tint))
            .accessibilityHidden(true)
    }

    private var spokenValue: String {
        var parts = ["Tab \(position) of \(count)"]
        if let compareRole { parts.append("File \(compareRole.letter)") }
        if isFavorite { parts.append("favorite") }
        if isLoading { parts.append("analysing") }
        return parts.joined(separator: ", ")
    }

    /// What is left for the title on a Safari tab once the close button's
    /// space (kept on both sides, so the pair stays centred) and the icon are
    /// taken out.
    private var safariTitleRoom: CGFloat {
        max(safariWidth - closeInset * 2 - 16 - SMI.Spacing.snug, 40)
    }

    /// The title is exactly as wide as the name, up to the room available.
    ///
    /// Past that, only the selected tab's name and the one under the pointer
    /// scroll — every one at the same speed and in the same direction. The
    /// rest are shortened in the middle, so a bar full of long release names
    /// stays still unless you are looking at one of them.
    private func title(maxWidth: CGFloat) -> some View {
        let font = NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .medium)
        let natural = ceil((fileName as NSString).size(withAttributes: [.font: font]).width) + 2

        return MarqueeText(
            text: fileName,
            size: 13,
            weight: isSelected ? .semibold : .medium,
            style: .loop,
            isAnimated: isSelected || compareRole != nil || isHovering,
            isSecondary: !(isSelected || compareRole != nil)
        )
        .foregroundStyle(isSelected || compareRole != nil ? .primary : .secondary)
        .frame(width: min(natural, maxWidth))
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if isLoading {
            ProgressView()
                .controlSize(.mini)
                .tint(.brandViolet)
        } else if hasProblem {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(SMI.Palette.warning)
        } else if isNewTab {
            Image(systemName: "plus.square.on.square")
                .font(.system(size: 12))
                .foregroundStyle(
                    isSelected ? Color.brandViolet : Color.secondary.opacity(0.8)
                )
        } else {
            Image(systemName: FileTabBar.symbol(for: url))
                .font(.system(size: 12))
                .foregroundStyle(
                    isSelected ? Color.brandViolet : Color.secondary.opacity(0.8)
                )
        }
    }

    /// The space is always reserved, so hovering never shifts the title.
    private func closeButton(visible: Bool) -> some View {
        Button {
            store.closeTab(tabID)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isHoveringClose ? Color.primary : Color.secondary)
                .frame(width: 18, height: 18)
                .background(
                    Circle().fill(isHoveringClose ? SMI.Palette.hoverWash : .clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .onHover { isHoveringClose = $0 }
        .help("Close Tab (⌘W)")
        .accessibilityHidden(true)
    }

    // MARK: Chrome

    private let cornerRadius: CGFloat = SMI.Radius.chip + 2

    @ViewBuilder
    private var backdrop: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if isSelected {
            // One highlight that slides between tabs, the same way the view
            // picker's selection moves: a raised card, lighter than the strip
            // around it. Outlined in File A's blue while comparing.
            raisedCard(shape, tint: compareRole?.tint ?? .brandViolet)
                .matchedGeometryEffect(id: "file_tab_highlight", in: namespace)
        } else if compareRole == .fileB {
            // File B is on screen too, so it is raised as well — in its own
            // colour, so which tab is which side is never a guess.
            raisedCard(shape, tint: CompareRole.fileB.tint)
                .transition(.opacity)
        } else if isHovering {
            shape.fill(SMI.Palette.hoverWash)
        }
    }

    private func raisedCard(_ shape: RoundedRectangle, tint: Color) -> some View {
        shape
            .fill(selectedSafariFill)
            .overlay(shape.strokeBorder(tint.opacity(compareRole == nil ? 0.30 : 0.55), lineWidth: compareRole == nil ? 0.7 : 1))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 2, y: 1)
    }

    private var selectedSafariFill: Color {
        if reduceTransparency { return Color.brandViolet.opacity(0.26) }
        return colorScheme == .dark
        ? Color.white.opacity(0.10)
        : Color.white.opacity(0.75)
    }

    @ViewBuilder
    private var separator: some View {
        if showsSeparator {
            Rectangle()
                .fill(Color.primary.opacity(0.14))
                .frame(width: 1, height: 16)
                .offset(x: 0.5)
                .smiDecorativeChrome()
        }
    }
}

// MARK: - Favorite star

/// The star at the right of a tab.
///
/// Starring is the moment worth marking: the outline morphs into a filled
/// amber star, bounces, and a thin ring expands from it and fades. Unstarring
/// is quieter — the star simply empties — because taking something away
/// should not feel like a celebration. Under Reduce Motion only the fill
/// changes.
struct FavoriteStarButton: View {
    let isFavorite: Bool
    let isVisible: Bool
    let fileName: String
    let action: () -> Void

    @State private var isHovering = false
    @State private var burst = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Ring {
        var scale: CGFloat = 0.5
        var opacity: Double = 0
    }

    var body: some View {
        Button {
            if !isFavorite { burst += 1 }
            action()
        } label: {
            ZStack {
                if !reduceMotion {
                    Circle()
                        .strokeBorder(Color.brandAmber, lineWidth: 1.2)
                        .keyframeAnimator(initialValue: Ring(), trigger: burst) { content, ring in
                            content
                                .scaleEffect(ring.scale)
                                .opacity(ring.opacity)
                        } keyframes: { _ in
                            KeyframeTrack(\.scale) {
                                LinearKeyframe(0.5, duration: 0.01)
                                SpringKeyframe(1.9, duration: 0.45, spring: .smooth)
                            }
                            KeyframeTrack(\.opacity) {
                                LinearKeyframe(0.9, duration: 0.01)
                                LinearKeyframe(0, duration: 0.45)
                            }
                        }
                }

                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isFavorite ? Color.brandAmber : (isHovering ? Color.primary : Color.secondary))
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                    .symbolEffect(.bounce, value: burst)
            }
            .frame(width: 18, height: 18)
            .background(Circle().fill(isHovering ? SMI.Palette.hoverWash : .clear))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .onHover { isHovering = $0 }
        .smiAnimation(SMI.Motion.snap, value: isFavorite)
        .smiAnimation(SMI.Motion.fade, value: isVisible)
        .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityHidden(true)
    }
}

// MARK: - Context menu

/// Built as a view so the tab bar and anything else that shows a tab can
/// share it.
struct TabContextMenu: View {
    let tabID: UUID
    /// Observed, not just held. The menu is built along with the tab, and
    /// without observation it kept the tab list from the moment the tab was
    /// created — so Compare With listed no tabs and "Close Tabs to the Right"
    /// stayed disabled however many tabs were opened afterwards.
    @ObservedObject var store: MediaStore

    private var others: [DocumentTab] {
        store.tabs.filter { $0.id != tabID }
    }

    var body: some View {
        // Compare With: this tab as File A, the chosen one as File B.
        Menu("Compare With") {
            CompareChoices(
                store: store,
                tabs: others,
                onTab: { store.compare(tab: tabID, with: $0) },
                onFile: { store.compare(tab: tabID, withFileAt: $0) },
                onChooseFile: { store.compareWithPickedFile(tab: tabID) }
            )
        }

        if store.isCompareMode, tabID == store.compareTabID || tabID == store.selectedTabID {
            Button("Stop Comparing") {
                store.exitCompareMode()
            }
        }

        if let tab = store.tabs.first(where: { $0.id == tabID }) {
            Divider()

            let starred = store.isFavorite(tab.identityURL)
            Button {
                store.toggleFavorite(tab.identityURL)
            } label: {
                Label(starred ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: starred ? "star.slash" : "star")
            }
        }

        Divider()

        Button("Close Tab") {
            store.closeTab(tabID)
        }

        Button("Close All Tabs to the Right") {
            store.closeTabs(toTheRightOf: tabID)
        }
        .disabled(!store.hasTabs(toTheRightOf: tabID))

        Button("Close All Tabs to the Left") {
            store.closeTabs(toTheLeftOf: tabID)
        }
        .disabled(!store.hasTabs(toTheLeftOf: tabID))

        Button("Close All Other Tabs") {
            store.closeOtherTabs(than: tabID)
        }
        .disabled(store.tabs.count < 2)

        Divider()

        Button("New Tab to the Right") {
            store.openNewTab(toTheRightOf: tabID)
        }
    }
}

// MARK: - Compare choices

/// Open tabs, favorites, recent files, then "Choose a File…" — the same
/// sources wherever a File B is picked from a menu.
struct CompareChoices: View {
    @ObservedObject var store: MediaStore
    let tabs: [DocumentTab]
    let onTab: (UUID) -> Void
    /// A favorite or a recent file, from disk.
    let onFile: (URL) -> Void
    let onChooseFile: () -> Void

    var body: some View {
        if !tabs.isEmpty {
            Section("Open Tabs") {
                ForEach(tabs) { tab in
                    Button {
                        onTab(tab.id)
                    } label: {
                        Label(tab.file.fileName, systemImage: FileTabBar.symbol(for: tab.file.url))
                    }
                }
            }
        }

        FoldingMenuSection(title: "Favorites", urls: store.favoriteCompareCandidates) { url in
            Button {
                onFile(url)
            } label: {
                Label(url.lastPathComponent, systemImage: "star.fill")
            }
        }

        FoldingMenuSection(title: "Recent Files", urls: store.recentCompareCandidates) { url in
            Button {
                onFile(url)
            } label: {
                Label(url.lastPathComponent, systemImage: FileTabBar.symbol(for: url))
            }
        }

        Divider()

        Button {
            onChooseFile()
        } label: {
            Label("Choose a File…", systemImage: "folder")
        }
    }
}

// MARK: - Long lists

/// How many favorites or recent files a list shows before folding the rest
/// away — enough for the files used most, short enough that a menu with
/// both lists still fits on screen.
enum ListFolding {
    static let shownCount = 5
}

/// A menu section showing its first few files, with the rest in an "N More"
/// submenu that opens as the pointer reaches it. Nothing at all when the
/// list is empty.
struct FoldingMenuSection<Row: View>: View {
    let title: String
    let urls: [URL]
    @ViewBuilder let row: (URL) -> Row

    var body: some View {
        if !urls.isEmpty {
            Section(title) {
                ForEach(urls.prefix(ListFolding.shownCount), id: \.self, content: row)
                if urls.count > ListFolding.shownCount {
                    Menu {
                        ForEach(urls.dropFirst(ListFolding.shownCount), id: \.self, content: row)
                    } label: {
                        Label("\(urls.count - ListFolding.shownCount) More", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

// MARK: - Reordering

private struct TabReorderDropDelegate: DropDelegate {
    let target: UUID
    let store: MediaStore

    private var draggingTabID: UUID? { store.draggingTabID }

    /// The move happens as the dragged tab passes over another, so the bar
    /// opens a gap under the pointer instead of jumping on release.
    func dropEntered(info: DropInfo) {
        guard let dragging = draggingTabID, dragging != target else { return }

        smiWithAnimation(SMI.Motion.snap) {
            store.moveTab(dragging, to: target)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        store.endTabDrag()
        return true
    }

    /// Only tabs from this bar reorder here. A file dragged in from Finder
    /// is not a tab, and falls through to the window's own drop handling.
    func validateDrop(info: DropInfo) -> Bool {
        draggingTabID != nil
    }
}

// MARK: - File icon

extension FileTabBar {
    /// One symbol per broad kind of file. Shared with the recent-files chips
    /// so a file looks the same in both places.
    static func symbol(for url: URL) -> String {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return "folder"
        }

        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return "doc"
        }

        if type.conforms(to: .movie)  { return "film" }
        if type.conforms(to: .audio)  { return "waveform" }
        if type.conforms(to: .image)  { return "photo" }
        return "doc"
    }
}
