//
//  SearchBarView.swift
//  SwiftMediaInfo
//
//  A floating search/filter bar that overlays the content area.
//  Works across all view modes. Activated with ⌘F.
//

import SwiftUI
import AppKit

// MARK: - Search bar overlay (positioned at top of content area)

struct SearchBarOverlay: View {
    @EnvironmentObject var store: MediaStore
    
    var body: some View {
        if store.showSearchBar {
            VStack {
                SearchBar()
                    .transition(.move(edge: .top).combined(with: .opacity))
                Spacer()
            }
            .padding(.top, 76) // below toolbar
            .zIndex(100)
        }
    }
}

// MARK: - Search bar

struct SearchBar: View {
    @EnvironmentObject var store: MediaStore
    @FocusState private var isFocused: Bool
    
    /// Set once the user clicks a navigation arrow, after which the field stops
    /// grabbing focus back.
    @State private var hasSteppedThroughResults = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.brandViolet.opacity(0.7))
                .frame(width: 48)
            
            // Text field
            TextField("Search fields, values, text…", text: $store.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($isFocused)
                .onSubmit { navigateNext() }
            
            // Match count badge
            if !store.searchQuery.isEmpty {
                matchCountBadge
                    .transition(.scale.combined(with: .opacity))
            }
            
            // Navigation arrows
            if store.searchMatchCount > 1 {
                HStack(spacing: 4) {
                    navButton(icon: "chevron.up") {
                        stepThroughResults()
                        navigatePrevious()
                    }
                    navButton(icon: "chevron.down") {
                        stepThroughResults()
                        navigateNext()
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
            
            // Close button
            Button(action: {
                store.toggleSearchBar()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.brandViolet.opacity(0.12), radius: 20, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.brandViolet.opacity(0.25),
                            Color.brandBlue.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
        )
        .frame(maxWidth: 640)
        .padding(.horizontal, 20)
        .onAppear {
            // A frame's delay. Setting focus in the same pass the field is
            // created is unreliable — the field may not be in the responder
            // chain yet, and the request is dropped silently.
            DispatchQueue.main.async { isFocused = true }
        }
        // Typing keeps focus. Stepping through results with the arrows moves
        // focus to the button that was clicked, which is correct — that is the
        // user deliberately leaving the field — so focus is only reclaimed
        // while the query itself is being edited.
        .onChange(of: store.searchQuery) { _, _ in
            guard !hasSteppedThroughResults else { return }
            isFocused = true
        }
        .onChange(of: store.showSearchBar) { _, shown in
            if shown {
                hasSteppedThroughResults = false
                DispatchQueue.main.async { isFocused = true }
            }
        }
        // Escape is handled by ContentView's key monitor rather than here.
        // `onExitCommand` only fires when the escape reaches this view, and
        // while the text field holds focus the field editor consumes it first
        // — which is exactly when you most want to close the bar.
        .animation(.easeInOut(duration: 0.15), value: store.searchQuery)
        .animation(.easeInOut(duration: 0.15), value: store.searchMatchCount)
    }
    
    // MARK: - Match count badge
    
    private var matchCountBadge: some View {
        Group {
            if store.searchMatchCount > 0 {
                Text("\(store.searchMatchIndex + 1)/\(store.searchMatchCount)")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.brandViolet)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.brandViolet.opacity(0.1))
                    )
            } else {
                Text("No matches")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.red.opacity(0.08))
                    )
            }
        }
        .padding(.trailing, 6)
    }
    
    // MARK: - Navigation button
    
    private func navButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.brandViolet)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(Color.brandViolet.opacity(0.08))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Navigate
    
    /// Hand keyboard focus back to the window.
    ///
    /// Clicking a chevron used to leave the text field as first responder — a
    /// plain SwiftUI button does not take focus on macOS. That meant the arrow
    /// keys still went to the field (where they move the insertion point) and
    /// the window-level monitor that steps through matches deliberately stood
    /// aside for them. So clicking once with the mouse and then reaching for
    /// the arrow keys did nothing at all.
    ///
    /// Clearing @FocusState is not enough on its own — SwiftUI will not always
    /// resign an AppKit field editor from a false — so the window is told
    /// directly. Typing does not reclaim focus afterwards, which is the point:
    /// you have deliberately left the field.
    private func stepThroughResults() {
        hasSteppedThroughResults = true
        isFocused = false
        
        // RunLoop rather than DispatchQueue, for the same reason as the rename
        // field: `makeFirstResponder` reaches into AppKit internals that GCD
        // reports as a priority inversion no matter what QoS the block is
        // given. The run loop carries no priority to invert.
        RunLoop.main.perform(inModes: [.common]) {
            guard let window = NSApp.keyWindow,
                  window.firstResponder is NSTextView else { return }
            window.makeFirstResponder(window.contentView)
        }
    }
    
    private func navigateNext() {
        guard store.searchMatchCount > 0 else { return }
        store.searchMatchIndex = (store.searchMatchIndex + 1) % store.searchMatchCount
    }
    
    private func navigatePrevious() {
        guard store.searchMatchCount > 0 else { return }
        store.searchMatchIndex = (store.searchMatchIndex - 1 + store.searchMatchCount) % store.searchMatchCount
    }
}

