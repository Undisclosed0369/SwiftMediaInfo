//
//  FolderSidebar.swift
//  SwiftMediaInfo
//
//  The file list beside a folder tab's report (see FolderContents for how
//  the list is made, MediaStore+Tabs for switching files).
//
//  One row per media file, the selected one highlighted. Clicking a row shows
//  that file in the same tab; middle-clicking opens it in a tab of its own.
//  Files in subfolders carry their subfolder path, so two files with the same
//  name are never ambiguous.
//

import SwiftUI

struct FolderSidebar: View {
    let folder: FolderContents
    let tabID: UUID

    @EnvironmentObject var store: MediaStore

    private var selectedURL: URL? { store.currentFile?.url }

    private var position: Int? {
        guard let selectedURL else { return nil }
        return folder.items.firstIndex(of: selectedURL).map { $0 + 1 }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)

            if folder.items.isEmpty {
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(folder.items, id: \.self) { url in
                                FolderRow(
                                    url: url,
                                    subfolder: folder.subfolderPath(of: url),
                                    isSelected: url == selectedURL
                                ) {
                                    store.selectFolderItem(url, inTab: tabID)
                                }
                                .id(url)
                            }
                        }
                        .padding(SMI.Spacing.small)
                    }
                    .onChange(of: selectedURL) { _, url in
                        guard let url else { return }
                        smiWithAnimation(SMI.Motion.smooth) {
                            proxy.scrollTo(url, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 260)
        .background(Color.primary.opacity(0.025))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Files in \(folder.name)")
    }

    private var header: some View {
        HStack(spacing: SMI.Spacing.small) {
            Image(systemName: "folder.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color.brandViolet)

            VStack(alignment: .leading, spacing: 1) {
                Text(folder.name)
                    .font(SMI.Typo.bodyStrong)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(countText)
                    .font(SMI.Typo.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SMI.Spacing.medium)
        .padding(.vertical, SMI.Spacing.small + 2)
        .help(folder.url.path(percentEncoded: false))
    }

    private var countText: String {
        if folder.isScanning { return "Reading folder…" }
        let count = folder.items.count
        let files = count == 1 ? "1 file" : "\(count) files"
        guard let position, count > 1 else { return files }
        return "\(position) of \(files)"
    }
}

// MARK: - Row

private struct FolderRow: View {
    let url: URL
    let subfolder: String
    let isSelected: Bool
    let action: () -> Void

    @EnvironmentObject var store: MediaStore
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: SMI.Spacing.small) {
                Image(systemName: FileTabBar.symbol(for: url))
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.brandViolet : Color.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent)
                        .font(isSelected ? SMI.Typo.bodyStrong : SMI.Typo.label)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if !subfolder.isEmpty {
                        Text(subfolder)
                            .font(SMI.Typo.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, SMI.Spacing.small + 2)
            .padding(.vertical, SMI.Spacing.snug)
            .background(backdrop)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onMiddleClick { store.openInBackgroundTab(url) }
        .onHover { isHovering = $0 }
        .smiAnimation(SMI.Motion.fade, value: isHovering)
        .help("\(url.lastPathComponent)\nMiddle-click to open in a tab of its own")
        .contextMenu {
            Button("Open in New Tab") {
                store.openInBackgroundTab(url)
            }
            Divider()
            FileActionsMenuItems(store: store, url: url, isCompare: false, excluding: [.rename, .trash])
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subfolder.isEmpty ? url.lastPathComponent : "\(url.lastPathComponent), in \(subfolder)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var backdrop: some View {
        let shape = RoundedRectangle(cornerRadius: SMI.Radius.chip + 2, style: .continuous)

        if isSelected {
            shape
                .fill(Color.brandViolet.opacity(0.15))
                .overlay(shape.strokeBorder(Color.brandViolet.opacity(0.30), lineWidth: 0.7))
        } else if isHovering {
            shape.fill(SMI.Palette.hoverWash)
        }
    }
}

// MARK: - Folder states

/// Shown in place of a report while a folder is read, or when it holds no
/// media at all.
struct FolderMessage: View {
    let icon: String
    let title: String
    let message: String
    let showsProgress: Bool

    var body: some View {
        VStack(spacing: SMI.Spacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.brandViolet.opacity(0.6))

            Text(title)
                .font(SMI.Typo.title)

            Text(message)
                .font(SMI.Typo.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(.brandViolet)
                    .padding(.top, SMI.Spacing.tight)
            }
        }
        .padding(SMI.Spacing.huge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
