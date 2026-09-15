//
//  MediaComparison.swift
//  SwiftMediaInfo
//
//  PHASE 7 — one comparison, computed once, read by both panes.
//
//  WHAT WAS WRONG
//
//  The old diff lived in a computed property on the pane view, so it ran again
//  on every render — and each pane computed its *own*, walking only its own
//  fields and asking whether the other file happened to have them.
//
//  That made it one-directional. A field present in File A but missing from
//  File B was marked "only in A" in A's pane, and simply did not appear in B's
//  pane at all. There was no row to mark, so the absence was invisible on the
//  side where it mattered most. Rows also drifted out of alignment between the
//  panes, because each listed a different set of fields.
//
//  WHAT THIS DOES
//
//  Builds the union of both files' fields, per track, once. Every field appears
//  in both panes at the same position, with a placeholder on whichever side
//  lacks it. Scrolling the two panes side by side now compares like with like,
//  which is the entire point of the mode.
//

import Foundation

// MARK: - Comparison

struct MediaComparison: Equatable {
    
    // MARK: Field
    
    struct FieldDifference: Identifiable, Equatable {
        let id: String
        let key: String
        /// nil means the field is absent from that file.
        let valueA: String?
        let valueB: String?
        let state: DiffState
        
        /// The value to show in a given pane, or nil when absent there.
        func value(isFileB: Bool) -> String? {
            isFileB ? valueB : valueA
        }
        
        /// How this difference should be coloured in a given pane.
        ///
        /// A field only File A has reads as "only in A" in both panes: the fact
        /// is about the pair of files, not about the pane you happen to be
        /// looking at, and flipping the label per side made the two panes
        /// disagree about the same field.
        var displayState: DiffState { state }
    }
    
    // MARK: Track
    
    struct TrackComparison: Identifiable, Equatable {
        // Compared by identity and by the differences themselves. The raw
        // MediaTrack values are deliberately excluded: their `fields` is a
        // tuple array, which Swift cannot synthesise Equatable for, and the
        // differences already capture everything that affects rendering.
        static func == (lhs: TrackComparison, rhs: TrackComparison) -> Bool {
            lhs.id == rhs.id && lhs.fields == rhs.fields
        }
        
        let id: String
        let type: String
        let streamIndex: Int
        let displayTitle: String
        /// The track as it exists in each file, if it exists there at all.
        let trackA: MediaTrack?
        let trackB: MediaTrack?
        let fields: [FieldDifference]
        
        var changeCount: Int {
            fields.filter { $0.state != .unchanged }.count
        }
        
        var icon: String {
            switch type {
            case "Video":  return "film"
            case "Audio":  return "waveform"
            case "Text":   return "captions.bubble"
            case "Menu":   return "list.number"
            case "Image":  return "photo"
            default:       return "info.circle"
            }
        }
    }
    
    let tracks: [TrackComparison]
    
    // MARK: Totals
    
    var modifiedCount: Int { tracks.reduce(0) { $0 + $1.fields.filter { $0.state == .modified }.count } }
    var onlyInACount:  Int { tracks.reduce(0) { $0 + $1.fields.filter { $0.state == .onlyInA  }.count } }
    var onlyInBCount:  Int { tracks.reduce(0) { $0 + $1.fields.filter { $0.state == .onlyInB  }.count } }
    
    var totalDifferences: Int { modifiedCount + onlyInACount + onlyInBCount }
    
    var isIdentical: Bool { totalDifferences == 0 }
    
    /// Tracks that differ, for the summary panel.
    var changedTracks: [TrackComparison] {
        tracks.filter { $0.changeCount > 0 }
    }
    
    /// Changed tracks arranged for display, collapsing crowded types.
    ///
    /// A release with twelve subtitle tracks turns the summary into a wall of
    /// near-identical rows, which buries the one or two lines that actually
    /// matter. Above the threshold a type folds into a single row that can be
    /// opened; below it, the rows are more useful flat than nested.
    var summaryGroups: [SummaryGroup] {
        let threshold = 3
        var groups: [SummaryGroup] = []
        var handled = Set<String>()
        
        for track in changedTracks where !handled.contains(track.type) {
            let sameType = changedTracks.filter { $0.type == track.type }
            handled.insert(track.type)
            
            if sameType.count > threshold {
                groups.append(
                    SummaryGroup(
                        id: "group.\(track.type)",
                        type: track.type,
                        icon: track.icon,
                        tracks: sameType,
                        isCollapsible: true
                    )
                )
            } else {
                for single in sameType {
                    groups.append(
                        SummaryGroup(
                            id: single.id,
                            type: single.type,
                            icon: single.icon,
                            tracks: [single],
                            isCollapsible: false
                        )
                    )
                }
            }
        }
        
        return groups
    }
    
    /// One row in the summary — either a single track or a folded type.
    struct SummaryGroup: Identifiable, Equatable {
        let id: String
        let type: String
        let icon: String
        let tracks: [TrackComparison]
        let isCollapsible: Bool
        
        var totalChanges: Int {
            tracks.reduce(0) { $0 + $1.changeCount }
        }
        
        /// "Audio" when folded, the full track title when not.
        var title: String {
            isCollapsible ? type : (tracks.first?.displayTitle ?? type)
        }
        
        var subtitle: String? {
            guard isCollapsible else { return nil }
            return "\(tracks.count) tracks"
        }
    }
    
