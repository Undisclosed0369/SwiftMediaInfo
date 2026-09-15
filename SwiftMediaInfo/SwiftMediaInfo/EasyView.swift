//
//  EasyView.swift
//  SwiftMediaInfo
//
//  PHASE 3 — Easy View adopts the design system.
//
//  What changed:
//    • Track cards are glass instead of opaque controlBackgroundColor. This was
//      the main reason the content area stopped looking like the rest of the app.
//    • Track colours come from SMI.Palette instead of stock SwiftUI colours.
//    • Field values are monospaced so bit rates, sizes, and durations line up
//      vertically and become scannable in a column.
//    • Zebra striping is a single low-opacity wash rather than two opaque
//      system colours, so it works on top of glass.
//    • The empty case is handled by ContentStateView, not a bespoke layout.
//
//  PHASE 8a — copy actions and field tooltips.
//
//  TrackCard and FieldCell are shared with SearchBarView and CompareView, so
//  the new parameters (rawKey, fileURL) are optional and every existing call
//  site keeps working. FieldCell now carries the raw MediaInfo key alongside
//  its friendly label, because tooltips and "Copy Field Name" need the real
//  name, not the prettified one.
//

import SwiftUI

struct EasyView: View {
    let file: MediaFile
    
    /// Inject a guaranteed "FileName" field at the top of the General track.
    /// MediaInfo reports FileName without the extension, which is exactly the
    /// part people are often checking. The value is replaced rather than merely
    /// inserted when absent, so the row always shows the complete name.
    private var tracksWithInjectedFields: [MediaTrack] {
        file.tracks.map { track in
            guard track.type == "General" else { return track }
            var t = track
            let fullName = file.url.lastPathComponent
            
            if let index = t.fields.firstIndex(where: { $0.key == "FileName" }) {
                t.fields[index] = (key: "FileName", value: fullName)
            } else {
                t.fields.insert((key: "FileName", value: fullName), at: 0)
            }
            return t
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SMI.Spacing.large) {
                ForEach(tracksWithInjectedFields) { track in
                    TrackCard(track: track, fileURL: file.url)
                }
            }
            .padding(SMI.Spacing.xLarge)
        }
    }
}

// MARK: - Checksum card
//
// Carries the states a plain field cannot hold: waiting to be asked, running,
// stopped, failed. Renders nothing at all once the digest is in the track data.

struct ChecksumCard: View {
    /// Which pane to report on. The file itself is deliberately NOT passed in.
    ///
    /// It used to be, and in Compare Mode the card went dead — the button did
    /// nothing and the close control did nothing. `MediaFile` declares
    /// equality as "same id", so a file whose hash state had just changed still
    /// compared equal to the one SwiftUI already had, and SwiftUI skipped
    /// re-evaluating this view. Reading the file out of the observed store
    /// instead means the state that changed is the state being watched.
    var isCompare: Bool = false
    
    @EnvironmentObject var store: MediaStore
    
    private var file: MediaFile? {
        isCompare ? store.compareFile : store.currentFile
    }
    
    var body: some View {
        switch file?.hashState ?? .notApplicable {
        case .notApplicable, .ready:
            EmptyView()
            
        case .awaitingRequest:
            card(icon: "number.square", tint: .brandTeal) {
                Text("This file is over 10 GB. A SHA-256 checksum can be calculated on request.")
                    .font(SMI.Typo.callout)
                    .foregroundStyle(.secondary)
                
                Spacer(minLength: SMI.Spacing.medium)
                
                Button("Compute Checksum") { store.startHashing(isCompare: isCompare) }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandTeal)
                    .fixedSize()
                
                dismissButton
            }
            
        case .hashing(let progress):
            card(icon: "number.square", tint: .brandTeal) {
                VStack(alignment: .leading, spacing: SMI.Spacing.snug) {
                    Text("Calculating SHA-256… \(Int(progress * 100))%")
                        .font(SMI.Typo.callout.weight(.medium))
                    
                    // A real bar, unlike the Homebrew install in Phase 9: the
                    // file size is known and the bytes read are counted, so
                    // this fraction is measured rather than guessed.
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.brandTeal)
                        .frame(maxWidth: 320)
                }
                
                Spacer(minLength: SMI.Spacing.medium)
                
                Button("Stop") { store.cancelHashing(isCompare: isCompare) }
                    .buttonStyle(.bordered)
            }
            
