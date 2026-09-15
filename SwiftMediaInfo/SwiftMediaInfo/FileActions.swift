//
//  FileActions.swift
//  SwiftMediaInfo
//
//  PHASE 8b — file actions.
//
//  Five things you can do to the file itself, as opposed to the report about
//  it: Reveal in Finder, Copy Path, Copy Filename, Rename, Move to Trash.
//
//  DESIGN NOTES
//
//  One action set, three renderings. The actions are described once as data
//  (`FileAction`) and dispatched through one entry point on the store
//  (`MediaStore.perform(_:on:isCompare:)`). The three places they appear —
//  a context menu, the toolbar popover, and the menu bar's File menu — are
//  purely presentation. Adding a sixth action later means touching the enum
//  and the switch, not five call sites.
//
//  The store is passed in explicitly rather than read from the environment.
//  `contextMenu` content is built in a detached presentation context on macOS,
//  and environment objects have historically not survived that reliably. A
//  plain `let` reference cannot go missing.
//
//  The two destructive actions confirm first, and both confirmations live on
//  ContentView because a sheet or alert has to be attached to a view that is
//  actually on screen — a context menu has already closed by the time its
//  action runs.
//

import SwiftUI
import AppKit

// MARK: - A pending confirmation
//
// Carries the file and which pane it belongs to, so the confirmation UI does
// not have to re-derive either. The identity is its own, not the file's: the
// same file can legitimately be renamed twice in a row, and a sheet keyed on
// the URL would refuse to reopen the second time.

struct PendingFileAction: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    /// True when this is File B in Compare Mode.
    let isCompare: Bool
}

// MARK: - The action set

enum FileAction: String, CaseIterable, Identifiable {
    case reveal
    case copyPath
    case copyFilename
    case rename
    case trash
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .reveal:       return "Reveal in Finder"
        case .copyPath:     return "Copy Path"
        case .copyFilename: return "Copy Filename"
        case .rename:       return "Rename…"
        case .trash:        return "Move to Trash"
        }
    }
    
    /// SF Symbols chosen for availability rather than novelty — every one of
    /// these has existed since macOS 11, so none can quietly render as a blank
    /// box on a machine that is a version behind.
    var icon: String {
        switch self {
        case .reveal:       return "folder"
        case .copyPath:     return "doc.on.clipboard"
        case .copyFilename: return "doc.on.doc"
        case .rename:       return "pencil"
        case .trash:        return "trash"
        }
    }
    
    /// Drawn in red and separated from the rest. The visual weight is the
    /// first line of defence; the confirmation is the second.
    var isDestructive: Bool { self == .trash }
    
    /// Whether this action changes anything on disk. Used to decide what a
    /// list of recent files should offer, where the file in question is not
    /// necessarily the one on screen.
    var modifiesFile: Bool {
        switch self {
        case .rename, .trash: return true
        default:              return false
        }
    }
    
    var help: String {
        switch self {
        case .reveal:       return "Show this file in a Finder window"
        case .copyPath:     return "Copy the full path to the clipboard"
        case .copyFilename: return "Copy just the file name to the clipboard"
        case .rename:       return "Give this file a new name on disk"
        case .trash:        return "Move this file to the Trash"
        }
    }
}

// MARK: - Menu items
//
// Plain buttons, for `contextMenu` and for the menu bar. No styling of its own
// — a menu item that tries to look designed looks wrong in a system menu.

struct FileActionsMenuItems: View {
    let store: MediaStore
    let url: URL
    let isCompare: Bool
    
    /// Actions to leave out. Recent-file chips exclude the two that write to
    /// disk: the file behind a chip is often not the file on screen, and
    /// renaming or trashing something you are only pointing at is a mistake
    /// waiting to happen.
    var excluding: Set<FileAction> = []
    
    /// Key equivalents are attached only in the menu bar's single-file case.
    /// A shortcut inside a context menu is decoration — the menu is already
    /// open, so nobody is going to reach for the keyboard — and the same
    /// shortcut appearing on both File A and File B would be a lie.
    var withShortcuts: Bool = false
    