    // MARK: - Building
    
    /// Compares two files, matching tracks by type and stream index.
    ///
    /// Track order follows File A, then any tracks only File B has, appended in
    /// its own order. That keeps the left pane's layout stable while the file on
    /// the right changes, which matters when someone is comparing one reference
    /// file against several candidates in turn.
    static func build(fileA: MediaFile?, fileB: MediaFile?) -> MediaComparison {
        guard let fileA, let fileB else {
            return MediaComparison(tracks: [])
        }
        
        var result: [TrackComparison] = []
        var consumedB = Set<String>()
        
        func key(_ track: MediaTrack) -> String {
            "\(track.type)#\(track.streamIndex)"
        }
        
        for trackA in fileA.tracks {
            let identifier = key(trackA)
            let trackB = fileB.tracks.first { key($0) == identifier }
            if trackB != nil { consumedB.insert(identifier) }
            
            result.append(
                compare(identifier: identifier, trackA: trackA, trackB: trackB)
            )
        }
        
        for trackB in fileB.tracks where !consumedB.contains(key(trackB)) {
            result.append(
                compare(identifier: key(trackB), trackA: nil, trackB: trackB)
            )
        }
        
        return MediaComparison(tracks: result)
    }
    
    private static func compare(
        identifier: String,
        trackA: MediaTrack?,
        trackB: MediaTrack?
    ) -> TrackComparison {
        
        // Easy View's curated field selection, so the comparison shows the same
        // fields the user already sees rather than the full raw dump.
        let fieldsA = trackA.map { EasyFields.resolve(for: $0) } ?? []
        let fieldsB = trackB.map { EasyFields.resolve(for: $0) } ?? []
        
        let lookupA = Dictionary(fieldsA.map { ($0.key, $0.value) }) { first, _ in first }
        let lookupB = Dictionary(fieldsB.map { ($0.key, $0.value) }) { first, _ in first }
        
        // Union, ordered by File A first so the left pane keeps its natural
        // reading order, with B-only fields appended.
        var orderedKeys = fieldsA.map(\.key)
        let seen = Set(orderedKeys)
        orderedKeys.append(contentsOf: fieldsB.map(\.key).filter { !seen.contains($0) })
        
        var differences: [FieldDifference] = []
        
        for fieldKey in orderedKeys {
            let valueA = lookupA[fieldKey]
            let valueB = lookupB[fieldKey]
            
            let state: DiffState
            switch (valueA, valueB) {
            case (.some(let a), .some(let b)):
                state = (a == b) ? .unchanged : .modified
            case (.some, .none):
                state = .onlyInA
            case (.none, .some):
                state = .onlyInB
            case (.none, .none):
                continue
            }
            
            differences.append(
                FieldDifference(
                    id: "\(identifier).\(fieldKey)",
                    key: fieldKey,
                    valueA: valueA,
                    valueB: valueB,
                    state: state
                )
            )
        }
        
        let reference = trackA ?? trackB
        
        return TrackComparison(
            id: identifier,
            type: reference?.type ?? "Unknown",
            streamIndex: reference?.streamIndex ?? 0,
            displayTitle: reference?.displayTitle ?? identifier,
            trackA: trackA,
            trackB: trackB,
            fields: differences
        )
    }
}

// MARK: - Text-view navigation

extension MediaComparison {
    
    /// The section headings MediaInfo writes for a given track, most specific
    /// first.
    ///
    /// Text and Raw Text output is organised by heading lines — "General",
    /// "Video", "Audio #2" — rather than by any structure the app can address
    /// directly, so jumping to a track there means finding its heading.
    ///
    /// MediaInfo numbers headings only when a file has more than one track of
    /// that kind: one audio track is "Audio", two are "Audio #1" and
    /// "Audio #2". Both spellings are tried, numbered first. The bare form is
    /// only offered for the first track, since a later track appearing without
    /// a number would mean the numbering was absent entirely — and matching the
    /// bare heading then would scroll to the wrong section.
    static func textSectionCandidates(forTrackID id: String) -> [String] {
        let parts = id.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let index = Int(parts[1]) else { return [id] }
        
        let type = String(parts[0])
        var candidates = ["\(type) #\(index + 1)"]
        if index == 0 { candidates.append(type) }
        return candidates
    }
    
    /// Locates a track's heading in MediaInfo text output.
    ///
    /// Matched as a whole line, anchored, rather than as a substring: "Audio"
    /// appears inside plenty of field values — "Audio ID", "Audio channels" —
    /// and a substring search would happily scroll to one of those instead of
    /// the heading.
    ///
    /// Uses NSString regular-expression matching so the returned NSRange is in
    /// UTF-16 units, which is what NSTextView expects. Counting Swift
    /// Characters would drift on any heading containing non-ASCII text.
    static func range(ofTrackID id: String, in text: String) -> NSRange? {
        let nsText = text as NSString
        
        for candidate in textSectionCandidates(forTrackID: id) {
            let pattern = "^[ \\t]*"
            + NSRegularExpression.escapedPattern(for: candidate)
            + "[ \\t]*$"
            
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.anchorsMatchLines]
            ) else { continue }
            
            if let match = regex.firstMatch(
                in: text,
                options: [],
                range: NSRange(location: 0, length: nsText.length)
            ) {
                return match.range
            }
        }
        
        return nil
    }
}