        case .cancelled:
            card(icon: "stop.circle", tint: SMI.Palette.warning) {
                Text("Checksum stopped before it finished.")
                    .font(SMI.Typo.callout)
                    .foregroundStyle(.secondary)
                
                Spacer(minLength: SMI.Spacing.medium)
                
                Button("Start Again") { store.startHashing(isCompare: isCompare) }
                    .buttonStyle(.bordered)
                    .fixedSize()
                
                dismissButton
            }
            
        case .failed(let reason):
            card(icon: "exclamationmark.triangle.fill", tint: SMI.Palette.danger) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Checksum failed")
                        .font(SMI.Typo.callout.weight(.medium))
                    Text(reason)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer(minLength: SMI.Spacing.medium)
                
                Button("Try Again") { store.startHashing(isCompare: isCompare) }
                    .buttonStyle(.bordered)
                    .fixedSize()
                
                dismissButton
            }
        }
    }
    
    /// Hide the card without hashing.
    ///
    /// Deliberately absent while a hash is running — that state already has a
    /// Stop button, and a close control beside it would be ambiguous about
    /// whether it stops the work or just hides the card.
    private var dismissButton: some View {
        Button {
            smiWithAnimation(SMI.Motion.fade) {
                store.dismissChecksum(isCompare: isCompare)
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Hide this — the file is not hashed")
    }
    
    @ViewBuilder
    private func card<Content: View>(
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: SMI.Spacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(tint)
            
            content()
        }
        .padding(SMI.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SMI.Radius.card, style: .continuous)
                .fill(tint.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: SMI.Radius.card, style: .continuous)
                        .strokeBorder(tint.opacity(0.25), lineWidth: 0.8)
                )
        )
    }
}

// MARK: - TrackCard

struct TrackCard: View {
    let track: MediaTrack
    var highlightQuery: String = ""
    /// The file this track belongs to, for path-aware copying.
    var fileURL: URL? = nil
    /// The field key and occurrence holding the currently selected search
    /// result, when it falls inside this track.
    var activeMatch: (fieldKey: String, occurrence: Int)? = nil
    
    @EnvironmentObject var store: MediaStore
    @State private var isExpanded = true
    @State private var isHeaderHovered = false
    
    // MARK: Field assembly
    //
    // MediaInfo JSON (--Full) uses UNDERSCORE keys like Duration_String3,
    // FileSize_String, BitRate_String. Slash notation (Duration/String3) is
    // only valid in mediainfo's TEXT template syntax, not in JSON output.
    // EasyFields.resolve handles the lookup plus the strip-suffix fallback.
    
    private var easyFields: [(key: String, value: String)] {
        var fields = EasyFields.resolve(for: track)
        
        // Post-process Hz → kHz for Audio SamplingRate
        if track.type == "Audio" {
            fields = fields.map { f in
                f.key == "SamplingRate" ? (key: f.key, value: hzToKHz(f.value)) : f
            }
        }
        return fields
    }
    
    private var trackColor: Color { SMI.Palette.track(track.type) }
    
    var body: some View {
        GlassCard(tint: trackColor, isExpanded: isExpanded) {
            header
        } content: {
            fieldGrid
        }
    }
    
    // MARK: Header
    
    private var header: some View {
        Button {
            smiWithAnimation(SMI.Motion.smooth) { isExpanded.toggle() }
        } label: {
            HStack(spacing: SMI.Spacing.medium - 2) {
                // Card headers scale with the zoom level so the whole pane
                // grows as one thing. A fixed-size title next to scaled body
                // text is one of those details that reads as unfinished.
                Image(systemName: track.typeIcon)
                    .font(.system(size: CGFloat(store.fontSize) + 2, weight: .semibold))
                    .foregroundStyle(trackColor)
                    .frame(width: CGFloat(store.fontSize) + 8)
                
                Text(track.displayTitle)
                    .font(.system(size: CGFloat(store.fontSize) + 2, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                GlassBadge(
                    text: "\(easyFields.count)",
                    tint: trackColor,
                    filled: false,
                    scale: store.fontSize
                )
                
                Spacer(minLength: SMI.Spacing.small)
                
                Image(systemName: "chevron.down")
                    .font(.system(size: CGFloat(store.fontSize) - 2, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .smiAnimation(SMI.Motion.snap, value: isExpanded)
            }
            .padding(.horizontal, SMI.Spacing.large)
            .padding(.vertical, SMI.Spacing.medium)
            .background(isHeaderHovered ? SMI.Palette.hoverWash : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHeaderHovered = $0 }
        .smiAnimation(SMI.Motion.fade, value: isHeaderHovered)
        .contextMenu {
            Button("Copy Track") {
                store.copyTrack(track, from: fileURL)
            }
        }
    }
    
    // MARK: Field grid
    
    private var fieldGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 180), spacing: 0),
                GridItem(.flexible(minimum: 220), spacing: 0)
            ],
            alignment: .leading,
            spacing: 0
        ) {
            ForEach(Array(easyFields.enumerated()), id: \.offset) { idx, field in
                FieldCell(
                    key: FieldFormat.friendlyLabel(field.key),
                    value: field.value,
                    rowIndex: idx / 2,
                    highlightQuery: highlightQuery,
                    rawKey: field.key,
                    fileURL: fileURL,
                    activeOccurrence: activeMatch?.fieldKey == field.key
                    ? activeMatch?.occurrence
                    : nil
                )
            }
        }
        .padding(.bottom, SMI.Spacing.hair)
    }
    