    var body: some View {
        let actions = FileAction.allCases.filter { !excluding.contains($0) }
        
        ForEach(actions) { action in
            if action.isDestructive {
                Divider()
            }
            
            button(for: action)
        }
    }
    
    @ViewBuilder
    private func button(for action: FileAction) -> some View {
        if withShortcuts, let shortcut = keyEquivalent(for: action) {
            plainButton(for: action)
                .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        } else {
            plainButton(for: action)
        }
    }
    
    private func plainButton(for action: FileAction) -> some View {
        let role: ButtonRole? = action.isDestructive ? ButtonRole.destructive : nil
        
        return Button(role: role) {
            store.perform(action, on: url, isCompare: isCompare)
        } label: {
            Label(action.title, systemImage: action.icon)
        }
    }
    
    /// Rename and Copy Filename deliberately have none.
    ///
    /// Rename has no conventional Mac shortcut outside Finder's own Return,
    /// which is already spoken for here. Copy Filename would need a four-key
    /// combination to sit beside Copy Path, and a shortcut nobody can hold
    /// down comfortably is worse than no shortcut at all.
    private func keyEquivalent(
        for action: FileAction
    ) -> (key: KeyEquivalent, modifiers: EventModifiers)? {
        switch action {
        case .reveal:
            return (key: "r", modifiers: [.command, .shift])
            
        case .copyPath:
            return (key: "c", modifiers: [.command, .option])
            
        case .trash:
            return (key: KeyEquivalent.delete, modifiers: .command)
            
        default:
            return nil
        }
    }
}

// MARK: - Toolbar button

struct FileActionsButton: View {
    @EnvironmentObject var store: MediaStore
    @State private var showPopover = false
    
    private var hasAnyFile: Bool {
        store.currentFile != nil || store.compareFile != nil
    }
    
    var body: some View {
        GlassButton(
            icon: "doc.badge.ellipsis",
            label: "File Actions",
            accentColor: .brandViolet,
            isDisabled: !hasAnyFile
        ) {
            showPopover = true
        }
        .help("Actions for the open file")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            FileActionsPopover(isPresented: $showPopover)
                .environmentObject(store)
        }
    }
}

// MARK: - Toolbar popover
//
// Flat rather than the two-step "choose a file, then choose an action" shape
// that Export uses. Export has six formats per file and would be unreadable
// flattened; this has five actions, and putting both files on one screen means
// the common case — one file open — is a single click instead of two.

