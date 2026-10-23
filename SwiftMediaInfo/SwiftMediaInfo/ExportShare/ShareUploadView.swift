//
//  ShareUploadView.swift
//  SwiftMediaInfo
//
//  Share's interface: the formats (ShareFormat), the toolbar button, the
//  menus (Compare Mode's file-then-format steps, and the format list shared
//  with Export), and the sheet that follows — preparing, the review screen,
//  uploading, then the link or the error.
//
//  The review screen lists exactly what sanitisation removed, so the privacy
//  protection is visible rather than taken on faith. The work itself —
//  building, sanitising and uploading — is in MediaStore+Share.
//

import SwiftUI

// MARK: - Share format picker

enum ShareFormat: String, CaseIterable, Identifiable {
    // The same formats, in the same order, as Export (raw values must match
    // ExportFormat's); plus every format at once as a ZIP.
    case text, rawText, html, pdf, markdown, csv, json, xml, zip
    var id: String { rawValue }
    
    /// The export this share uploads. Nil for the ZIP, which holds all of them.
    var exportFormat: ExportFormat? {
        ExportFormat(rawValue: rawValue)
    }
    
    var label: String {
        exportFormat?.label ?? "ZIP (all formats)"
    }
    
    var icon: String {
        exportFormat?.icon ?? "archivebox"
    }
    
    /// Where it goes. HTML and PDF become web pages, Markdown a rendered
    /// Markdown page, the rest plain-text pastes.
    enum Host {
        case paste, webPage, markdownPage, fileDrop
        
        var name: String {
            switch self {
            case .paste:        return "pb.plz.ac"
            case .webPage:      return "ship.page"
            case .markdownPage: return "markdown.page"
            case .fileDrop:     return "up.sb"
            }
        }
    }
    
    var host: Host {
        switch self {
        case .html, .pdf: return .webPage
        case .markdown:   return .markdownPage
        case .zip:        return .fileDrop
        default:          return .paste
        }
    }
}

// MARK: - Share Button (toolbar)

struct ShareButton: View {
    @EnvironmentObject var store: MediaStore
    @State private var showPopover = false
    
    var body: some View {
        // On ToolbarActionButton so it hovers and compresses
        // like everything else in its cluster. No success state: sharing opens
        // a popover and then a link, both of which confirm themselves.
        ToolbarActionButton(
            icon: "link.badge.plus",
            label: "Share",
            accentColor: .brandGreen,
            isActive: showPopover,
            isDisabled: !store.hasOpenReport,
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
    /// The file chosen in the first step. Kept after stepping back, so the
    /// formats step can slide out still showing it.
    @State private var source: CopySource = .fileA
    @State private var showsFormats = false
    @State private var isGoingBack = false
    
    var body: some View {
        PopoverSteps(showsSecond: showsFormats, isGoingBack: isGoingBack) {
            fileStep
        } second: {
            ShareFormatPopover(isPresented: $isPresented, source: source, onBack: {
                step(to: false)
            })
            .environmentObject(store)
        }
        .frame(width: 300)
    }
    
    private func step(to formats: Bool) {
        isGoingBack = !formats
        smiWithAnimation(SMI.Motion.popoverStep) { showsFormats = formats }
    }
    
    private var fileStep: some View {
        VStack(alignment: .leading, spacing: 4) {
            PopoverTitle(text: "Share — Choose File")
            
            Divider()
            
            // In share mode, only allow individual files (not "both")
            ForEach([CopySource.fileA, .fileB], id: \.self) { choice in
                PopoverChoiceRow(title: choice.label, icon: choice.icon) {
                    source = choice
                    step(to: true)
                }
            }
        }
        .padding(.bottom, 8)
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
                PopoverBackButton(title: source.label, action: onBack)
            }
            
            PopoverTitle(text: "Share Online", topPadding: onBack == nil ? 12 : 0)
            
            Text("Upload and get a link anyone can open")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            
            Divider()
            
            ExportFormatList(verb: "Share") { exportFormat in
                guard let format = ShareFormat(rawValue: exportFormat.rawValue) else { return }
                isPresented = false
                store.afterPopoverCloses { store.shareOnline(format: format, source: source) }
            }
            
            Divider()
            
            PopoverMenuItem(title: "Share All as ZIP…", icon: "archivebox") {
                isPresented = false
                store.afterPopoverCloses { store.shareOnline(format: .zip, source: source) }
            }
            
            Divider()
            
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                Text("HTML, PDF → ship.page · Markdown → markdown.page · Text, CSV, JSON, XML → pb.plz.ac (24h) · ZIP → up.sb")
                    .font(.system(size: 10))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .padding(.bottom, 4)
        .frame(width: 300)
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
        .background(SheetKeyGuard())
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
            
            if pending.offersPathChoice {
                // Same shape as the deferred bindings in AppearanceSettings.
                // A segmented Picker calls its setter *during*
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
                Picker("File paths", selection: Binding(
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
                    Text(pending.pathsKeptBySetting
                         ? "This upload will include your full file path — Settings › Privacy keeps paths in HTML."
                         : "This upload will include your full file path.")
                        .font(SMI.Typo.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
            
            // Never a guess whether the checksum is going out.
            if let includesChecksum = pending.includesChecksum {
                HStack(spacing: SMI.Spacing.snug) {
                    Image(systemName: includesChecksum ? "number.square.fill" : "number.square")
                        .foregroundStyle(Color.brandTeal)
                    Text(includesChecksum
                         ? "The SHA-256 checksum is included."
                         : "The SHA-256 checksum is left out.")
                        .font(SMI.Typo.caption)
                        .foregroundStyle(.secondary)
                }
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
                    // The green tick is invisible to a screen
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
