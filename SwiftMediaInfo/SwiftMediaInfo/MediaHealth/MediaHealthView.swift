//
//  MediaHealthView.swift
//  SwiftMediaInfo
//
//  The Media Health window (a sheet, ⇧⌘H): verdict, checks and warnings,
//  Copy Report as text or Markdown, and a File A / File B switch in Compare
//  Mode. Return, Enter or Escape close it.
//
//  Read top to bottom it answers three questions in order: is this file OK
//  (the verdict), what was looked at (the checks), and what needs attention
//  (the warnings, each with what it means and what to do). When nothing does,
//  the last section says so plainly instead of disappearing.
//
//  The report is rebuilt from the store on every redraw rather than captured
//  once, so a file still loading, or a checksum still running, updates in
//  place while the window is open.
//

import SwiftUI

struct MediaHealthView: View {
    @EnvironmentObject var store: MediaStore
    @Environment(\.dismiss) private var dismiss

    @State var isCompare: Bool
    @State private var didCopy = false
    @State private var keyMonitor: Any?

    private var file: MediaFile? {
        isCompare ? store.compareFile : store.currentFile
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, SMI.Spacing.xxLarge)
                .padding(.top, SMI.Spacing.xxLarge)
                .padding(.bottom, SMI.Spacing.large)

            Divider().opacity(0.4)

            Group {
                if let file, !file.tracks.isEmpty {
                    let report = HealthReport(file: file)
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: SMI.Spacing.xLarge) {
                                verdict(report)
                                checksSection(report)
                                warningsSection(report)
                            }
                            .padding(SMI.Spacing.xxLarge)
                        }
                        