struct FileActionsPopover: View {
    @EnvironmentObject var store: MediaStore
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("File Actions")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)
            
            Divider()
            
            if store.isCompareMode {
                if let fileA = store.currentFile {
                    section(
                        title: "File A — \(fileA.fileName)",
                        tint: .brandBlue,
                        url: fileA.url,
                        isCompare: false
                    )
                }
                
                if store.currentFile != nil && store.compareFile != nil {
                    Divider()
                        .padding(.vertical, 2)
                }
                
                if let fileB = store.compareFile {
                    section(
                        title: "File B — \(fileB.fileName)",
                        tint: .brandPink,
                        url: fileB.url,
                        isCompare: true
                    )
                }
            } else if let file = store.currentFile {
                ForEach(FileAction.allCases) { action in
                    row(action, url: file.url, isCompare: false)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(minWidth: 260)
    }
    
    @ViewBuilder
    private func section(
        title: String,
        tint: Color,
        url: URL,
        isCompare: Bool
    ) -> some View {
        Text(title)
            .font(SMI.Typo.caption)
            .foregroundStyle(tint)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)
        
        ForEach(FileAction.allCases) { action in
            row(action, url: url, isCompare: isCompare)
        }
    }
    
    private func row(_ action: FileAction, url: URL, isCompare: Bool) -> some View {
        Button {
            isPresented = false
            store.perform(action, on: url, isCompare: isCompare)
        } label: {
            Label(action.title, systemImage: action.icon)
                .foregroundStyle(action.isDestructive ? SMI.Palette.danger : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .help(action.help)
    }
}

// MARK: - Rename text field
//
// AppKit rather than SwiftUI's TextField, for two things SwiftUI cannot do.
//
//   1. SELECT THE STEM. Opening the sheet with `document.mp4` fully selected
//      means typing replaces the extension too. Finder selects only the part
//      before the final dot, and so does this — you type the new name, the
//      extension survives, and nobody has to think about it.
//
//   2. STANDARD EDITING KEYS. ⌘⌫ (clear to start of line), ⌥⌫ (delete word)
//      and the rest are behaviours of AppKit's field editor. A SwiftUI
//      TextField gets most of them, but only an NSTextField gives a reliable
//      handle on the editor to place a selection in the first place.
//
// The field owns focus itself rather than going through @FocusState, because
// the selection has to be set on the *editor*, which only exists once the
// field is first responder — so the two steps have to happen together.

private struct RenameTextField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onCancel: () -> Void
    
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.placeholderString = "File name"
        return field
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        
        guard !context.coordinator.hasTakenFocus else { return }
        
        // A focus request made in the same pass as the view's creation is
        // dropped silently — the field is not in the responder chain yet. One
        // turn of the run loop later it lands. The flag is only set once the
        // window actually exists, so a first attempt that arrives too early
        // simply tries again on the next update.
        //
        // WHY RunLoop AND NOT DispatchQueue
        //
        // `DispatchQueue.main.async` was tried, both bare and with an explicit
        // user-interactive QoS, and both produced Xcode's priority-inversion
        // hang warning on the `makeFirstResponder` call. GCD tracks the
        // priority of the thread that enqueued a block against the priority of
        // whatever that block ends up waiting on inside AppKit, and no QoS
        // argument fixes what AppKit does internally.
        //
        // `RunLoop.main.perform` schedules the block directly on the run loop
        // instead. It carries no GCD priority to invert, which is what makes
        // the warning go away. The observable behaviour — one turn of the run
        // loop later — is identical.
        RunLoop.main.perform(inModes: [.common]) {
            guard let window = nsView.window else { return }
            
            context.coordinator.hasTakenFocus = true
            window.makeFirstResponder(nsView)
            selectStem(in: nsView)
        }
    }
    
    /// Select everything up to the final dot.
    ///
    /// A leading dot is left alone: `.hidden` is the whole name, not an empty
    /// name with an extension, and selecting nothing would be a strange way to
    /// open the sheet.
    private func selectStem(in field: NSTextField) {
        guard let editor = field.currentEditor() else { return }
        
        let name = field.stringValue as NSString
        let dot  = name.range(of: ".", options: .backwards)
        
        let stemLength: Int
        if dot.location == NSNotFound || dot.location == 0 {
            stemLength = name.length
        } else {
            stemLength = dot.location
        }
        
        editor.selectedRange = NSRange(location: 0, length: stemLength)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RenameTextField
        var hasTakenFocus = false
        
        init(parent: RenameTextField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        
        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy selector: Selector
        ) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
                
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
                
            default:
                // Everything else — ⌘⌫, ⌥⌫, ⌃A, word selection — is handled by
                // the field editor's own key bindings. Returning false is what
                // lets it get on with that.
                return false
            }
        }
    }
}

// MARK: - Rename sheet
//
// A sheet rather than an NSAlert with an accessory text field. The privacy
// prompt uses an alert because it asks a yes/no question in the middle of a
// synchronous action; this one is a small form with live validation, and an
// alert is a poor host for anything that has to give feedback as you type.
//
// The whole file name is editable, extension included. Finder edits only the
// stem and warns when you touch the suffix; the same warning is here, but the
// field is not split, because splitting it makes the common case — correcting a
// typo mid-name — require working out which half the typo is in.

struct RenameFileSheet: View {
    @EnvironmentObject var store: MediaStore
    let pending: PendingFileAction
    
    @State private var name: String = ""
    
    private var originalName: String { pending.url.lastPathComponent }
    
    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// The two characters macOS will not accept in a file name. Colons are
    /// legal on disk but Finder rewrites them to slashes on sight, so a name
    /// containing one comes back looking like something you did not type.
    private var illegalCharacters: Bool {
        trimmed.contains("/") || trimmed.contains(":")
    }
    
    private var isUnchanged: Bool { trimmed == originalName }
    