// MARK: - Filterable text view (replaces RawTextView when search is active)

struct FilterableRawTextView: NSViewRepresentable {
    let content: String
    /// Which pane this instance is rendering, so dropped files route correctly.
    var dropTarget: FileDropTarget = .main
    @EnvironmentObject var store: MediaStore
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var lastQuery: String = ""
        var lastIndex: Int = -1
        var lastFontSize: Double = 0
        var lastContent: String = ""
        var matchRanges: [NSRange] = []
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        // Shared builder: read-only, transparent, and able to accept dropped
        // files rather than swallowing them.
        let scrollView = FileDropScrollView.make(richText: true)
        scrollView.configureDrop(target: dropTarget, store: store)
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = FileDropScrollView.textView(in: scrollView) else { return }
        
        (scrollView as? FileDropScrollView)?.configureDrop(target: dropTarget, store: store)
        
        let query = store.searchQuery
        let coord = context.coordinator
        let fontSize = store.fontSize
        
        // Only rebuild attributed string when content, query, font size, or active index changes
        let indexChanged = coord.lastIndex != store.searchMatchIndex
        let queryChanged = coord.lastQuery != query
        let fontChanged  = coord.lastFontSize != fontSize
        let contentChanged = coord.lastContent != content
        
        guard queryChanged || fontChanged || contentChanged || indexChanged else { return }
        
        let font  = NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            font,
            .foregroundColor: NSColor.labelColor
        ]
        
        let attrStr = NSMutableAttributedString(string: content, attributes: attrs)
        
        // Recompute ranges only when query or content changes
        if queryChanged || contentChanged || fontChanged {
            coord.lastContent = content
            coord.lastFontSize = fontSize
            
            if !query.isEmpty {
                // Try exact case-insensitive match first
                var ranges = findNSRanges(of: query, in: content)
                
                // If no exact matches, try space-normalized search
                if ranges.isEmpty {
                    let qNorm = query.lowercased().replacingOccurrences(of: " ", with: "")
                    // Build index map from normalized to original positions
                    let lower = content.lowercased()
                    var indexMap: [Int] = [] // normalizedOffset -> originalOffset
                    for (i, char) in lower.enumerated() {
                        if char != " " {
                            indexMap.append(i)
                        }
                    }
                    let normalized = lower.replacingOccurrences(of: " ", with: "")
                    let nsNorm = normalized as NSString
                    var searchRange = NSRange(location: 0, length: nsNorm.length)
                    
                    while searchRange.location < nsNorm.length {
                        let found = nsNorm.range(of: qNorm, options: [], range: searchRange)
                        if found.location == NSNotFound { break }
                        
                        let origStart = found.location < indexMap.count ? indexMap[found.location] : found.location
                        let origEndIdx = found.location + found.length - 1
                        let origEnd = origEndIdx < indexMap.count ? indexMap[origEndIdx] + 1 : origStart + found.length
                        
                        ranges.append(NSRange(location: origStart, length: origEnd - origStart))
                        searchRange.location = found.location + found.length
                        searchRange.length = nsNorm.length - searchRange.location
                    }
                }
                
                coord.matchRanges = ranges
                coord.lastQuery = query
                
                DispatchQueue.main.async {
                    self.store.searchMatchCount = ranges.count
                    if ranges.count > 0 && self.store.searchMatchIndex >= ranges.count {
                        self.store.searchMatchIndex = 0
                    }
                }
            } else {
                coord.matchRanges = []
                coord.lastQuery = ""
                DispatchQueue.main.async {
                    self.store.searchMatchCount = 0
                    self.store.searchMatchIndex = 0
                }
            }
        }
        
        // Apply highlights
        let highlightColor = NSColor(Color.brandGreen.opacity(0.3))
        let activeColor    = NSColor(Color.brandGreen.opacity(0.6))
        
        for (idx, range) in coord.matchRanges.enumerated() {
            if idx == store.searchMatchIndex {
                attrStr.addAttribute(.backgroundColor, value: activeColor, range: range)
            } else {
                attrStr.addAttribute(.backgroundColor, value: highlightColor, range: range)
            }
        }
        
        textView.textStorage?.setAttributedString(attrStr)
        
        // Only scroll when index actually changed
        if indexChanged {
            coord.lastIndex = store.searchMatchIndex
            if !coord.matchRanges.isEmpty && store.searchMatchIndex < coord.matchRanges.count {
                textView.scrollRangeToVisible(coord.matchRanges[store.searchMatchIndex])
            }
        }
    }
}

// MARK: - NSRange search helper

private func findNSRanges(of query: String, in content: String) -> [NSRange] {
    let searchString = content as NSString
    var ranges: [NSRange] = []
    var searchRange = NSRange(location: 0, length: searchString.length)
    
    while searchRange.location < searchString.length {
        let found = searchString.range(of: query, options: .caseInsensitive, range: searchRange)
        if found.location == NSNotFound { break }
        ranges.append(found)
        searchRange.location = found.location + found.length
        searchRange.length = searchString.length - searchRange.location
    }
    return ranges
}

