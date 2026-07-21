//
//  ShareUploadView.swift
//  SwiftMediaInfo
//
//  Upload mediainfo results to pb.plz.ac (text) or up.sb (ZIP)
//  and display the resulting URL with copy support.
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
        Button(action: {
            showPopover = true
        }) {
            VStack(spacing: 3) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 21))
                Text("Share")
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(minWidth: 62, minHeight: 47)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .disabled(store.currentFile == nil)
        .help("Upload & share online")
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
        VStack(spacing: 16) {
            // Header
            if store.isUploading {
                uploadingState
            } else if let error = store.shareError {
                errorState(error)
            } else if let url = store.shareResultURL {
                successState(url)
            }
        }
        .padding(24)
        .frame(minWidth: 400)
        .background(.ultraThinMaterial)
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
                
                // Copy button
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                    copied = true
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
