//
//  PrivacySettings.swift
//  SwiftMediaInfo
//
//  Settings › Privacy: paths in shares, copies and exports, paths in HTML,
//  the SHA-256 checksum, and what the empty screen shows. The preferences
//  themselves are in PrivacySanitizer.swift.
//

import SwiftUI

// MARK: - Privacy

struct PrivacySettings: View {
    @Environment(\.smiScale) private var scale
    
    @AppStorage(PrivacyPreference.shareKey) private var shareMode: String = SharePrivacyMode.always.rawValue
    @AppStorage(PrivacyPreference.localKey) private var localMode: String = LocalPrivacyMode.unmodified.rawValue
    @AppStorage(PrivacyPreference.htmlPathsKey) private var htmlPathsMode: String = HTMLPathsMode.never.rawValue
    @AppStorage(PrivacyPreference.checksumKey) private var checksumMode: String = ChecksumPrivacyMode.never.rawValue
    @AppStorage(EmptyScreenPreference.showsFavoritesKey) private var showsFavorites = true
    @AppStorage(EmptyScreenPreference.showsRecentsKey) private var showsRecents = true
    @AppStorage(EmptyScreenPreference.showsTimeSpentKey) private var showsTimeSpent = true
    
    @EnvironmentObject var store: MediaStore
    
    private var tint: Color { SettingsSection.privacy.tint }
    
    private var shareExplanation: String {
        switch SharePrivacyMode(rawValue: shareMode) ?? .always {
        case .always:
            return "MediaInfo reports the full path of every file it reads, which discloses your account name and folder layout. Share strips it, and shows you exactly what was removed before anything is uploaded."
        case .ask:
            return "The review screen before each upload lets you choose, and still shows exactly what would be removed."
        case .never:
            return "Uploads go out exactly as MediaInfo reported them — full paths included. The review screen will say so plainly."
        }
    }
    
    private var htmlPathsExplanation: String {
        let lead = "HTML exports and shares follow this, whatever the two settings above say. "
        switch HTMLPathsMode(rawValue: htmlPathsMode) ?? .never {
        case .always:
            return lead + "Each file’s full path is kept — useful when the HTML is an archive of where your files live."
        case .ask:
            return lead + "Each HTML export asks, and the share review screen lets you choose."
        case .never:
            return lead + "Paths are replaced with just the file name."
        }
    }
    
    private var checksumExplanation: String {
        let lead = "For files over 10 GB whose checksum you have calculated. "
        switch ChecksumPrivacyMode(rawValue: checksumMode) ?? .never {
        case .always:
            return lead + "Copies, exports and shares include it — it proves which exact file the report describes."
        case .ask:
            return lead + "Each copy, export or share asks first, and the share review screen says which you chose."
        case .never:
            return lead + "Copies, exports and shares leave it out."
        }
    }
    
    private var localExplanation: String {
        switch LocalPrivacyMode(rawValue: localMode) ?? .unmodified {
        case .unmodified:
            return "Left exactly as MediaInfo reported it, paths included. These stay on your Mac, where the path is yours and often the reason you exported."
        case .ask:
            return "Each Copy or Export asks whether to keep the path. Asked once per action, not once per file."
        case .always:
            return "Paths are replaced with just the file name, the same as Share. Useful if you routinely paste output into tickets or chats."
        }
    }
    
    private func warningNotice(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: scale.s(SMI.Spacing.medium) - 2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SMI.Palette.warning)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(scale.font(12, .medium))
                Text(detail)
                    .font(scale.font(11, .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
        .settingsNotice(tint: SMI.Palette.warning, scale: scale)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: scale.s(SMI.Spacing.xLarge)) {
            
            SettingsGroup(title: "Sharing", tint: tint) {
                SettingsRow(
                    title: "Remove local paths before upload",
                    explanation: shareExplanation,
                    isFirst: true
                ) {
                    Picker("Remove local paths before upload", selection: $shareMode) {
                        ForEach(SharePrivacyMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: scale.s(210))
                }
                
                SettingsRow(
                    title: "Copy and Export",
                    explanation: localExplanation
                ) {
                    Picker("Copy and Export", selection: $localMode) {
                        ForEach(LocalPrivacyMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: scale.s(210))
                }
                
                SettingsRow(
                    title: "Include paths in HTML",
                    explanation: htmlPathsExplanation
                ) {
                    Picker("Include paths in HTML", selection: $htmlPathsMode) {
                        ForEach(HTMLPathsMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: scale.s(210))
                }
                
                SettingsRow(
                    title: "Include the SHA-256 checksum",
                    explanation: checksumExplanation
                ) {
                    Picker("Include the SHA-256 checksum", selection: $checksumMode) {
                        ForEach(ChecksumPrivacyMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: scale.s(210))
                }
            }
            
            if shareMode == SharePrivacyMode.never.rawValue {
                warningNotice(
                    "Uploads will include your full file paths",
                    detail: "That means your account name and folder layout, on a page anyone with the link can read."
                )
            }
            
            // What the empty screen shows. All off by choice, never by
            // default: hiding them is about who might see your screen.
            SettingsGroup(title: "Empty Screen", tint: tint) {
                SettingsRow(
                    title: "Show Favorites",
                    explanation: "Your starred files, above Recent Files when nothing is open. Hiding them here leaves them in File › Favorites.",
                    isFirst: true
                ) {
                    Toggle("Show Favorites", isOn: $showsFavorites)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(tint)
                }
                
                SettingsRow(
                    title: "Show Recent Files",
                    explanation: "The files you opened lately, when nothing is open. Hiding them here leaves them in File › Open Recent."
                ) {
                    Toggle("Show Recent Files", isOn: $showsRecents)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(tint)
                }
                
                SettingsRow(
                    title: "Show time spent",
                    explanation: "Total time in SwiftMediaInfo so far — \(store.usage.formattedTotal.lowercased()) — with a fun fact about it. It keeps counting while hidden, and never leaves your Mac."
                ) {
                    Toggle("Show time spent", isOn: $showsTimeSpent)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(tint)
                }
            }
            
            SettingsGroup(title: "Network", tint: tint) {
                SettingsRow(
                    title: "When SwiftMediaInfo connects",
                    explanation: "Only when you use Share, and only to the paste service that receives the upload. Nothing is sent in the background, and there is no analytics or telemetry of any kind.",
                    isFirst: true
                ) {
                    Text("Share only")
                        .font(scale.font(12, .medium))
                        .foregroundStyle(.secondary)
                }
                
                SettingsRow(
                    title: "Uploads are public",
                    explanation: "Anyone with the link can read a shared report. Treat the link as the only thing protecting it."
                ) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(SMI.Palette.warning)
                }
            }
        }
        .smiAnimation(SMI.Motion.smooth, value: shareMode)
        .smiAnimation(SMI.Motion.smooth, value: localMode)
    }
}