    // MARK: - Hz → kHz
    
    private func hzToKHz(_ raw: String) -> String {
        let digits = raw.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ").first ?? raw
        if let hz = Double(digits) {
            let khz = hz / 1000.0
            return khz.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(khz)) kHz"
            : String(format: "%.1f kHz", khz)
        }
        return raw
    }
}

// MARK: - FieldCell

struct FieldCell: View {
    let key: String
    let value: String
    let rowIndex: Int
    var highlightQuery: String = ""
    var diffState: DiffState = .unchanged
    /// The raw MediaInfo key, kept alongside the friendly label so tooltips and
    /// "Copy Field & Value" can use the real name.
    var rawKey: String? = nil
    /// The file this row describes, so copies can be checked for local paths.
    var fileURL: URL? = nil
    /// Which search occurrence inside this row is the currently selected one,
    /// counted across the label first and then the value — the same order the
    /// match counter uses. Nil when the active match is in another row.
    var activeOccurrence: Int? = nil
    
    @EnvironmentObject var store: MediaStore
    @State private var isHovering = false
    @State private var didCopy = false
    @State private var showingExplanation = false
    
    private var explanation: String? {
        guard let rawKey else { return nil }
        return FieldGlossary.explanation(for: rawKey)
    }
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SMI.Spacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: SMI.Spacing.tight) {
                highlightedText(key, isKey: true)
                    .font(SMI.Typo.fieldLabel(store.fontSize))
                    .foregroundStyle(diffState == .unchanged ? .secondary : diffForeground)
                    .lineLimit(2)
                
                // A visible marker for fields the glossary can describe.
                // Hovering the label still works, but without a mark there is
                // nothing telling anyone a tooltip exists — an explanation you
                // have to guess is there is one most people never find.
                if let explanation {
                    Button {
                        showingExplanation.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: max(8, CGFloat(store.fontSize) - 4)))
                            .foregroundStyle(isHovering ? .secondary : .tertiary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // Hover *and* click. Hovering is faster once you know the
                    // tooltip is there; clicking gives you something that stays
                    // put long enough to read a long explanation, and is the
                    // only option if you use the keyboard or a trackpad where
                    // hovering is fiddly.
                    .help(explanation)
                    .accessibilityLabel("About \(key): \(explanation)")
                    .popover(isPresented: $showingExplanation, arrowEdge: .bottom) {
                        explanationPopover(explanation)
                    }
                }
                
                Spacer(minLength: 0)
            }
            .frame(minWidth: 118, alignment: .leading)
            // Applied to the whole label group as well as the icon. In Compare
            // Mode the panes sit under drop targets and motion modifiers, and a
            // tooltip attached to a single Text inside that stack was not being
            // picked up; the group is a reliable hover target.
            .help(explanation ?? "")
            
            // Monospaced so numeric values align down the column. This is the
            // single change that most makes the pane read as a measurement tool
            // rather than a form.
            highlightedText(value, isKey: false)
                .font(SMI.Typo.value(store.fontSize))
                .foregroundStyle(diffState == .unchanged ? .primary : diffForeground)
                .textSelection(.enabled)
            // No line limit: a truncated value is a value you have to copy
            // out to read, which defeats the point of a metadata viewer.
            // Long filenames wrap and the row grows to fit them.
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer(minLength: 0)
            
            copyAffordance
        }
        .padding(.horizontal, SMI.Spacing.large)
        .padding(.vertical, SMI.Spacing.snug)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        // PHASE 12b — the row-wide hover animation is deliberately gone.
        //
        // It was the single most expensive thing in the app. Sweeping a pointer
        // down forty rows started forty overlapping animations, each redrawing
        // its row for a dozen frames — and each of those repaints forced the
        // frosted card above it to re-sample its backdrop.
        //
        // The wash is now instant. Finder, Mail and Xcode all highlight rows
        // instantly; a fading row highlight is the unusual choice, not the
        // other way round. The copy button keeps its fade, scoped to itself.
        .contextMenu { contextMenuItems }
        // PHASE 11. One stop per row rather than four, and the copy button —
        // which only exists on hover, so it is unreachable without a pointer —
        // becomes a rotor action that is always available.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityAction(named: "Copy value") {
            copy(value, label: "value")
        }
        .accessibilityAction(named: "Copy field and value") {
            copy("\(rawKey ?? key): \(value)", label: "field")
        }
    }
    
    // MARK: - Explanation popover
    
    private func explanationPopover(_ explanation: String) -> some View {
        VStack(alignment: .leading, spacing: SMI.Spacing.small) {
            Text(key)
                .font(SMI.Typo.bodyStrong)
            
            if let rawKey, rawKey != key {
                // The real MediaInfo key, since that is what appears in the
                // Text, XML and JSON tabs and in anything scripted against the
                // tool. The friendly label only exists inside this app.
                Text(rawKey)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            
            Divider().opacity(0.4)
            
            Text(explanation)
                .font(SMI.Typo.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SMI.Spacing.large)
        .frame(width: 320, alignment: .leading)
    }
    
    // MARK: - Copy affordance
    //
    // A button that appears on hover, rather than making the whole row
    // clickable: the value is selectable text, and a row-wide click target
    // would fight with dragging out a selection.
    
    // PHASE 12b — restructured for cost, not for looks. Identical on screen.
    //
    // This used to be an if/else-if/else over three structurally different
    // views: a checkmark, a button, or an empty spacer. Every time the pointer
    // crossed a row, SwiftUI had to tear one branch out of the view tree and
    // build another — and sweeping down a long list means doing that forty
    // times in a second, in forty different rows.
    //
    // Now both pieces always exist and only their opacity changes. Opacity is
    // among the cheapest things to alter, because the view is already built and
    // already laid out; nothing is created or destroyed.
    //
    // The spacer is gone because it is no longer needed. It existed to stop the
    // row reflowing as the button appeared and disappeared — but the button
    // never disappears now, so the column cannot shift.
    //
    // `allowsHitTesting` is what keeps an invisible button from swallowing
    // clicks meant for the row underneath it.
    //
    // No longer needs @ViewBuilder — there is one view here now, not a branch.
    private var copyAffordance: some View {
        ZStack {
            Button {
                copy(value, label: "value")
            } label: {
                Image(systemName: "square.on.square")
                    .font(.system(size: max(9, CGFloat(store.fontSize) - 3), weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressStyle(scale: 0.85))
            .help("Copy this value")
            .opacity(isHovering && !didCopy ? 1 : 0)
            .allowsHitTesting(isHovering && !didCopy)
            // The fade you were promised, scoped to this one small view rather
            // than to the whole row. Twenty points of icon animating is a
            // fraction of the cost of an entire row animating.
            .smiAnimation(SMI.Motion.fade, value: isHovering)
            
            Image(systemName: "checkmark")
                .font(.system(size: max(9, CGFloat(store.fontSize) - 3), weight: .bold))
                .foregroundStyle(LinearGradient.brandSuccess)
                .frame(width: 20)
                .opacity(didCopy ? 1 : 0)
                .scaleEffect(didCopy ? 1 : 0.6)
                .allowsHitTesting(false)
        }
        .frame(width: 20)
    }
    
    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Copy Value") {
            copy(value, label: "value")
        }
        
        Button("Copy Field & Value") {
            copy("\(rawKey ?? key): \(value)", label: "field")
        }
        
        if let rawKey {
            Divider()
            Button("Copy Field Name") {
                copy(rawKey, label: "name")
            }
        }
    }
    
    private func copy(_ text: String, label: String) {
        store.copySnippet(text, from: fileURL)
        
        smiWithAnimation(SMI.Motion.snap) { didCopy = true }
        
        // PHASE 11 — the tick is the whole confirmation, and it is silent.
        SMI.A11y.announce("Copied \(label) to clipboard")
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            smiWithAnimation(SMI.Motion.fade) { didCopy = false }
        }
    }
    
    // MARK: - Search highlighting
    
    @ViewBuilder
    private func highlightedText(_ text: String, isKey: Bool) -> some View {
        if highlightQuery.isEmpty {
            Text(text)
        } else {
            Text(buildHighlightedAttributedString(text, isKey: isKey))
        }
    }
    
    /// Highlights every match, and marks one of them as the selected result.
    ///
    /// Without this, stepping through results moved the counter and scrolled
    /// the view but left every match looking identical — so "4 of 9" pointed at
    /// a screen where nothing said which one was the fourth.
    private func buildHighlightedAttributedString(
        _ text: String,
        isKey: Bool
    ) -> AttributedString {
        var result = AttributedString(text)
        let ranges = FieldFormat.highlightRanges(of: highlightQuery, in: text)
        
        // Occurrences are numbered label-first, then value, matching the order
        // the counter walks them in. The label's count is the value's offset.
        let labelCount = isKey
        ? 0
        : FieldFormat.highlightRanges(of: highlightQuery, in: key).count
        
        for (offset, range) in ranges.enumerated() {
            guard let attrRange = Range(range, in: result) else { continue }
            
            let isActive = activeOccurrence == labelCount + offset
            
            result[attrRange].backgroundColor = isActive
            ? Color.brandViolet.opacity(0.85)
            : Color.brandGreen.opacity(0.35)
            
            if isActive {
                result[attrRange].foregroundColor = .white
            }
        }
        
        return result
    }
    
    // MARK: - Row backgrounds
    
    @ViewBuilder
    private var rowBackground: some View {
        ZStack {
            (diffBackground ?? alternatingBackground)
            
            if isHovering {
                SMI.Palette.hoverWash
            }
        }
    }
    
    private var alternatingBackground: Color {
        rowIndex % 2 == 0 ? Color.clear : SMI.Palette.rowAlternate
    }
    
    private var diffBackground: Color? {
        switch diffState {
        case .unchanged: return nil
        case .added:     return SMI.Palette.success.opacity(0.10)
        case .removed:   return SMI.Palette.danger.opacity(0.10)
        case .modified:  return SMI.Palette.diffModified.opacity(0.12)
        case .onlyInA:   return SMI.Palette.diffOnlyInA.opacity(0.10)
        case .onlyInB:   return SMI.Palette.diffOnlyInB.opacity(0.10)
        }
    }
    
    private var diffForeground: Color {
        switch diffState {
        case .unchanged: return .primary
        case .added:     return SMI.Palette.success
        case .removed:   return SMI.Palette.danger
        case .modified:  return SMI.Palette.diffModified
        case .onlyInA:   return SMI.Palette.diffOnlyInA
        case .onlyInB:   return SMI.Palette.diffOnlyInB
        }
    }
    
    // MARK: - Diff state, spoken
    //
    // PHASE 11, and the most substantive accessibility finding in the app.
    //
    // In Compare Mode a row's status is carried entirely by colour: amber for
    // modified, blue for only-in-A, pink for only-in-B. Nothing else on the row
    // differs. Anyone who cannot separate those three hues — and red-green and
    // blue-purple confusion between them is common — sees a list of fields with
    // no comparison in it at all, which is the entire feature.
    //
    // Putting the status into the spoken label fixes it outright for VoiceOver.
    // It does not fix it for a sighted user with colour vision deficiency, who
    // gets no screen reader and no glyph. That remaining half needs a visible
    // marker on the row, which changes diff visuals carried over from v1.5 — a
    // design decision rather than a bug fix, and one flagged in the audit
    // report rather than made unilaterally here.
    
    private var diffDescription: String? {
        switch diffState {
        case .unchanged: return nil
        case .added:     return "Added"
        case .removed:   return "Removed"
        case .modified:  return "Changed between the two files"
        case .onlyInA:   return "Only in File A"
        case .onlyInB:   return "Only in File B"
        }
    }
    
    /// The whole row as one sentence: what the field is, what it says, and —
    /// in Compare Mode — how it differs.
    private var spokenLabel: String {
        var parts = ["\(key), \(value)"]
        if let diffDescription { parts.append(diffDescription) }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Diff state

enum DiffState {
    case unchanged, added, removed, modified, onlyInA, onlyInB
}
