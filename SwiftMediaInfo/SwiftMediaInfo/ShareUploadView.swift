//
//  ShareUploadView.swift
//  SwiftMediaInfo
//
//  Upload mediainfo results to pb.plz.ac (text) or up.sb (ZIP)
//  and display the resulting URL with copy support.
//
//  PHASE 5 — a review step now sits between choosing a format and uploading.
//  It lists exactly what sanitisation removed, so the user can see the privacy
//  protection working rather than being asked to take it on faith.
//

import SwiftUI

// MARK: - Share format picker

enum ShareFormat: String, CaseIterable, Identifiable {
    case txt, rawText, csv, json, html, zip
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .txt:     return "Text (.txt)"
        case .rawText: return "Raw Text (.txt)"
        case .csv:     return "CSV (.csv)"
        case .json:    return "JSON (.json)"
        case .html:    return "HTML (.html)"
        case .zip:     return "ZIP (all formats)"
        }
    }
    
    var icon: String {
        switch self {
        case .txt:     return "doc.text"
        case .rawText: return "text.alignleft"
        case .csv:     return "tablecells"
        case .json:    return "curlybraces"
        case .html:    return "globe"
        case .zip:     return "archivebox"
        }
    }
    
    var accentColor: Color {
        switch self {
        case .txt:     return .brandViolet
        case .rawText: return .brandPink
        case .csv:     return .brandGreen
        case .json:    return .brandBlue
        case .html:    return .brandPink
        case .zip:     return .brandViolet
        }
    }
}

// MARK: - Share Button (toolbar)

struct ShareButton: View {
    @EnvironmentObject var store: MediaStore
    @State private var showPopover = false
    
    var body: some View {
        // PHASE 11 — moved onto ToolbarActionButton so it hovers and compresses
        // like everything else in its cluster. No success state: sharing opens
        // a popover and then a link, both of which confirm themselves.
        ToolbarActionButton(
            icon: "link.badge.plus",
            label: "Share",
            accentColor: .brandGreen,
            isActive: showPopover,
            isDisabled: store.currentFile == nil,
            help: "Upload & share online",
            voiceOverLabel: "Share report",
            voiceOverHint: "Uploads the report and gives you a link"
        ) {
            showPopover = true
        }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            if store.isCompareMode {
                CompareSharePopover(isPresented: $showPopover)
                    .environmentObject(store)
            } else {
                ShareFormatPopover(isPresented: $showPopover, source: .fileA)
                    .environmentObject(store)
            }
        }
    }
}

// MARK: - Compare share popover (pick file first, then format)

struct CompareSharePopover: View {
    @EnvironmentObject var store: MediaStore
    @Binding var isPresented: Bool
    @State private var selectedSource: CopySource? = nil
    
