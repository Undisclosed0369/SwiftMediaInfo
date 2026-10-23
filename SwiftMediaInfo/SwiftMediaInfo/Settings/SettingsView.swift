//
//  SettingsView.swift
//  SwiftMediaInfo
//
//  The Settings window (⌘,).
//
//  STRUCTURE
//
//  A sidebar rather than top tabs. Seven pages fit a sidebar comfortably and
//  it leaves room to grow; top tabs start crowding at about four. The selected
//  row's capsule slides between positions via matchedGeometryEffect, matching
//  how the main window's tab bar behaves — one object moving, not two swapping.
//
//  This file holds the window, its sidebar and the building blocks every page
//  uses (SettingsGroup, SettingsRow, settingsNotice). Each page has its own
//  file: GeneralSettings, AppearanceSettings, AnalysisSettings,
//  ToolsSettings, IntelligenceSettings, PrivacySettings and AdvancedSettings.
//
//  EVERY CONTROL EXPLAINS ITSELF
//
//  Each row carries a one-line description under its title. A settings window
//  that lists switches without saying what they do makes the person guess, and
//  guessing about a preference usually means leaving it alone.
//

import SwiftUI
import AppKit

// MARK: - Sections

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case analysis
    case mediaInfo
    case intelligence
    case privacy
    case advanced
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .general:   return "General"
        case .appearance: return "Appearance"
        case .analysis:  return "Analysis"
        case .mediaInfo: return "Tools"
        case .intelligence: return "Siri AI"
        case .privacy:   return "Privacy"
        case .advanced:  return "Advanced"
        }
    }
    
    var icon: String {
        switch self {
        case .general:   return "gearshape"
        case .appearance: return "paintbrush"
        case .analysis:  return "waveform.badge.magnifyingglass"
        case .mediaInfo: return "shippingbox"
        case .intelligence: return "siri"
        case .privacy:   return "hand.raised"
        case .advanced:  return "wrench.and.screwdriver"
        }
    }
    
    var tint: Color {
        switch self {
        case .general:   return .brandBlue
        case .appearance: return .brandViolet
        case .analysis:  return .brandTeal
        case .mediaInfo: return .brandGreen
        case .intelligence: return .brandViolet
        case .privacy:   return .brandPink
        case .advanced:  return .brandAmber
        }
    }
    
    var subtitle: String {
        switch self {
        case .general:   return "Startup and recent files"
        case .appearance: return "Theme, glass, and motion"
        case .analysis:  return "Timeouts and hashing"
        case .mediaInfo: return "MediaInfo and ffmpeg"
        case .intelligence: return "On-device · macOS 27"
        case .privacy:   return "What leaves your Mac"
        case .advanced:  return "Diagnostics and reset"
        }
    }
}

// MARK: - Root

/// Thin wrapper.
///
/// The scale is injected by the scene onto *this* view. A view's own
/// `@Environment` properties are resolved before modifiers applied to it are
/// written, so reading the scale here would have given the default of 1.0 —
/// which is exactly what happened: the content pane's subviews scaled because
/// they are children, while the sidebar, built in this view's own body, did
/// not. Moving every scaled metric one level down removes the ambiguity.
struct SettingsView: View {
    var body: some View {
        SettingsContent()
    }
}

private struct SettingsContent: View {
    @Environment(\.smiScale) private var scale
    
    @EnvironmentObject var store: MediaStore
    @State private var selection: SettingsSection = .general
    @Namespace private var sidebarNamespace
    
