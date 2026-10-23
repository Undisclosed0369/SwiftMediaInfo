//
//  MediaStore+Checksums.swift
//  SwiftMediaInfo
//
//  SHA-256 checksums: when a file is hashed (per Settings › Analysis), how
//  a hash is started, deferred until its tab is shown, cancelled and
//  recorded — on the file, and in HashCache and the analysis cache. The
//  hashing itself is FileHasher; the running tasks (`hashTasks`) are
//  declared in MediaStore.swift.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit
internal import Combine

extension MediaStore {
    
    // MARK: Checksum methods
    /// Decide what to do about a newly opened file's checksum.
    ///
    /// Called once the file is on screen rather than before, so a 50 GB file
    /// shows its metadata immediately and hashes in the background.
    func beginHashingIfNeeded(for url: URL, sessionID: UUID, isCompare: Bool) {
        guard FileHasher.isEligible(url) else {
            setHashState(.notApplicable, sessionID: sessionID, isCompare: isCompare)
            return
        }
        
        // A remembered digest is applied without touching the disk. This is
        // the whole reason the cache exists: reopening a large file should be
        // instant, not another few minutes of reading.
        if let cached = HashCache.digest(for: url) {
            applyDigest(cached, sessionID: sessionID, isCompare: isCompare)
            return
        }
        
        switch HashPolicy.current {
        case .never:
            setHashState(.notApplicable, sessionID: sessionID, isCompare: isCompare)
            
        case .manual:
            setHashState(.awaitingRequest, sessionID: sessionID, isCompare: isCompare)
            
        case .always:
            startHashing(sessionID: sessionID)
        }
    }
    
    /// Start hashing whichever pane is named. Also the entry point for the
    /// Compute Checksum button and for retrying after a failure.
    func startHashing(isCompare: Bool) {
        guard let file = isCompare ? compareFile : currentFile else { return }
        startHashing(sessionID: file.id)
    }
    
    private func startHashing(sessionID: UUID) {
        guard let file = file(withSessionID: sessionID),
              !file.hashState.isRunning else { return }
        
        let url = file.url
        
        cancelHashing(sessionID: sessionID)
        setHashState(.hashing(progress: 0), sessionID: sessionID, isCompare: false)
        
        let task = Task { [weak self] in
            do {
                let digest = try await FileHasher.sha256(of: url) { progress in
                    self?.setHashState(
                        .hashing(progress: progress),
                        sessionID: sessionID,
                        isCompare: false
                    )
                }
                
                guard !Task.isCancelled else { return }
                
                HashCache.store(digest, for: url)
                AnalysisCache.update(for: url) { $0.digest = digest }
                self?.hashTasks[sessionID] = nil
                self?.applyDigest(digest, sessionID: sessionID, isCompare: false)
                
            } catch is CancellationError {
                // The cancelling side already set the state. Setting it again
                // here would overwrite a file that has since been replaced.
                return
                
            } catch {
                self?.hashTasks[sessionID] = nil
                self?.setHashState(
                    .failed(reason: error.localizedDescription),
                    sessionID: sessionID,
                    isCompare: false
                )
            }
        }
        
        hashTasks[sessionID] = task
    }
    
    /// Hide the checksum card without hashing.
    ///
    /// A card offering work you have decided not to do is clutter, and on a
    /// file you are only inspecting it sits between you and the metadata. This
    /// is per-file and not persisted — reopening the file offers again, which
    /// is right, because "not now" is not the same as "never for this file".
    /// "Never at all" is the Off setting.
    func dismissChecksum(isCompare: Bool) {
        guard let file = isCompare ? compareFile : currentFile else { return }
        
        cancelHashing(sessionID: file.id)
        setHashState(.notApplicable, sessionID: file.id, isCompare: isCompare)
    }
    
    /// Stop a running hash at the user's request, saying so and offering to
    /// start again.
    func cancelHashing(isCompare: Bool, markCancelled: Bool = true) {
        guard let file = isCompare ? compareFile : currentFile else { return }
        
        cancelHashing(sessionID: file.id)
        
        if markCancelled, file.hashState.isRunning {
            setHashState(.cancelled, sessionID: file.id, isCompare: isCompare)
        }
    }
    
    /// Stop a hash quietly — the file is being closed or replaced, so there is
    /// nothing left to report it on.
    func cancelHashing(sessionID: UUID) {
        hashTasks.removeValue(forKey: sessionID)?.cancel()
    }
    
    /// Write a state back, but only if the file it belongs to is still open.
    ///
    /// The session id is checked for the same reason the analysis results
    /// check it: a hash started minutes ago must not write into whatever file
    /// happens to be on screen now. Matched by id wherever the file is — in
    /// any tab, or as File B.
    private func setHashState(_ state: HashState, sessionID: UUID, isCompare: Bool) {
        update(sessionID: sessionID) { $0.hashState = state }
    }
    
    /// Record a finished digest and inject it into the track data.
    ///
    /// Injecting into `tracks` rather than into each view is what makes this
    /// feature cheap: Easy View, Compare Mode's diff, the search index, CSV
    /// export and every copy action already read from tracks, so all of them
    /// gain the checksum without a line of their own.
    private func applyDigest(_ digest: String, sessionID: UUID, isCompare: Bool) {
        setHashState(.ready(digest: digest), sessionID: sessionID, isCompare: isCompare)
        refreshComparison()
    }
}
