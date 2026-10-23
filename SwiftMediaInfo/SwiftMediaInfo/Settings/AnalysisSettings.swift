//
//  AnalysisSettings.swift
//  SwiftMediaInfo
//
//  Settings › Analysis: the MediaInfo time limit, Media Health's SHA-256
//  check, when files over 10 GB are hashed, and the checksum and analysis
//  caches (size, Show in Finder, Clear).
//

import SwiftUI

// MARK: - Analysis

struct AnalysisSettings: View {
    @Environment(\.smiScale) private var scale
    
    @EnvironmentObject var store: MediaStore
    // Three states, not a switch. "Manual" is a real answer that a boolean
    // cannot express: eligible, but not until I say so. Reads the shipped
    // default rather than naming a case, so on a fresh install the picker
    // always shows what the engine actually does.
    @AppStorage(HashPolicy.key) private var hashPolicyRaw: String = HashPolicy.shippedDefault.rawValue
    @AppStorage(HealthPreference.includeChecksumKey) private var healthIncludesChecksum = HealthPreference.includeChecksumDefault
    
    /// Recomputed when the view redraws, which is enough — the only thing that
    /// changes it inside Settings is the Clear button right next to it.
    @State private var cachedHashCount: Int = 0
    @State private var cachedHashSize: String = "0 bytes"
    @State private var cachedAnalysisCount: Int = 0
    @State private var cachedAnalysisSize: String = "Zero KB"
    @State private var customTimeoutText: String = ""
    
    private var tint: Color { SettingsSection.analysis.tint }
    
    /// The presets, plus a custom option. 60 s is the default:
    /// the slowest real-world file observed took about 40 seconds, so a minute
    /// still clears it, and a file that genuinely needs longer is one click
    /// from two minutes.
    private enum TimeoutChoice: Hashable {
        case oneMinute, twoMinutes, custom
    }
    