    // The sidebar's app icon is pressable, like the About window's: two taps
    // opens the app's page.
    //
    // Two rather than About's four, because these are different things. About's
    // is a joke that should be hard to trip over; this is a shortcut that
    // should be easy to find once and impossible to hit by accident. One tap
    // would fire every time someone clicked past the icon on their way to the
    // sidebar.
    //
    // The counter resets itself after a second, so a tap now and a tap in a
    // minute are not read as a double tap.
    @State private var iconTapCount = 0
    @State private var iconTapResetTask: Task<Void, Never>? = nil
    
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.4)
            content
        }
        // Fixed. Zoom scales the contents, not the window — the same
        // behaviour as the main window, where ⌘+ enlarges text and the
        // window stays put.
        .frame(width: scale.s(720), height: scale.s(520))
        .background {
            ZStack {
                GradientBackground()
                    .opacity(0.5)
                Rectangle().fill(.ultraThinMaterial)
            }
            .ignoresSafeArea()
        }
    }
    
    // MARK: Sidebar
    
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: scale.s(SMI.Spacing.tight)) {
            Text("Settings")
                .font(scale.font(20, .semibold))
                .padding(.horizontal, scale.s(SMI.Spacing.medium))
                .padding(.top, scale.s(SMI.Spacing.xLarge))
                .padding(.bottom, scale.s(SMI.Spacing.medium))
            
            ForEach(SettingsSection.allCases) { section in
                SidebarRow(
                    section: section,
                    isSelected: selection == section,
                    namespace: sidebarNamespace
                ) {
                    smiWithAnimation(SMI.Motion.smooth) {
                        selection = section
                    }
                }
            }
            
            Spacer(minLength: 0)
            
            // App identity. The icon is taken from the running application
            // rather than an asset name, so it always matches whatever the
            // bundle actually ships — including any future icon change.
            // Centred with explicit spacers rather than `maxWidth: .infinity`.
            // The enclosing VStack is leading-aligned and its width is set by a
            // later modifier, so an infinite-width frame here resolved against
            // the natural width and the icon sat against the left edge.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                
                VStack(spacing: scale.s(SMI.Spacing.small)) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: scale.s(85), height: scale.s(85))
                        .smiShadow(SMI.Elevation.resting(.brandViolet))
                        .pressableIcon { tapSidebarIcon() }
                        .help("Open the project on GitHub")
                        .accessibilityLabel("SwiftMediaInfo icon")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Opens the project on GitHub")
                    
                    VStack(spacing: 1) {
                        Text("SwiftMediaInfo")
                            .font(scale.font(11, .medium))
                            .foregroundStyle(.secondary)
                        Text(appVersionString)
                            .font(scale.font(11, .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .multilineTextAlignment(.center)
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, scale.s(SMI.Spacing.medium))
            .padding(.bottom, scale.s(SMI.Spacing.large))
        }
        .frame(width: scale.s(200))
        .padding(.horizontal, scale.s(SMI.Spacing.small))
    }
    
    // MARK: Content
    
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: scale.s(SMI.Spacing.xLarge)) {
                header
                
                Group {
                    switch selection {
                    case .general:    GeneralSettings()
                    case .appearance: AppearanceSettings()
                    case .analysis:   AnalysisSettings()
                    case .mediaInfo:  ToolsSettings()
                    case .intelligence: IntelligenceSettings()
                    case .privacy:    PrivacySettings()
                    case .advanced:   AdvancedSettings()
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 10)),
                        removal: .opacity
                    )
                )
            }
            .padding(scale.s(SMI.Spacing.xxLarge))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .smiAnimation(SMI.Motion.smooth, value: selection)
    }
    
    private var header: some View {
        HStack(spacing: scale.s(SMI.Spacing.medium)) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                selection.tint.opacity(0.22),
                                selection.tint.opacity(0.05)
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: scale.s(26)
                        )
                    )
                    .frame(width: scale.s(48), height: scale.s(48))
                
                Image(systemName: selection.icon)
                    .font(scale.font(20, .medium))
                    .foregroundStyle(LinearGradient.brandSweep(selection.tint))
            }
            .smiAnimation(SMI.Motion.flourish, value: selection)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(selection.title)
                    .font(scale.font(20, .semibold))
                Text(selection.subtitle)
                    .font(scale.font(12, .medium))
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 0)
        }
    }
    
    // MARK: - Sidebar icon
    
    private func tapSidebarIcon() {
        // Every press moves the icon (PressableIcon), including the first one
        // that does nothing — otherwise half the presses feel like a dead icon.
        iconTapCount += 1
        
        guard iconTapCount >= 2 else {
            // Arm the reset. Cancelled and restarted on each tap, so the pair
            // has to arrive close together.
            iconTapResetTask?.cancel()
            iconTapResetTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                iconTapCount = 0
            }
            return
        }
        
        iconTapResetTask?.cancel()
        iconTapCount = 0
        
        // The app's page rather than the repository. Someone
        // who double-taps an app icon is being curious about the app, not
        // about its source — and the source is one click from the page.
        ProjectLinks.open(ProjectLinks.appPage)
    }
    
    /// Marketing version only — the build number is not shown anywhere in the
    /// app. See the note in AboutView for why.
    private var appVersionString: String {
        guard let short = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String else { return "" }
        
        return "Version \(short)"
    }
}