    private var alreadyExists: Bool {
        guard !trimmed.isEmpty, !isUnchanged, !illegalCharacters else { return false }
        let destination = pending.url
            .deletingLastPathComponent()
            .appendingPathComponent(trimmed)
        return FileManager.default.fileExists(
            atPath: destination.path(percentEncoded: false)
        )
    }
    
    /// True when the suffix after the final dot has changed. Compared
    /// case-insensitively, because `.MP4` and `.mp4` open in the same app and
    /// warning about that would be noise.
    private var extensionChanged: Bool {
        let oldExt = (originalName as NSString).pathExtension.lowercased()
        let newExt = (trimmed as NSString).pathExtension.lowercased()
        return oldExt != newExt
    }
    
    private var canRename: Bool {
        !trimmed.isEmpty && !illegalCharacters && !alreadyExists && !isUnchanged
    }
    
    private var problem: String? {
        if trimmed.isEmpty       { return "A file needs a name." }
        if illegalCharacters     { return "A file name can’t contain “/” or “:”." }
        if alreadyExists         { return "There’s already an item with that name in this folder." }
        return nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: SMI.Spacing.large) {
            
            header
            
            VStack(alignment: .leading, spacing: SMI.Spacing.small) {
                RenameTextField(
                    text: $name,
                    onSubmit: { if canRename { commit() } },
                    onCancel: { store.pendingRename = nil }
                )
                .frame(height: 20)
                .padding(.horizontal, SMI.Spacing.medium)
                .padding(.vertical, SMI.Spacing.small + 1)
                .background(
                    RoundedRectangle(cornerRadius: SMI.Radius.control, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SMI.Radius.control, style: .continuous)
                        .strokeBorder(
                            problem == nil
                            ? Color.brandViolet.opacity(0.35)
                            : SMI.Palette.danger.opacity(0.55),
                            lineWidth: 1
                        )
                )
                
                notice
            }
            
            HStack(spacing: SMI.Spacing.small) {
                Spacer()
                
                Button("Cancel") { store.pendingRename = nil }
                    .keyboardShortcut(.cancelAction)
                
                Button("Rename") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.brandViolet)
                    .disabled(!canRename)
            }
        }
        .padding(SMI.Spacing.xxLarge)
        .frame(width: 460)
        .background(.ultraThinMaterial)
        .smiAnimation(SMI.Motion.fade, value: problem)
        .smiAnimation(SMI.Motion.fade, value: extensionChanged)
        // Seeded here rather than as the property's default, because the
        // default is evaluated once for the type and this sheet is handed a
        // different file each time it opens. Focus and the stem selection are
        // the field's own job — see RenameTextField.
        .onAppear { name = originalName }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: SMI.Spacing.medium) {
            ZStack {
                Circle()
                    .fill(Color.brandViolet.opacity(0.12))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "pencil")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.brandViolet)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Rename File")
                    .font(.title3.weight(.semibold))
                
                Text(originalName)
                    .font(SMI.Typo.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer(minLength: 0)
        }
    }
    
    // MARK: - Inline notice
    //
    // One slot, three possible occupants, in priority order: an error that
    // blocks the rename, a warning that does not, or a reminder of what this
    // touches. Keeping it to one slot means the sheet never changes height as
    // you type, which is what makes a live-validating form feel calm.
    
    @ViewBuilder
    private var notice: some View {
        if let problem {
            noticeRow(
                icon: "exclamationmark.circle.fill",
                tint: SMI.Palette.danger,
                text: problem
            )
        } else if extensionChanged && !isUnchanged {
            noticeRow(
                icon: "exclamationmark.triangle.fill",
                tint: SMI.Palette.warning,
                text: "Changing the extension may stop this file opening in the right app."
            )
        } else {
            noticeRow(
                icon: "info.circle",
                tint: .secondary,
                text: "This renames the file on disk, then re-reads it so the report matches."
            )
        }
    }
    
    private func noticeRow(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SMI.Spacing.snug) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(tint)
            
            Text(text)
                .font(SMI.Typo.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer(minLength: 0)
        }
        .frame(height: 30, alignment: .top)
    }
    
    private func commit() {
        store.commitRename(pending, to: trimmed)
    }
}
