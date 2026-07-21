//
//  CompareView.swift
//  SwiftMediaInfo
//

import SwiftUI
import UniformTypeIdentifiers

struct CompareView: View {
    @EnvironmentObject var store: MediaStore
    @State private var isTargetedLeft  = false
    @State private var isTargetedRight = false
    
    /// Diff is only supported in easy, text, rawText
    private var diffSupported: Bool {
        [.easy, .text, .rawText].contains(store.viewMode)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ── Diff toggle bar (only when both files loaded & mode supports diff) ──
            if diffSupported &&
                store.currentFile != nil && store.compareFile != nil &&
                !(store.currentFile?.isLoading ?? true) &&
                !(store.compareFile?.isLoading ?? true) {
                diffToggleBar
            }
            
            HStack(spacing: 0) {
                
                // ── Left pane: File A ─────────────────────────────────
                ZStack {
                    VStack(spacing: 0) {
                        paneHeader(file: store.currentFile, label: "File A", isLeft: true)
                        Divider()
                        paneContent(file: store.currentFile, isCompare: false)
                    }
                    if isTargetedLeft {
                        GlassDropOverlay(color: .brandBlue)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $isTargetedLeft) { providers in
                    handleDrop(providers: providers, isLeft: true)
                }
                .animation(.spring(response: 0.25), value: isTargetedLeft)
                
                Divider()
                
                // ── Right pane: File B ────────────────────────────────
                ZStack {
                    VStack(spacing: 0) {
                        paneHeader(file: store.compareFile, label: "File B", isLeft: false)
                        Divider()
                        paneContent(file: store.compareFile, isCompare: true)
                    }
                    if isTargetedRight {
                        GlassDropOverlay(color: .brandPink)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $isTargetedRight) { providers in
                    handleDrop(providers: providers, isLeft: false)
                }
                .animation(.spring(response: 0.25), value: isTargetedRight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: store.viewMode) { _, newMode in
            store.loadFormatIfNeeded(newMode, isCompare: false)
            store.loadFormatIfNeeded(newMode, isCompare: true)
        }
    }
    
    // MARK: - Diff toggle bar
    
    private var diffToggleBar: some View {
        HStack(spacing: 10) {
            Spacer()
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    store.showDiffHighlight.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: store.showDiffHighlight
                          ? "square.split.2x1.fill"
                          : "square.split.2x1")
                    .font(.system(size: 12, weight: .medium))
                    Text(store.showDiffHighlight ? "Highlighting Differences" : "Highlight Differences")
                        .font(.system(size: 11, weight: .semibold))
                    Text("⌘D")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(store.showDiffHighlight ? Color.brandViolet : Color.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(store.showDiffHighlight
                              ? Color.brandViolet.opacity(0.12)
                              : Color.primary.opacity(0.04))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(store.showDiffHighlight
                                      ? Color.brandViolet.opacity(0.3)
                                      : Color.primary.opacity(0.08),
                                      lineWidth: 0.7)
                )
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: store.showDiffHighlight)
            
            // Legend (only when diff is active)
            if store.showDiffHighlight {
                HStack(spacing: 12) {
                    diffLegendItem(color: Color(red: 0.90, green: 0.58, blue: 0.15), label: "Modified")
                    diffLegendItem(color: .brandBlue, label: "Only in A")
                    diffLegendItem(color: .brandPink, label: "Only in B")
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
    
    private func diffLegendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Drop handler
    
    private func handleDrop(providers: [NSItemProvider], isLeft: Bool) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard
                let data = item as? Data,
                let url  = URL(dataRepresentation: data, relativeTo: nil)
            else { return }
            DispatchQueue.main.async {
                if isLeft { store.openURL(url) }
                else      { store.openCompareURL(url) }
            }
        }
        return true
    }
    
    // MARK: - Pane header
    
    @ViewBuilder
    private func paneHeader(file: MediaFile?, label: String, isLeft: Bool) -> some View {
        let accent: Color = isLeft ? .brandBlue : .brandPink
        
        HStack(spacing: 8) {
            // Badge
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(accent)
                )
            
            if let file = file {
                MarqueeText(text: file.fileName, font: .system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !file.isLoading {
                    Text(file.fileSizeString)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            } else {
                Button(isLeft ? "Open File A…" : "Open File B…") {
                    if isLeft { store.openFilePicker() }
                    else      { store.openCompareFilePicker() }
                }
                .buttonStyle(.bordered)
                .tint(accent)
                .font(.system(size: 12))
            }
            
            Spacer()
            
            if file != nil {
                Button {
                    if isLeft { store.openFilePicker() }
                    else      { store.openCompareFilePicker() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .help(isLeft ? "Choose a different File A" : "Choose a different File B")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Pane content
    
    @ViewBuilder
    private func paneContent(file: MediaFile?, isCompare: Bool) -> some View {
        if let file = file {
            if file.isLoading {
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(isCompare ? .brandPink : .brandBlue)
                    Text("Analysing \(file.fileName)…")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
            } else {
                resolvedContent(file: file, isCompare: isCompare)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        (isCompare ? Color.brandPink : Color.brandBlue).opacity(0.35)
                    )
                    .symbolEffect(.pulse)
                Text("No file selected")
                    .foregroundStyle(.secondary)
                Text("Drop a file here or click Open above")
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Route to the right view
    
    @ViewBuilder
    private func resolvedContent(file: MediaFile, isCompare: Bool) -> some View {
        let isSearchActive = store.showSearchBar && !store.searchQuery.isEmpty
        let isDiffActive = store.showDiffHighlight && store.currentFile != nil && store.compareFile != nil
        
        switch store.viewMode {
            
        case .easy:
            if isDiffActive {
                // Diff view — search highlights overlay via FieldCell's highlightQuery
                DiffEasyView(file: file, isFileB: isCompare)
            } else if isSearchActive {
                FilterableEasyView(file: file)
            } else {
                EasyView(file: file)
            }
            
        case .text:
            if let content = file.rawText {
                if isDiffActive,
                   let otherContent = (isCompare ? store.currentFile : store.compareFile)?.rawText {
                    // Diff view — search highlights overlay on top of diff colors
                    DiffRawTextView(content: content, otherContent: otherContent, isFileB: isCompare)
                } else if isSearchActive {
                    FilterableRawTextView(content: content)
                } else {
                    RawTextView(content: content)
                }
            } else {
                lazyPlaceholder(label: "Text", isLoading: file.isLoadingText, color: .brandViolet) {
                    store.loadFormatIfNeeded(.text, isCompare: isCompare)
                }
            }
            
        case .rawText:
            if let content = file.rawTextFull {
                if isDiffActive,
                   let otherContent = (isCompare ? store.currentFile : store.compareFile)?.rawTextFull {
                    DiffRawTextView(content: content, otherContent: otherContent, isFileB: isCompare)
                } else if isSearchActive {
                    FilterableRawTextView(content: content)
                } else {
                    RawTextView(content: content)
                }
            } else {
                lazyPlaceholder(label: "Raw Text", isLoading: file.isLoadingRawText, color: .brandPink) {
                    store.loadFormatIfNeeded(.rawText, isCompare: isCompare)
                }
            }
            
        case .html:
            if let content = file.rawHTML {
                HTMLView(htmlString: content)
            } else {
                lazyPlaceholder(label: "HTML", isLoading: file.isLoadingHTML, color: .brandGreen) {
                    store.loadFormatIfNeeded(.html, isCompare: isCompare)
                }
            }
            
        case .xml:
            if let content = file.rawXML {
                if isSearchActive {
                    FilterableRawTextView(content: content)
                } else {
                    RawTextView(content: content)
                }
            } else {
                lazyPlaceholder(label: "XML", isLoading: file.isLoadingXML, color: .brandBlue) {
                    store.loadFormatIfNeeded(.xml, isCompare: isCompare)
                }
            }
            
        case .json:
            if let content = file.rawJSON {
                if isSearchActive {
                    FilterableRawTextView(content: content)
                } else {
                    RawTextView(content: content)
                }
            } else {
                lazyPlaceholder(label: "JSON", isLoading: file.isLoadingJSON, color: .brandViolet) {
                    store.loadFormatIfNeeded(.json, isCompare: isCompare)
                }
            }
        }
    }
    
    // MARK: - Lazy-load placeholder
    
    private func lazyPlaceholder(
        label: String,
        isLoading: Bool,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 14) {
            if isLoading {
                ProgressView().tint(color)
                Text("Loading \(label)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(color.opacity(0.4))
                    .symbolEffect(.pulse)
                Text("\(label) not loaded")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Load \(label)") { action() }
                    .buttonStyle(.borderedProminent)
                    .tint(color)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Diff Easy View (colour-coded field comparison — easy fields only)

struct DiffEasyView: View {
    let file: MediaFile
    let isFileB: Bool
    @EnvironmentObject var store: MediaStore
    
    /// Build diff-annotated fields using ONLY the easy field keys (same subset EasyView shows)
    private var diffTracks: [(track: MediaTrack, fieldDiffs: [(key: String, value: String, state: DiffState)])] {
        let otherFile: MediaFile? = isFileB ? store.currentFile : store.compareFile
        guard let other = otherFile else {
            return file.tracks.map { track in
                let easyF = EasyFields.resolve(for: track)
                return (track: track, fieldDiffs: easyF.map { ($0.key, $0.value, DiffState.unchanged) })
            }
        }
        
        var result: [(track: MediaTrack, fieldDiffs: [(key: String, value: String, state: DiffState)])] = []
        
        for track in file.tracks {
            let easyF = EasyFields.resolve(for: track)
            
            // Find matching track in other file
            let otherTrack = other.tracks.first(where: {
                $0.type == track.type && $0.streamIndex == track.streamIndex
            })
            
            var fieldDiffs: [(key: String, value: String, state: DiffState)] = []
            
            for field in easyF {
                if let otherTrack = otherTrack {
                    if let otherField = otherTrack.fields.first(where: { $0.key == field.key }) {
                        if otherField.value == field.value {
                            fieldDiffs.append((field.key, field.value, .unchanged))
                        } else {
                            fieldDiffs.append((field.key, field.value, .modified))
                        }
                    } else {
                        fieldDiffs.append((field.key, field.value, isFileB ? .onlyInB : .onlyInA))
                    }
                } else {
                    fieldDiffs.append((field.key, field.value, isFileB ? .onlyInB : .onlyInA))
                }
            }
            
            result.append((track: track, fieldDiffs: fieldDiffs))
        }
        
        return result
    }
    
    var body: some View {
        let tracks = diffTracks
        
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(Array(tracks.enumerated()), id: \.offset) { _, item in
                    DiffTrackCard(track: item.track, fieldDiffs: item.fieldDiffs)
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Diff Track Card

struct DiffTrackCard: View {
    let track: MediaTrack
    let fieldDiffs: [(key: String, value: String, state: DiffState)]
    @EnvironmentObject var store: MediaStore
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: track.typeIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(trackColor)
                        .frame(width: 20)
                    Text(track.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    // Diff summary badge
                    let modCount = fieldDiffs.filter { $0.state != .unchanged }.count
                    if modCount > 0 {
                        Text("\(modCount) diff\(modCount == 1 ? "" : "s")")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.orange.opacity(0.85))
                            )
                    }
                    
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(trackColor.opacity(0.08))
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 160), spacing: 0),
                        GridItem(.flexible(minimum: 200), spacing: 0)
                    ],
                    alignment: .leading,
                    spacing: 0
                ) {
                    ForEach(Array(fieldDiffs.enumerated()), id: \.offset) { idx, field in
                        FieldCell(
                            key: FieldFormat.friendlyLabel(field.key),
                            value: field.value,
                            rowIndex: idx / 2,
                            highlightQuery: store.showSearchBar ? store.searchQuery : "",
                            diffState: field.state
                        )
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }
    
    private var trackColor: Color {
        switch track.type {
        case "General": return .gray
        case "Video":   return .blue
        case "Audio":   return .purple
        case "Text":    return .green
        case "Image":   return .teal
        case "Menu":    return .orange
        default:        return .secondary
        }
    }
}

// MARK: - Diff Raw Text View (line-by-line diff for text/rawText modes)

struct DiffRawTextView: NSViewRepresentable {
    let content: String
    let otherContent: String
    let isFileB: Bool
    @EnvironmentObject var store: MediaStore
    
    class Coordinator {
        var lastContent: String = ""
        var lastOtherContent: String = ""
        var lastFontSize: Double = 0
        var lastQuery: String = ""
        var lastIndex: Int = -1
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView   = scrollView.documentView as! NSTextView
        textView.isEditable         = false
        textView.isRichText         = true
        textView.backgroundColor    = .clear
        textView.drawsBackground    = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isSelectable       = true
        textView.usesFontPanel      = false
        textView.usesRuler          = false
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        let coord = context.coordinator
        let query = store.showSearchBar ? store.searchQuery : ""
        let fontSize = store.fontSize
        
        let contentChanged = coord.lastContent != content || coord.lastOtherContent != otherContent
        let fontChanged = coord.lastFontSize != fontSize
        let queryChanged = coord.lastQuery != query
        let indexChanged = coord.lastIndex != store.searchMatchIndex
        
        guard contentChanged || fontChanged || queryChanged || indexChanged else { return }
        
        let needsFullRebuild = contentChanged || fontChanged || queryChanged
        
        if needsFullRebuild {
            coord.lastContent = content
            coord.lastOtherContent = otherContent
            coord.lastFontSize = fontSize
            coord.lastQuery = query
        }
        
        let font = NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        
        let myLines    = content.components(separatedBy: "\n")
        let otherLines = otherContent.components(separatedBy: "\n")
        let otherLineSet = Set(otherLines)
        
        let attrStr = NSMutableAttributedString()
        
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        
        let modifiedBg    = NSColor(Color.orange.opacity(0.12))
        let modifiedFg    = NSColor(Color(red: 0.85, green: 0.50, blue: 0.10))
        let onlyInThisBg  = NSColor((isFileB ? Color.brandPink : Color.brandBlue).opacity(0.10))
        let onlyInThisFg  = NSColor(isFileB ? Color.brandPink : Color.brandBlue)
        
        for (i, line) in myLines.enumerated() {
            let lineText = line + (i < myLines.count - 1 ? "\n" : "")
            
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                attrStr.append(NSAttributedString(string: lineText, attributes: normalAttrs))
            } else if !otherLineSet.contains(line) {
                let isModified = i < otherLines.count && DiffHelper.sameKey(line, otherLines[i])
                
                if isModified {
                    var attrs = normalAttrs
                    attrs[.backgroundColor] = modifiedBg
                    attrs[.foregroundColor] = modifiedFg
                    attrStr.append(NSAttributedString(string: lineText, attributes: attrs))
                } else {
                    var attrs = normalAttrs
                    attrs[.backgroundColor] = onlyInThisBg
                    attrs[.foregroundColor] = onlyInThisFg
                    attrStr.append(NSAttributedString(string: lineText, attributes: attrs))
                }
            } else {
                attrStr.append(NSAttributedString(string: lineText, attributes: normalAttrs))
            }
        }
        
        // Overlay search highlights on top of diff colors
        var searchRanges: [NSRange] = []
        if !query.isEmpty {
            let fullText = attrStr.string
            
            // Try exact match first
            searchRanges = findNSRangesInContent(of: query, in: fullText)
            
            // If no exact matches, try space-normalized
            if searchRanges.isEmpty {
                let qNorm = query.lowercased().replacingOccurrences(of: " ", with: "")
                let lower = fullText.lowercased()
                var indexMap: [Int] = []
                for (i, char) in lower.enumerated() {
                    if char != " " { indexMap.append(i) }
                }
                let normalized = lower.replacingOccurrences(of: " ", with: "")
                let nsNorm = normalized as NSString
                var sr = NSRange(location: 0, length: nsNorm.length)
                
                while sr.location < nsNorm.length {
                    let found = nsNorm.range(of: qNorm, options: [], range: sr)
                    if found.location == NSNotFound { break }
                    let origStart = found.location < indexMap.count ? indexMap[found.location] : found.location
                    let origEndIdx = found.location + found.length - 1
                    let origEnd = origEndIdx < indexMap.count ? indexMap[origEndIdx] + 1 : origStart + found.length
                    searchRanges.append(NSRange(location: origStart, length: origEnd - origStart))
                    sr.location = found.location + found.length
                    sr.length = nsNorm.length - sr.location
                }
            }
            
            let highlightBg = NSColor(Color.brandGreen.opacity(0.3))
            let activeBg    = NSColor(Color.brandGreen.opacity(0.6))
            
            for (idx, range) in searchRanges.enumerated() {
                if idx == store.searchMatchIndex {
                    attrStr.addAttribute(.backgroundColor, value: activeBg, range: range)
                } else {
                    attrStr.addAttribute(.backgroundColor, value: highlightBg, range: range)
                }
            }
            
            if queryChanged {
                DispatchQueue.main.async {
                    self.store.searchMatchCount = searchRanges.count
                }
            }
        }
        
        textView.textStorage?.setAttributedString(attrStr)
        
        // Only scroll when index actually changed
        if indexChanged {
            coord.lastIndex = store.searchMatchIndex
            if !searchRanges.isEmpty && store.searchMatchIndex < searchRanges.count {
                textView.scrollRangeToVisible(searchRanges[store.searchMatchIndex])
            }
        }
    }
}

// MARK: - Marquee scrolling text for overflowing filenames

struct MarqueeText: View {
    let text: String
    let font: Font
    
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animating = false
    
    private var overflows: Bool { textWidth > containerWidth && containerWidth > 0 }
    
    // Total distance: scroll the full overflow + a gap so it looks clean
    private var scrollDistance: CGFloat { textWidth - containerWidth + 40 }
    // Duration proportional to text length so speed feels constant
    private var duration: Double { max(Double(scrollDistance) / 30.0, 2.0) }
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize()
                .offset(x: overflows ? offset : 0)
                .background(
                    // Invisible measurer
                    Text(text)
                        .font(font)
                        .lineLimit(1)
                        .fixedSize()
                        .hidden()
                        .background(GeometryReader { proxy in
                            Color.clear.onAppear { textWidth = proxy.size.width }
                        })
                )
                .onAppear { containerWidth = w }
                .onChange(of: w) { _, newW in containerWidth = newW }
                .onChange(of: textWidth) { _, _ in startAnimation() }
                .onChange(of: containerWidth) { _, _ in startAnimation() }
        }
        .frame(height: 16) // fixed height for single-line text
        .clipped()
    }
    
    private func startAnimation() {
        animating = false
        offset = 0
        
        guard overflows else { return }
        
        // Pause at the start, then scroll left, pause at the end, scroll back
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard overflows else { return }
            animating = true
            withAnimation(.linear(duration: duration)) {
                offset = -scrollDistance
            }
            
            // After reaching the end, pause then scroll back
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 2.0) {
                withAnimation(.linear(duration: duration)) {
                    offset = 0
                }
                // Restart the cycle
                DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1.5) {
                    startAnimation()
                }
            }
        }
    }
}

// MARK: - NSRange search helper

private func findNSRangesInContent(of query: String, in content: String) -> [NSRange] {
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