// MARK: - Sidebar row

private struct SidebarRow: View {
    @Environment(\.smiScale) private var scale
    
    let section: SettingsSection
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    
    @State private var isHovering = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: scale.s(SMI.Spacing.medium) - 2) {
                Image(systemName: section.icon)
                    .font(scale.font(14, isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? section.tint : .secondary)
                    .frame(width: scale.s(22))
                    .symbolEffect(.bounce, value: isSelected)
                
                Text(section.title)
                    .font(scale.font(13, isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, scale.s(SMI.Spacing.medium) - 2)
            .padding(.vertical, scale.s(SMI.Spacing.small) + 1)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: scale.s(SMI.Radius.control), style: .continuous)
                        .fill(section.tint.opacity(reduceTransparency ? 0.28 : 0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: scale.s(SMI.Radius.control), style: .continuous)
                                .strokeBorder(section.tint.opacity(0.32), lineWidth: 0.7)
                        )
                        .matchedGeometryEffect(id: "settings_selection", in: namespace)
                } else if isHovering {
                    RoundedRectangle(cornerRadius: scale.s(SMI.Radius.control), style: .continuous)
                        .fill(SMI.Palette.hoverWash)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle(scale: 0.98))
        .onHover { isHovering = $0 }
        .smiAnimation(SMI.Motion.fade, value: isHovering)
    }
}

// MARK: - Shared building blocks

/// A titled group of related controls.
struct SettingsGroup<Content: View>: View {
    @Environment(\.smiScale) private var scale
    
    let title: String
    var tint: Color = .brandViolet
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: scale.s(SMI.Spacing.small)) {
            GlassSectionHeader(title: title, tint: tint)
            
            VStack(spacing: 0) {
                content()
            }
            .liquidGlass(
                cornerRadius: scale.s(SMI.Radius.card),
                tint: tint,
                borderOpacity: 0.18,
                elevation: SMI.Elevation.resting(tint)
            )
        }
    }
}

/// One row: title, explanation, and a control on the trailing edge.
struct SettingsRow<Control: View>: View {
    @Environment(\.smiScale) private var scale
    
    let title: String
    var explanation: String? = nil
    var isFirst: Bool = false
    @ViewBuilder var control: () -> Control
    
    var body: some View {
        VStack(spacing: 0) {
            if !isFirst {
                Divider().opacity(0.25)
                    .padding(.horizontal, scale.s(SMI.Spacing.large))
            }
            
            HStack(alignment: .center, spacing: scale.s(SMI.Spacing.large)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(scale.font(13, .medium))
                    
                    if let explanation {
                        Text(explanation)
                            .font(scale.font(11, .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                Spacer(minLength: scale.s(SMI.Spacing.medium))
                
                control()
            }
            .padding(.horizontal, scale.s(SMI.Spacing.large))
            .padding(.vertical, scale.s(SMI.Spacing.medium))
        }
    }
}

extension View {
    /// The tinted, outlined box a notice sits in: accessibility settings in
    /// effect, an install that failed, Siri AI's requirement, a warning.
    func settingsNotice(tint: Color, fill: Double = 0.10, stroke: Double = 0.28, scale: SMIScale) -> some View {
        self
            .padding(scale.s(SMI.Spacing.medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: scale.s(SMI.Radius.control), style: .continuous)
                    .fill(tint.opacity(fill))
                    .overlay(
                        RoundedRectangle(cornerRadius: scale.s(SMI.Radius.control), style: .continuous)
                            .strokeBorder(tint.opacity(stroke), lineWidth: 0.7)
                    )
            )
    }
}