    private var currentChoice: TimeoutChoice {
        switch store.analysisTimeoutSeconds {
        case 60:  return .oneMinute
        case 120: return .twoMinutes
        default:  return .custom
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: scale.s(SMI.Spacing.xLarge)) {
            
            SettingsGroup(title: "Time Limit", tint: tint) {
                SettingsRow(
                    title: "Give up after",
                    explanation: "How long a single MediaInfo run may take before it is stopped. Large files on fast drives finish in seconds; the limit exists so a stalled read can't hang the window forever.",
                    isFirst: true
                ) {
                    Picker("Give up after", selection: timeoutChoiceBinding) {
                        Text("1 min").tag(TimeoutChoice.oneMinute)
                        Text("2 min").tag(TimeoutChoice.twoMinutes)
                        Text("Custom").tag(TimeoutChoice.custom)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: scale.s(210))
                }
                
                if currentChoice == .custom {
                    SettingsRow(
                        title: "Custom limit",
                        explanation: "In seconds, up to 3600 (one hour)."
                    ) {
                        HStack(spacing: scale.s(SMI.Spacing.small)) {
                            TextField("", text: $customTimeoutText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: scale.s(82))
                                .multilineTextAlignment(.trailing)
                                .onSubmit(commitCustomTimeout)
                            
                            Text("seconds")
                                .font(scale.font(12, .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            
            SettingsGroup(title: "Media Health", tint: tint) {
                SettingsRow(
                    title: "Include SHA-256 availability",
                    explanation: "Adds a checksum check to Media Health (⇧⌘H). It only appears for files over 10 GB — the only ones that get a checksum — and shows whether one has been calculated yet.",
                    isFirst: true
                ) {
                    Toggle("Include SHA-256 availability", isOn: $healthIncludesChecksum)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(tint)
                }
            }
            
            SettingsGroup(title: "Checksums", tint: tint) {
                SettingsRow(
                    title: "SHA-256 for files over 10 GB",
                    explanation: "Hashing reads the whole file, so a 50 GB file means several minutes of sustained disk activity. Only files over 10 GB are hashed — smaller files show no checksum. \(HashPolicy.current.explanation)",
                    isFirst: true
                ) {
                    Picker("SHA-256 for files over 10 GB", selection: hashPolicyBinding) {
                        ForEach(HashPolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: scale.s(190))
                }
                
                SettingsRow(
                    title: "Remembered checksums",
                    explanation: "Digests are kept between launches so reopening a large file is instant instead of another few minutes of reading. A file that changes is re-hashed automatically — clearing is only needed if you want to force that."
                ) {
                    HStack(spacing: scale.s(SMI.Spacing.small)) {
                        Text(cachedHashCount == 1
                             ? "1 file · \(cachedHashSize)"
                             : "\(cachedHashCount) files · \(cachedHashSize)")
                        .font(scale.font(12, .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        
                        // Fixed size, as the toolbar labels are: without it the
                        // label is treated as
                        // compressible and shortens to "Show in Fin…" while
                        // there is still room in the row.
                        Button("Show in Finder") { HashCache.revealInFinder() }
                            .buttonStyle(.bordered)
                            .fixedSize()
                        
                        Button("Clear") {
                            HashCache.clear()
                            smiWithAnimation(SMI.Motion.snap) {
                                cachedHashCount = 0
                                cachedHashSize  = HashCache.sizeOnDisk
                            }
                        }
                        .buttonStyle(.bordered)
                        .fixedSize()
                        .disabled(cachedHashCount == 0)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                
                SettingsRow(
                    title: "Cached analyses",
                    explanation: "The full MediaInfo output for every file you have opened, kept so reopening is instant instead of running MediaInfo again. Entries record which MediaInfo version produced them, and a file that changes is re-analysed on its own. There is no size limit — clearing is entirely your call."
                ) {
                    HStack(spacing: scale.s(SMI.Spacing.small)) {
                        Text(cachedAnalysisCount == 1
                             ? "1 file · \(cachedAnalysisSize)"
                             : "\(cachedAnalysisCount) files · \(cachedAnalysisSize)")
                        .font(scale.font(12, .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        
                        Button("Show in Finder") { AnalysisCache.revealInFinder() }
                            .buttonStyle(.bordered)
                            .fixedSize()
                        
                        Button("Clear") {
                            AnalysisCache.clear()
                            smiWithAnimation(SMI.Motion.snap) {
                                cachedAnalysisCount = 0
                                cachedAnalysisSize  = AnalysisCache.sizeOnDisk
                            }
                        }
                        .buttonStyle(.bordered)
                        .fixedSize()
                        .disabled(cachedAnalysisCount == 0)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .onAppear {
            customTimeoutText = String(Int(store.analysisTimeoutSeconds))
            cachedHashCount   = HashCache.count
            cachedHashSize    = HashCache.sizeOnDisk
            cachedAnalysisCount = AnalysisCache.count
            cachedAnalysisSize  = AnalysisCache.sizeOnDisk
        }
        .smiAnimation(SMI.Motion.smooth, value: currentChoice)
    }
    
    private var timeoutChoiceBinding: Binding<TimeoutChoice> {
        Binding(
            get: { currentChoice },
            set: { choice in
                smiWithAnimation(SMI.Motion.smooth) {
                    switch choice {
                    case .oneMinute:  store.analysisTimeoutSeconds = 60
                    case .twoMinutes: store.analysisTimeoutSeconds = 120
                    case .custom:
                        // Step off a preset value so the picker stays on Custom.
                        if store.analysisTimeoutSeconds == 60 || store.analysisTimeoutSeconds == 120 {
                            store.analysisTimeoutSeconds = 180
                        }
                        customTimeoutText = String(Int(store.analysisTimeoutSeconds))
                    }
                }
            }
        )
    }
    
    private var hashPolicyBinding: Binding<HashPolicy> {
        Binding(
            get: { HashPolicy(rawValue: hashPolicyRaw) ?? .always },
            set: { newValue in
                smiWithAnimation(SMI.Motion.snap) { hashPolicyRaw = newValue.rawValue }
            }
        )
    }
    
    /// Clamped rather than rejected — an out-of-range entry is corrected in
    /// place so the field never sits showing a value that isn't in effect.
    private func commitCustomTimeout() {
        let parsed = Double(customTimeoutText.trimmingCharacters(in: .whitespaces)) ?? store.analysisTimeoutSeconds
        let clamped = min(max(parsed, 5), MediaEngine.maximumTimeout)
        store.analysisTimeoutSeconds = clamped
        customTimeoutText = String(Int(clamped))
    }
}
