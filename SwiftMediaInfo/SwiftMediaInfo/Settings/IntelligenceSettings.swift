//
//  IntelligenceSettings.swift
//  SwiftMediaInfo
//
//  Settings › Siri AI: whether this Mac can run it (and why not), the
//  on/off switch, and why everything stays on-device.
//

import SwiftUI

// MARK: - Siri AI

/// Siri AI. Only on Macs that support Apple Intelligence, on macOS 27
/// or later, and only with Apple's on-device model; this page says plainly
/// when that isn't this Mac, and why nothing goes to the cloud.
struct IntelligenceSettings: View {
    @Environment(\.smiScale) private var scale
    
    @AppStorage(IntelligencePreference.enabledKey) private var enabled = true
    
    @State private var status = IntelligenceStatus.current
    
    private var tint: Color { SettingsSection.intelligence.tint }
    
    /// macOS 26 or an unsupported Mac: nothing here can be switched on.
    private var unsupported: Bool {
        status == .needsNewerMacOS || status == .deviceNotEligible
    }
    
    private var statusIcon: (String, Color) {
        switch status {
        case .available:                           return ("checkmark.circle.fill", SMI.Palette.success)
        case .needsNewerMacOS, .deviceNotEligible: return ("xmark.circle.fill", SMI.Palette.danger)
        default:                                   return ("exclamationmark.triangle.fill", SMI.Palette.warning)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: scale.s(SMI.Spacing.xLarge)) {
            requirementNotice
            
            SettingsGroup(title: "Siri AI", tint: tint) {
                SettingsRow(
                    title: "Status",
                    explanation: status.detail,
                    isFirst: true
                ) {
                    HStack(spacing: scale.s(SMI.Spacing.snug)) {
                        Image(systemName: statusIcon.0)
                            .foregroundStyle(statusIcon.1)
                        Text(status.title)
                            .font(scale.font(12, .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .frame(maxWidth: scale.s(240), alignment: .trailing)
                }
                
                if status.canOpenSystemSettings {
                    SettingsRow(
                        title: "System Settings",
                        explanation: "Apple Intelligence is switched on in System Settings › Apple Intelligence & Siri."
                    ) {
                        Button("Open") { IntelligencePreference.openSystemSettings() }
                            .buttonStyle(.bordered)
                    }
                }
                
                SettingsRow(
                    title: "Use Siri AI",
                    explanation: unsupported
                    ? "Can’t be turned on here. " + IntelligencePreference.requirement
                    : "Adds Siri AI to the toolbar, the File menu (⇧⌘I) and File Actions. Ask what a file is, check its health, get an overview, or compare two files in Compare Mode — then ask follow-up questions. Off removes it everywhere."
                ) {
                    Toggle("Use Siri AI", isOn: Binding(get: { enabled && !unsupported }, set: { enabled = $0 }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(tint)
                        .disabled(unsupported)
                }
            }
            
            SettingsGroup(title: "On-Device Only", tint: tint) {
                SettingsRow(
                    title: "Everything stays on your Mac",
                    explanation: "Siri AI uses only Apple’s on-device model. The file’s report is read on this Mac and nothing is sent anywhere.",
                    isFirst: true
                ) {
                    rowIcon("lock.shield.fill", tint: SMI.Palette.success)
                }
                
                SettingsRow(
                    title: "Why not Private Cloud Compute?",
                    explanation: "Apple also offers Private Cloud Compute, a larger model on Apple’s servers. SwiftMediaInfo can’t use it: Apple makes it available only to apps it has individually approved, and this app isn’t one of them."
                ) {
                    rowIcon("xmark.icloud", tint: Color.brandBlue)
                }
                
                SettingsRow(
                    title: "The privacy risk it avoids",
                    explanation: "Using it would mean sending each report off your Mac. Even without folder paths, a report carries file names, titles, release groups, languages and dates — enough to reveal what you own and watch. Keeping Siri AI on-device means none of that ever leaves your Mac."
                ) {
                    rowIcon("hand.raised.fill", tint: Color.brandPink)
                }
                
                SettingsRow(
                    title: "Long reports",
                    explanation: "The on-device model reads about 8,000 tokens at a time. Reports longer than that — a remux with dozens of subtitle tracks, say — are shortened to fit: less important fields go first, then extra subtitle and audio tracks are listed on one line. Siri AI says when it has done this."
                ) {
                    rowIcon("scissors", tint: Color.brandAmber)
                }
            }
            
            SettingsGroup(title: "What Siri AI Reads", tint: tint) {
                SettingsRow(
                    title: "The report, never the file",
                    explanation: "MediaInfo’s text report — the same as the Text view — with the full path replaced by just the file name. Asked about health or for an overview, it also reads the app’s own Media Health results and Overview, so its answers match what SwiftMediaInfo shows.",
                    isFirst: true
                ) {
                    rowIcon("doc.text.magnifyingglass", tint: Color.brandTeal)
                }
            }
        }
        .onAppear { status = IntelligenceStatus.current }
    }
    
    /// The pictures beside the explanations: a symbol in a soft tinted
    /// circle, large enough to read at a glance.
    private func rowIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: scale.s(17), weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: scale.s(36), height: scale.s(36))
            .background(Circle().fill(tint.opacity(0.14)))
            .accessibilityHidden(true)
    }
    
    /// Said first and plainly, whatever this Mac is.
    private var requirementNotice: some View {
        HStack(alignment: .top, spacing: scale.s(SMI.Spacing.medium) - 2) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Macs that support Apple Intelligence, on macOS 27 or later")
                    .font(scale.font(12, .semibold))
                Text("Siri AI is built on Apple Intelligence. It only works on Macs that support Apple Intelligence, running macOS 27 or later, with Apple Intelligence turned on. On any other Mac it stays hidden, and everything else in SwiftMediaInfo works as usual.")
                    .font(scale.font(11, .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .settingsNotice(tint: tint, scale: scale)
    }
}
