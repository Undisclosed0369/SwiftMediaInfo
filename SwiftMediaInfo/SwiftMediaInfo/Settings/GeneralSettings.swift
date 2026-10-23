//
//  GeneralSettings.swift
//  SwiftMediaInfo
//
//  Settings › General: which view the app opens on, recent files, the
//  Finder right-click menu, and the donate link.
//

import SwiftUI
import AppKit

// MARK: - General

struct GeneralSettings: View {
    @Environment(\.smiScale) private var scale
    
    @EnvironmentObject var store: MediaStore
    @AppStorage(LaunchPreference.key) private var launchChoice: String = LaunchPreference.restoreLastValue
    
    /// The Finder extension's switch. Not stored here: it is read from the
    /// system (FinderExtension) when the page opens and whenever the app
    /// comes back to the front — it may have been changed in System Settings
    /// meanwhile.
    @State private var finderMenuOn = FinderExtension.lastKnownOn
    /// Only the latest change's answer is shown, so flipping the switch
    /// twice quickly never shows the first answer last.
    @State private var finderRequest = 0
    
    private var launchExplanation: String {
        if launchChoice == LaunchPreference.restoreLastValue {
            return "SwiftMediaInfo reopens on whichever tab you were last using. Takes effect the next time the app starts."
        }
        let name = ViewMode(rawValue: launchChoice)?.label ?? "Easy"
        return "SwiftMediaInfo always opens on \(name), whatever you were using last. Takes effect the next time the app starts."
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: scale.s(SMI.Spacing.xLarge)) {
            
            SettingsGroup(title: "On Launch", tint: SettingsSection.general.tint) {
                SettingsRow(
                    title: "Open on",
                    explanation: launchExplanation,
                    isFirst: true
                ) {
                    Picker("Open on", selection: $launchChoice) {
                        Text("Last used tab").tag(LaunchPreference.restoreLastValue)
                        Divider()
                        ForEach(ViewMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: scale.s(190))
                }
            }
            
            SettingsGroup(title: "Recent Files", tint: SettingsSection.general.tint) {
                SettingsRow(
                    title: "Remembered files",
                    explanation: "Shown on the empty screen and in File › Open Recent. Files that have moved or whose drive is disconnected are marked rather than hidden.",
                    isFirst: true
                ) {
                    Text("\(store.recentFileURLs.count) of 10")
                        .font(scale.font(12, .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                
                SettingsRow(
                    title: "Clear recent files",
                    explanation: "Removes the list. The files themselves are untouched."
                ) {
                    Button("Clear") {
                        smiWithAnimation(SMI.Motion.smooth) {
                            store.clearRecentFiles()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.recentFileURLs.isEmpty)
                }
            }
            
            SettingsGroup(title: "Finder", tint: SettingsSection.general.tint) {
                SettingsRow(
                    title: "Right-click menu",
                    explanation: "Adds Open in SwiftMediaInfo to Finder's right-click menu, and Compare in SwiftMediaInfo when two files are selected. The same switch as the one in System Settings › General › Login Items & Extensions.",
                    isFirst: true
                ) {
                    Toggle("Right-click menu", isOn: Binding(get: { finderMenuOn }, set: setFinderMenu))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(SettingsSection.general.tint)
                }
            }
            
            // The quiet half of the donate link; the About window has the
            // other one.
            //
            // It sits last in the pane, below everything functional, because
            // that is what it is worth relative to the settings above it. The
            // explanation states that the app is free before the button is
            // reached, for the same reason the donate page does: an ask that
            // arrives before the reassurance reads as a toll.
            SettingsGroup(title: "Support", tint: SettingsSection.general.tint) {
                SettingsRow(
                    title: "Donate",
                    explanation: "Everything in SwiftMediaInfo is free and always will be. If you have found it useful and would like to say thanks, there is a way to — and nothing changes in the app if you do not.",
                    isFirst: true
                ) {
                    Button("Open") {
                        ProjectLinks.open(ProjectLinks.donate)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .task { await refreshFinderMenu() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshFinderMenu() }
        }
    }
    
    private func setFinderMenu(_ on: Bool) {
        finderMenuOn = on
        finderRequest += 1
        let request = finderRequest
        Task {
            let isOn = await FinderExtension.set(on)
            if request == finderRequest { finderMenuOn = isOn }
        }
    }
    
    private func refreshFinderMenu() async {
        let request = finderRequest
        let isOn = await FinderExtension.isOn()
        if request == finderRequest { finderMenuOn = isOn }
    }
}
