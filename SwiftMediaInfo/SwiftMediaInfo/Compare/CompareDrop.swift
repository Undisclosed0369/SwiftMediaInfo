//
//  CompareDrop.swift
//  SwiftMediaInfo
//
//  Dropping files on Compare Mode: the SwiftUI panes' drop delegate and the
//  centre card that opens a dropped file on its own. The AppKit panes use
//  the same zone rules through FileDropHandler (FileDropTextView.swift).
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Compare-mode drop delegate
//
// SwiftUI's plain `.onDrop(of:isTargeted:)` reports only *whether* a drag is
// over the pane, never where — which isn't enough once a pane holds more than
// one destination. DropDelegate exposes the location on every update, so the
// same zone rules the AppKit panes use can be applied here.
//
// WHY THIS IS A CLASS, NOT A STRUCT
//
// The first version was a struct built inline in `body`. Its `dropEntered`
// mutates store state that `body` observes, so the sequence was: drag enters →
// state changes → body re-renders → `.onDrop` is handed a brand-new delegate
// instance mid-drag → SwiftUI treats the drop session as changed and can tear
// it down. A self-invalidating loop, which is why the highlight appeared
// sometimes and not others rather than never.
//
// Holding one instance in @State and mutating its properties keeps the
// delegate's identity stable across re-renders, so the drag session survives
// its own side effects.

@MainActor
final class PaneDropCoordinator: DropDelegate {
    
    let paneTarget: FileDropTarget
    var paneSize: CGSize = .zero
    weak var store: MediaStore?
    
    init(paneTarget: FileDropTarget) {
        self.paneTarget = paneTarget
    }
    
    private func resolved(_ info: DropInfo) -> FileDropTarget? {
        guard let store else { return paneTarget }
        return FileDropSupport.resolveTarget(
            paneTarget: paneTarget,
            localPoint: info.location,
            paneSize: paneSize,
            centreAvailable: store.isCentreDropAvailable
        )
    }
    
    /// Whether this coordinator's pane still exists.
    private var isLive: Bool {
        store?.isCompareMode == true
    }
    
    /// The destination this drag should actually go to.
    ///
    /// A stale coordinator — one whose pane has gone but whose drop region is
    /// still mounted — resolves to `.main` rather than refusing the drag.
    ///
    /// Refusing was the previous behaviour and it broke Easy View: SwiftUI does
    /// not pass a declined drop up to an ancestor handler, so the stale region
    /// swallowed the drag and the window-wide target never saw it. Tabs backed
    /// by AppKit views were unaffected because they handle drops themselves,
    /// which is why only Easy View stopped accepting files.
    ///
    /// Behaving as the window-wide target is both correct and self-healing: it
    /// works whether or not the region is stale, with no dependency on when
    /// SwiftUI gets around to tearing the pane down.
    private func destination(for info: DropInfo) -> FileDropTarget? {
        guard isLive else { return .main }
        return resolved(info)
    }
    
    /// Who owns the highlight for this drag — the pane, or the window.
    private var owner: FileDropTarget {
        isLive ? paneTarget : .main
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        // A tab dragged over a pane is a tab, not a file arriving.
        !FileDropSupport.isTabDragActive && info.hasItemsConforming(to: [.fileURL])
    }
    
    func dropEntered(info: DropInfo) {
        store?.beginDragSession()
        store?.reportDropTarget(destination(for: info), from: owner)
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        let target = destination(for: info)
        store?.reportDropTarget(target, from: owner)
        // Refusing in the dead zone makes the cursor show "no" there, which is
        // the honest signal: a drop at that point would do nothing.
        return DropProposal(operation: target == nil ? .cancel : .copy)
    }
    
    func dropExited(info: DropInfo) {
        store?.reportDropTarget(nil, from: owner)
        store?.endDragSession(from: owner)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        guard let store else { return false }
        
        guard let target = destination(for: info) else {
            store.reportDropTarget(nil, from: owner)
            store.endDragSession(from: owner)
            return false
        }
        
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else {
            return false
        }
        
        store.reportDropTarget(nil, from: owner)
        store.endDragSession(from: owner)
        
        Task { @MainActor in
            let urls = await FileDropSupport.fileURLs(from: providers)
            FileDropSupport.deliver(urls, to: target, store: store)
        }
        
        return true
    }
}

// MARK: - Centre drop card
//
// Straddles the divider, which is the whole point: it belongs to neither pane,
// and its position says so before any label does.

struct CentreDropCard: View {
    let isHighlighted: Bool
    
    private var tint: Color { FileDropTarget.newFile.tint }
    
    var body: some View {
        VStack(spacing: SMI.Spacing.small) {
            Image(systemName: "film.stack")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(LinearGradient.brandSweep(tint))
            
            VStack(spacing: 2) {
                Text("Open on its own")
                    .font(SMI.Typo.bodyStrong)
                    .foregroundStyle(.primary)
                
                // States the consequence up front. A file dropped here closes
                // a mode, and that shouldn't be a surprise discovered after.
                Text("Leaves Compare Mode")
                    .font(SMI.Typo.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(
            width: CompareDropGeometry.cardWidth,
            height: CompareDropGeometry.cardHeight
        )
        .background(
            RoundedRectangle(cornerRadius: SMI.Radius.panel, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: SMI.Radius.panel, style: .continuous)
                        .fill(tint.opacity(isHighlighted ? 0.20 : 0.08))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: SMI.Radius.panel, style: .continuous)
                .strokeBorder(
                    tint.opacity(isHighlighted ? 0.9 : 0.35),
                    lineWidth: isHighlighted ? 2.5 : 1
                )
        )
        .smiShadow(
            isHighlighted
            ? SMI.Elevation.floating(tint)
            : SMI.Elevation.raised(tint)
        )
        .scaleEffect(isHighlighted ? 1.04 : 1.0)
        .smiAnimation(SMI.Motion.snap, value: isHighlighted)
    }
}