                        // Its own row under the list, not floated over it:
                        // floating, the report scrolled visibly behind the
                        // buttons.
                        Divider().opacity(0.4)
                        footer(report, url: file.url)
                    }
                } else if let file, file.jsonError != nil || file.loadError != nil {
                    message(
                        icon: "exclamationmark.triangle.fill",
                        tint: SMI.Palette.warning,
                        title: "This file couldn't be read",
                        detail: "MediaInfo couldn't analyse it, so there is nothing to check. The file may be damaged or not a media file."
                    )
                } else if file != nil {
                    VStack(spacing: SMI.Spacing.medium) {
                        ProgressView().controlSize(.large)
                        Text("Reading the file…")
                            .font(SMI.Typo.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    message(icon: "doc", tint: .secondary, title: "No file open",
                            detail: "Open a file to check its health.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 600, height: 680)
        .background(.ultraThinMaterial)
        .background(SheetKeyGuard())
        .onChange(of: isCompare) { _, side in
            store.loadFormatIfNeeded(.easy, isCompare: side)
        }
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: SMI.Spacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.brandGreen, Color.brandTeal],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                Image(systemName: "stethoscope")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Media Health")
                    .font(SMI.Typo.title)
                Text(file?.url.lastPathComponent ?? "")
                    .font(SMI.Typo.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(file?.url.lastPathComponent ?? "")
            }

            Spacer(minLength: SMI.Spacing.medium)

            // Compare Mode: switch between the two files here, so ⌘⇧H never
            // has to guess which one you meant.
            if store.isCompareMode, store.currentFile != nil, store.compareFile != nil {
                Picker("File", selection: $isCompare) {
                    Text("File A").tag(false)
                    Text("File B").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }

            SheetCloseButton { dismiss() }
        }
    }

    // MARK: Verdict

    private func verdict(_ report: HealthReport) -> some View {
        let healthy = report.warnings.isEmpty
        let tint = healthy ? SMI.Palette.success : SMI.Palette.warning

        return HStack(spacing: SMI.Spacing.medium) {
            Image(systemName: healthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 2) {
                Text(healthy ? "This file looks healthy" : (report.warnings.count == 1
                                                             ? "1 thing to look at"
                                                             : "\(report.warnings.count) things to look at"))
                    .font(SMI.Typo.headline)
                Text("\(report.passedCount) of \(report.checks.count) checks passed"
                     + (healthy ? "" : " · details below"))
                    .font(SMI.Typo.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(SMI.Spacing.large)
        .background(
            RoundedRectangle(cornerRadius: SMI.Radius.button, style: .continuous)
                .fill(tint.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: SMI.Radius.button, style: .continuous)
                        .strokeBorder(tint.opacity(0.30), lineWidth: 0.8)
                )
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: Checks

    private func checksSection(_ report: HealthReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassSectionHeader(title: "Checks", icon: "list.bullet.clipboard", tint: .brandBlue)

            VStack(spacing: 0) {
                ForEach(Array(report.checks.enumerated()), id: \.element.id) { index, check in
                    if index > 0 {
                        Divider().opacity(0.3).padding(.leading, 44)
                    }
                    checkRow(check)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: SMI.Radius.button, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: SMI.Radius.button, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                    )
            )
        }
    }

    private func checkRow(_ check: HealthCheck) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SMI.Spacing.medium) {
            statusIcon(check.status)
                .frame(width: 20)

            Text(check.title)
                .font(SMI.Typo.label)
                .frame(width: 170, alignment: .leading)

            Text(check.result)
                .font(SMI.Typo.body)
                .monospacedDigit()
                .foregroundStyle(check.status == .warning ? SMI.Palette.warning : .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SMI.Spacing.medium)
        .padding(.vertical, SMI.Spacing.small + 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(check.title): \(check.result). \(spoken(check.status))")
    }

    private func statusIcon(_ status: HealthCheck.Status) -> some View {
        Group {
            switch status {
            case .passed:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(SMI.Palette.success)
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(SMI.Palette.warning)
            case .info:
                Image(systemName: "minus.circle").foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 14, weight: .semibold))
    }

    private func spoken(_ status: HealthCheck.Status) -> String {
        switch status {
        case .passed:  return "Passed"
        case .warning: return "Warning"
        case .info:    return "Not applicable"
        }
    }

    // MARK: Warnings

    private func warningsSection(_ report: HealthReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassSectionHeader(title: "Warnings", icon: "exclamationmark.triangle", tint: SMI.Palette.warning)

            if report.warnings.isEmpty {
                HStack(alignment: .top, spacing: SMI.Spacing.medium) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SMI.Palette.success)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No warnings — nothing needs fixing")
                            .font(SMI.Typo.bodyStrong)
                        Text("Every check that applies to this file passed. It should play and edit without surprises.")
                            .font(SMI.Typo.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(SMI.Spacing.large)
                .background(
                    RoundedRectangle(cornerRadius: SMI.Radius.button, style: .continuous)
                        .fill(SMI.Palette.success.opacity(0.08))
                )
            } else {
                VStack(spacing: SMI.Spacing.medium) {
                    ForEach(report.warnings) { warning in
                        warningCard(warning)
                    }
                }
            }
        }
    }

    private func warningCard(_ warning: HealthCheck) -> some View {
        VStack(alignment: .leading, spacing: SMI.Spacing.small) {
            HStack(spacing: SMI.Spacing.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(SMI.Palette.warning)
                Text(warning.title)
                    .font(SMI.Typo.bodyStrong)
                Text("·").foregroundStyle(.tertiary)
                Text(warning.result)
                    .font(SMI.Typo.callout)
                    .foregroundStyle(SMI.Palette.warning)
            }

            if let explanation = warning.explanation {
                Text(explanation)
                    .font(SMI.Typo.body)
                    .foregroundStyle(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if let suggestion = warning.suggestion {
                HStack(alignment: .firstTextBaseline, spacing: SMI.Spacing.snug) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.brandTeal)
                    Text(suggestion)
                        .font(SMI.Typo.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(SMI.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SMI.Radius.button, style: .continuous)
                .fill(SMI.Palette.warning.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: SMI.Radius.button, style: .continuous)
                        .strokeBorder(SMI.Palette.warning.opacity(0.25), lineWidth: 0.8)
                )
        )
    }

    // MARK: Footer

    private func footer(_ report: HealthReport, url: URL) -> some View {
        HStack(spacing: SMI.Spacing.small) {
            Menu {
                Button("Copy Report") { copy(report, url: url, asMarkdown: false) }
                Button("Copy Report as Markdown") { copy(report, url: url, asMarkdown: true) }
            } label: {
                Label(didCopy ? "Copied" : "Copy Report",
                      systemImage: didCopy ? "checkmark" : "doc.on.doc")
            } primaryAction: {
                copy(report, url: url, asMarkdown: false)
            }
            .menuStyle(.borderedButton)
            .fixedSize()

            Spacer()

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.brandViolet)
        }
        .padding(.horizontal, SMI.Spacing.xxLarge)
        .padding(.vertical, SMI.Spacing.medium)
    }

    private func copy(_ report: HealthReport, url: URL, asMarkdown: Bool) {
        store.copyHealthReport(report, from: url, asMarkdown: asMarkdown)
        smiWithAnimation(SMI.Motion.snap) { didCopy = true }
        SMI.A11y.announce("Copied report")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            smiWithAnimation(SMI.Motion.fade) { didCopy = false }
        }
    }

    // MARK: Keys
    //
    // Return, Enter and Escape all close the window — it is a report, so
    // there is nothing for any of them to confirm or cancel.
    //
    // A monitor rather than the Done button's default-action shortcut alone:
    // once a click lands in the report's selectable text, that text becomes
    // first responder and swallows Return before the button ever sees it,
    // and Escape had no control to fall back on at all.
    
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Only this sheet's own window, and only the bare keys: ⌘-Return
            // and friends keep whatever meaning they have elsewhere.
            guard event.window?.isSheet == true,
                  event.window?.attachedSheet == nil,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            else { return event }
            
            switch event.keyCode {
            case 36, 76, 53:   // Return, keypad Enter, Escape
                dismiss()
                return nil
            default:
                return event
            }
        }
    }
    
    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
    
    // MARK: Messages

    private func message(icon: String, tint: Color, title: String, detail: String) -> some View {
        VStack(spacing: SMI.Spacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(tint)
            Text(title).font(SMI.Typo.headline)
            Text(detail)
                .font(SMI.Typo.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .padding(.top, SMI.Spacing.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