    var body: some View {
        if let source = selectedSource {
            ShareFormatPopover(isPresented: $isPresented, source: source, onBack: {
                selectedSource = nil
            })
            .environmentObject(store)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Share — Choose File")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                
                Divider()
                
                // In share mode, only allow individual files (not "both")
                ForEach([CopySource.fileA, .fileB], id: \.self) { source in
                    Button { selectedSource = source } label: {
                        HStack {
                            Label(source.label, systemImage: source.icon)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)
            .frame(minWidth: 230)
        }
    }
}

// MARK: - Share format popover

struct ShareFormatPopover: View {
    @EnvironmentObject var store: MediaStore
    @Binding var isPresented: Bool
    let source: CopySource
    var onBack: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let onBack = onBack {
                HStack {
                    Button {
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left")
                        Text(source.label)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .padding(.leading, 12)
                    Spacer()
                }
                .padding(.top, 12)
                .padding(.bottom, 4)
            }
            
            Text("Share Online")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, onBack == nil ? 12 : 0)
                .padding(.bottom, 4)
            
            Text("Upload to a pastebin and get a link")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            
            Divider()
            
            ForEach(ShareFormat.allCases) { format in
                Button {
                    isPresented = false
                    store.shareOnline(format: format, source: source)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: format.icon)
                            .foregroundStyle(format.accentColor)
                            .frame(width: 16)
                        Text(format.label)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                Text("Text files → pb.plz.ac (24h) · ZIP → up.sb")
                    .font(.system(size: 10))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .padding(.bottom, 4)
        .frame(minWidth: 280)
    }
}

// MARK: - Upload progress / result sheet

struct ShareResultView: View {
    @EnvironmentObject var store: MediaStore
    @State private var copied = false
    
    var body: some View {
        VStack(spacing: SMI.Spacing.large) {
            if let error = store.shareError {
                errorState(error)
            } else if let url = store.shareResultURL {
                successState(url)
            } else if store.isUploading {
                uploadingState
            } else if store.isPreparingShare {
                preparingState
            } else if let pending = store.pendingShare {
                reviewState(pending)
            }
        }
        .padding(SMI.Spacing.xxLarge)
        .frame(minWidth: 440)
        .background(.ultraThinMaterial)
        .smiAnimation(SMI.Motion.smooth, value: store.pendingShare)
        .smiAnimation(SMI.Motion.smooth, value: store.isUploading)
    }
    
    // MARK: - Preparing
    
    private var preparingState: some View {
        VStack(spacing: SMI.Spacing.medium + 2) {
            ZStack {
                Circle()
                    .fill(Color.brandViolet.opacity(0.12))
                    .frame(width: 64, height: 64)
                ProgressView()
                    .tint(.brandViolet)
                    .scaleEffect(1.2)
            }
            Text("Preparing…")
                .font(.title3.weight(.semibold))
            Text("Gathering the report and removing local paths")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Review
    //
    // Nothing has left the machine at this point. This screen is the last stop
    // before it does, and it exists to make the redactions visible.
    
    private func reviewState(_ pending: PendingShare) -> some View {
        VStack(spacing: SMI.Spacing.large) {
            
            ZStack {
                Circle()
                    .fill(Color.brandGreen.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.brandGreen)
            }
            
            VStack(spacing: SMI.Spacing.tight) {
                Text("Ready to Upload")
                    .font(.title3.weight(.semibold))
                
                Text("\(pending.format.label) · \(pending.fileName)")
                    .font(SMI.Typo.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 380)
            }
            
            if PrivacyPreference.share == .ask {
                // PHASE 12c FIX — same shape as the three bindings in
                // SettingsView. A segmented Picker calls its setter *during*
                // SwiftUI's update pass; `setPendingShareRemovesPaths` then
                // mutates a @Published value on the store, which announces a
                // change to a SwiftUI that has not finished applying the last
                // one.
                //
                // Deferred by one turn of the run loop so the current update
                // completes first. `MainActor.assumeIsolated` asserts what
                // `RunLoop.main` already guarantees — that this body runs on
                // the main thread — so the compiler can verify the call rather
                // than warning about it.
                Picker("", selection: Binding(
                    get: { pending.removePaths },
                    set: { newValue in
                        RunLoop.main.perform {
                            MainActor.assumeIsolated {
                                store.setPendingShareRemovesPaths(newValue)
                            }
                        }
                    }
                )) {
                    Text("Remove paths").tag(true)
                    Text("Include paths").tag(false)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            
            if !pending.removePaths {
                HStack(spacing: SMI.Spacing.snug) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(SMI.Palette.warning)
                    Text("This upload will include your full file path.")
                        .font(SMI.Typo.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(SMI.Spacing.medium)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: SMI.Radius.control, style: .continuous)
                        .fill(SMI.Palette.warning.opacity(0.10))
                )
            } else if pending.report.isEmpty {
                HStack(spacing: SMI.Spacing.snug) {
                    Image(systemName: "checkmark.seal")
                        .foregroundStyle(Color.brandGreen)
                    Text("No local path information was found in this report.")
                        .font(SMI.Typo.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(SMI.Spacing.medium)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: SMI.Radius.control, style: .continuous)
                        .fill(Color.brandGreen.opacity(0.08))
                )
            } else {
                VStack(alignment: .leading, spacing: SMI.Spacing.small) {
                    GlassSectionHeader(
                        title: "Removed before upload",
                        icon: "eye.slash",
                        tint: .brandGreen
                    )
                    
                    ForEach(pending.report.removals) { removal in
                        HStack(alignment: .firstTextBaseline, spacing: SMI.Spacing.small) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.brandGreen)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(removal.label)
                                    .font(SMI.Typo.callout)
                                Text(removal.replacement)
                                    .font(SMI.Typo.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer(minLength: SMI.Spacing.small)
                            
                            GlassBadge(
                                text: "\(removal.occurrences)×",
                                tint: .brandGreen,
                                filled: false
                            )
                        }
                    }
                }
                .padding(SMI.Spacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: SMI.Radius.control, style: .continuous)
                        .fill(Color.brandGreen.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: SMI.Radius.control, style: .continuous)
                                .strokeBorder(Color.brandGreen.opacity(0.22), lineWidth: 0.7)
                        )
                )
            }
            
            Text("The upload will be publicly accessible to anyone with the link.")
                .font(SMI.Typo.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: SMI.Spacing.medium) {
                Button("Cancel") {
                    store.cancelPendingShare()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Button("Upload") {
                    store.confirmShareUpload()
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandViolet)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
    
    // MARK: - States
    
    private var uploadingState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.brandViolet.opacity(0.12))
                    .frame(width: 64, height: 64)
                ProgressView()
                    .tint(.brandViolet)
                    .scaleEffect(1.2)
            }
            Text("Uploading…")
                .font(.title3.weight(.semibold))
            Text("Preparing and uploading your mediainfo report")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.red)
            }
            Text("Upload Failed")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            
            Button("Dismiss") {
                store.dismissShareResult()
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandViolet)
        }
    }
    
    private func successState(_ url: String) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.brandGreen.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.brandGreen)
            }
            
            Text("Uploaded Successfully!")
                .font(.title3.weight(.semibold))
            
            // Clickable URL
            HStack(spacing: 8) {
                // The URL as a clickable link
                Button(action: {
                    if let link = URL(string: url) {
                        NSWorkspace.shared.open(link)
                    }
                }) {
                    Text(url)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.brandBlue)
                        .underline()
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help("Click to open in browser")
                .accessibilityLabel("Share link")
                .accessibilityValue(url)
                .accessibilityHint("Opens the link in your browser")
                .accessibilityAddTraits([.isButton, .isLink])
                
                // Copy button
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                    copied = true
                    // PHASE 11 — the green tick is invisible to a screen
                    // reader, and the clipboard is invisible to everyone.
                    SMI.A11y.announce("Link copied to clipboard")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12))
                        Text(copied ? "Copied!" : "Copy")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(copied ? Color.brandGreen : Color.brandViolet)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill((copied ? Color.brandGreen : Color.brandViolet).opacity(0.12))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder((copied ? Color.brandGreen : Color.brandViolet).opacity(0.3), lineWidth: 0.7)
                    )
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: copied)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Copy link")
                .accessibilityValue(copied ? "Copied" : "")
                .accessibilityAddTraits(.isButton)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            )
            
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text("Link expires in 24 hours")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
            
            Button("Done") {
                store.dismissShareResult()
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandViolet)
        }
    }
}