// MARK: - Filterable Easy View (wraps EasyView with search filtering)

struct FilterableEasyView: View {
    let file: MediaFile
    @EnvironmentObject var store: MediaStore
    
    /// Inject a guaranteed "FileName" field at the top of the General track.
    private func tracksWithInjectedFields(_ tracks: [MediaTrack]) -> [MediaTrack] {
        tracks.map { track in
            guard track.type == "General" else { return track }
            var t = track
            let fullName = file.url.lastPathComponent
            if let index = t.fields.firstIndex(where: { $0.key == "FileName" }) {
                // MediaInfo drops the extension; put it back.
                t.fields[index] = (key: "FileName", value: fullName)
            } else {
                t.fields.insert((key: "FileName", value: fullName), at: 0)
            }
            return t
        }
    }
    
    /// Resolve the same easy fields that TrackCard would display, then apply friendly labels
    private func resolvedEasyFields(for track: MediaTrack) -> [(key: String, value: String)] {
        let fields = EasyFields.resolve(for: track)
        return fields.map { (key: FieldFormat.friendlyLabel($0.key), value: $0.value) }
    }
    
    /// The track, field and occurrence holding the currently selected match.
    ///
    /// Built by walking exactly the same fields in the same order the counter
    /// does, so the index the search bar shows and the one highlighted on
    /// screen always refer to the same occurrence.
    private func activeMatchLocation() -> (trackID: UUID, fieldKey: String, occurrence: Int)? {
        let query = store.searchQuery.lowercased()
        guard !query.isEmpty else { return nil }
        
        let index = store.searchMatchIndex
        var seen = 0
        
        for track in tracksWithInjectedFields(filteredTracks) {
            for field in EasyFields.resolve(for: track) {
                let label = FieldFormat.friendlyLabel(field.key)
                let hits = FieldFormat.occurrences(of: query, in: label)
                + FieldFormat.occurrences(of: query, in: field.value)
                if hits == 0 { continue }
                
                if index < seen + hits {
                    return (track.id, field.key, index - seen)
                }
                seen += hits
            }
        }
        
        return nil
    }
    
    /// Which track card holds the nth match.
    ///
    /// Matches are counted as text occurrences, and a single field can contain
    /// several, so the mapping is built by walking the same fields in the same
    /// order the counter does and repeating a track's id once per occurrence
    /// inside it. Both must agree, or the counter and the scrolling would
    /// disagree about what "match 4 of 9" means.
    private func trackID(forMatchIndex index: Int) -> UUID? {
        activeMatchLocation()?.trackID
    }
    
    /// Count actual text occurrences of the query across displayed easy fields
    private func countMatches(in tracks: [MediaTrack], query: String) -> Int {
        let q = query.lowercased()
        var count = 0
        for track in tracks {
            let fields = resolvedEasyFields(for: track)
            for field in fields {
                count += FieldFormat.occurrences(of: q, in: field.key)
                count += FieldFormat.occurrences(of: q, in: field.value)
            }
        }
        return count
    }
    
    /// Filter tracks to only those with matching easy fields
    private var filteredTracks: [MediaTrack] {
        guard !store.searchQuery.isEmpty else { return file.tracks }
        let q = store.searchQuery
        
        return file.tracks.filter { track in
            let fields = resolvedEasyFields(for: track)
            return FieldFormat.fuzzyContains(query: q, in: track.displayTitle) ||
            fields.contains(where: {
                FieldFormat.fuzzyContains(query: q, in: $0.key) ||
                FieldFormat.fuzzyContains(query: q, in: $0.value)
            })
        }
    }
    
    var body: some View {
        let tracks = tracksWithInjectedFields(filteredTracks)
        let matchCount = store.searchQuery.isEmpty ? 0 : countMatches(in: tracks, query: store.searchQuery)
        let activeMatch = activeMatchLocation()
        
        Group {
            if tracks.isEmpty && !store.searchQuery.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                    Text("No fields matching \"\(store.searchQuery)\"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if file.tracks.isEmpty {
                EasyView(file: file)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(tracks) { track in
                                TrackCard(
                                    track: track,
                                    highlightQuery: store.searchQuery,
                                    fileURL: file.url,
                                    activeMatch: activeMatch?.trackID == track.id
                                    ? (activeMatch!.fieldKey, activeMatch!.occurrence)
                                    : nil
                                )
                                .id(track.id)
                            }
                        }
                        .padding(20)
                    }
                    // Stepping through matches with ↑ / ↓ moved the counter but
                    // not the view, so a match in a track further down the list
                    // was "selected" while staying off screen. The other tabs
                    // scroll because NSTextView does it for them; this list had
                    // nothing doing the equivalent.
                    .onChange(of: store.searchMatchIndex) { _, index in
                        guard let target = trackID(forMatchIndex: index) else { return }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                    }
                }
            }
        }
        .onAppear { store.searchMatchCount = matchCount }
        .onChange(of: matchCount) { _, newVal in store.searchMatchCount = newVal }
    }
}

// Global helpers removed — now using EasyFields, FieldFormat, and DiffHelper from MediaInfoUtilities.swift
