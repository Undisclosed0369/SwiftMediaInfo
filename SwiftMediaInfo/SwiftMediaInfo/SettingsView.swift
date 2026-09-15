//
//  SettingsView.swift
//  SwiftMediaInfo
//
//  PHASE 6 — the Settings window.
//
//  Built from scratch: the old PreferencesView was removed in v1.5, leaving a
//  `defaultViewMode` key that nothing wrote and no way to reach any preference
//  from the UI.
//
//  STRUCTURE
//
//  A sidebar rather than top tabs. Six categories fit a sidebar comfortably and
//  it leaves room to grow; top tabs start crowding at about four. The selected
//  row's capsule slides between positions via matchedGeometryEffect, matching
//  how the main window's tab bar behaves — one object moving, not two swapping.
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
    case privacy
    case advanced
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .general:   return "General"
        case .appearance: return "Appearance"
        case .analysis:  return "Analysis"
        case .mediaInfo: return "MediaInfo"
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
        case .privacy:   return .brandPink
        case .advanced:  return .brandAmber
        }
    }
    
    var subtitle: String {
        switch self {
        case .general:   return "Startup and recent files"
        case .appearance: return "Theme, glass, and motion"
        case .analysis:  return "Timeouts and hashing"
        case .mediaInfo: return "The command-line tool"
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @EnvironmentObject var store: MediaStore
    @State private var selection: SettingsSection = .general
    @Namespace private var sidebarNamespace
    
    // PHASE 11 — the sidebar icon is now pressable, the same way the About
    // window's is. Two taps opens the project page.
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
    @State private var iconNudge = false
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
        .frame(width: scale.s(760), height: scale.s(560))
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
                        .scaleEffect(iconNudge && !reduceMotion ? 0.94 : 1.0)
                        .smiAnimation(SMI.Motion.snap, value: iconNudge)
                        .onTapGesture { tapSidebarIcon() }
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
                    case .mediaInfo:  MediaInfoSettings()
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
        // Fires on both taps, including the first one that does nothing —
        // otherwise half the presses feel like a dead icon.
        iconNudge = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 130_000_000)
            iconNudge = false
        }
        
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
        
        // PHASE 13n. Opens the app's page rather than the repository. Someone
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

// MARK: - General

private struct GeneralSettings: View {
    @Environment(\.smiScale) private var scale
    
    @EnvironmentObject var store: MediaStore
    @AppStorage(LaunchPreference.key) private var launchChoice: String = LaunchPreference.restoreLastValue
    
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
                    Picker("", selection: $launchChoice) {
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
            
            // PHASE 13n. The quiet half of the donate work. The About window
            // has the other one.
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
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @Environment(\.smiScale) private var scale
    
    @EnvironmentObject var store: MediaStore
    @AppStorage(GlassPreference.key) private var glassEnabled: Bool = true
    
    // PHASE 12b. Stored as hex strings; the wells work in Color, so each one
    // gets a binding that converts on the way through.
    @AppStorage(BackgroundPalette.keys[0]) private var hex1: String = Color.brandViolet.smiHex
    @AppStorage(BackgroundPalette.keys[1]) private var hex2: String = Color.brandPink.smiHex
    @AppStorage(BackgroundPalette.keys[2]) private var hex3: String = Color.brandBlue.smiHex
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    private var tint: Color { SettingsSection.appearance.tint }
    
    var body: some View {
        VStack(alignment: .leading, spacing: scale.s(SMI.Spacing.xLarge)) {
            
            SettingsGroup(title: "Theme", tint: tint) {
                SettingsRow(
                    title: "Appearance",
                    explanation: "Following the system matches whatever macOS is set to, including automatic switching at sunset.",
                    isFirst: true
                ) {
                    Picker("", selection: appearanceBinding) {
                        Text("System").tag(AppearanceMode.system)
                        Text("Light").tag(AppearanceMode.light)
                        Text("Dark").tag(AppearanceMode.dark)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: scale.s(210))
                }
            }
            
            SettingsGroup(title: "Effects", tint: tint) {
                SettingsRow(
                    title: "Liquid Glass",
                    explanation: "Translucent panels that pick up colour from the background. Turning this off draws solid surfaces instead, which is noticeably cheaper to render on battery.",
                    isFirst: true
                ) {
                    Toggle("", isOn: glassBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(tint)
                }
                
                SettingsRow(
                    title: "Background",
                    explanation: backgroundModeExplanation
                ) {
                    Picker("", selection: backgroundModeBinding) {
                        ForEach(BackgroundMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: scale.s(210))
                }
                
                // Both rows hidden when the background is off, because
                // colours that visibly change nothing are worse than no
                // colours at all.
                if store.backgroundMode != .off {
                    
                    // PHASE 13l. Presets come first: it is the easier choice
                    // and the one most people will make, and putting the three
                    // pickers above it would ask everyone to solve the harder
                    // problem before learning there was an easier one.
                    SettingsRow(
                        title: "Palette",
                        explanation: presetExplanation
                    ) {
                        HStack(spacing: scale.s(SMI.Spacing.snug)) {
                            ForEach(GradientPreset.allCases) { preset in
                                presetSwatch(preset)
                            }
                        }
                    }
                    
                    SettingsRow(
                        title: "Background colours",
                        explanation: "The three shades the wash is built from. They apply to both Static and Animated."
                    ) {
                        VStack(alignment: .trailing, spacing: scale.s(SMI.Spacing.snug)) {
                            HStack(spacing: scale.s(SMI.Spacing.small)) {
                                colorWell(color1, label: "First background colour")
                                colorWell(color2, label: "Second background colour")
                                colorWell(color3, label: "Third background colour")
                            }
                            
                            // The same three colours as text.
                            //
                            // A colour picker is the right tool for choosing a
                            // colour and the wrong one for reproducing a
                            // specific colour you already have — from a brand
                            // guide, a screenshot, or another machine. Hex is
                            // how colours are written down everywhere else, so
                            // it is offered alongside rather than instead.
                            HStack(spacing: scale.s(SMI.Spacing.tight)) {
                                hexField($hex1, fallback: .brandViolet, label: "First background colour, hex")
                                hexField($hex2, fallback: .brandPink, label: "Second background colour, hex")
                                hexField($hex3, fallback: .brandBlue, label: "Third background colour, hex")
                            }
                        }
                    }
                }
                
                SettingsRow(
                    title: "Default text size",
                    explanation: "The size metadata values are drawn at. ⌘+ and ⌘− change this at any time."
                ) {
                    HStack(spacing: scale.s(SMI.Spacing.small)) {
                        Text("\(Int(store.fontSize)) pt")
                            .font(scale.font(12, .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: scale.s(44), alignment: .trailing)
                        
                        Stepper("", value: $store.fontSize, in: 8...48, step: 1)
                            .labelsHidden()
                    }
                }
            }
            
            // Surfaced rather than silently applied. If the system is overriding
            // a preference here, saying so is less confusing than a switch that
            // appears to do nothing.
            if reduceMotion || reduceTransparency {
                accessibilityNotice
            }
        }
    }
    
    private var accessibilityNotice: some View {
        HStack(alignment: .top, spacing: scale.s(SMI.Spacing.medium) - 2) {
            Image(systemName: "figure.wave.circle")
                .font(scale.font(15))
                .foregroundStyle(tint)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("System accessibility settings are active")
                    .font(scale.font(12, .medium))
                
                Text(accessibilityDetail)
                    .font(scale.font(11, .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
        .padding(scale.s(SMI.Spacing.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: scale.s(SMI.Radius.control), style: .continuous)
                .fill(tint.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: scale.s(SMI.Radius.control), style: .continuous)
                        .strokeBorder(tint.opacity(0.22), lineWidth: 0.7)
                )
        )
    }
    
    private var accessibilityDetail: String {
        switch (reduceMotion, reduceTransparency) {
        case (true, true):
            return "Reduce Motion and Reduce Transparency are on in System Settings, so animation is minimised and panels are drawn solid regardless of the choices above."
        case (true, false):
            return "Reduce Motion is on in System Settings, so animation is kept to a minimum regardless of the choices above."
        default:
            return "Reduce Transparency is on in System Settings, so panels are drawn solid regardless of the Liquid Glass setting."
        }
    }
    
    // MARK: - Effect bindings
    //
    // PHASE 12b FIX. All three of these previously wrote straight through, and
    // all three produced "Publishing changes from within view updates is not
    // allowed" in the console.
    //
    // WHY IT HAPPENS
    //
    // A segmented Picker and a Toggle call their binding's setter *during*
    // SwiftUI's update pass, not after it. Each of these setters then mutates
    // something observable — an @AppStorage value, or a property on the store —
    // which immediately announces "I changed" to a SwiftUI that is still busy
    // working out what the last change meant.
    //
    // SwiftUI does not crash on this, which is why it reads as a mild blue
    // warning. It is telling the truth about the risk, though: the second
    // change can be applied against a half-computed view tree, and the visible
    // result is a control that occasionally needs two clicks or animates from
    // the wrong starting state.
    //
    // THE FIX
    //
    // Move the write to the very next turn of the run loop, so the current
    // update finishes first. `RunLoop.main.perform` rather than
    // `DispatchQueue.main.async` — the project already learned that lesson: the
    // dispatch form takes a QoS and can invert priority against the main
    // thread's own work. The delay is a single tick and is not perceptible.
    //
    // ON `MainActor.assumeIsolated`
    //
    // `RunLoop.main.perform` takes a plain closure with no actor annotation, so
    // as far as the compiler can see the body might run anywhere — hence
    // "main actor-isolated method in a synchronous nonisolated context" on
    // everything inside it.
    //
    // It does always run on the main thread. That is what `RunLoop.main` means.
    // `assumeIsolated` is how you say so: it asserts the fact rather than
    // hopping to the actor, so there is no extra suspension and no change in
    // timing — it simply lets the compiler verify what is already true.
    //
    // This is not a way of silencing the warning. If the assumption were ever
    // wrong the assertion would trap immediately and loudly, which is the
    // correct outcome and far better than the silent data race the warning is
    // pointing at.
    
    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(
            get: { store.appearanceMode },
            set: { newValue in
                RunLoop.main.perform {
                    MainActor.assumeIsolated { store.setAppearance(newValue) }
                }
            }
        )
    }
    
    private var glassBinding: Binding<Bool> {
        Binding(
            get: { glassEnabled },
            set: { newValue in
                RunLoop.main.perform {
                    MainActor.assumeIsolated {
                        smiWithAnimation(SMI.Motion.smooth) { glassEnabled = newValue }
                    }
                }
            }
        )
    }
    
    private var backgroundModeBinding: Binding<BackgroundMode> {
        Binding(
            get: { store.backgroundMode },
            set: { newValue in
                // Deferred for the reason described above the appearance
                // binding. This is the one you saw the warning from.
                RunLoop.main.perform {
                    MainActor.assumeIsolated {
                        smiWithAnimation(SMI.Motion.smooth) { store.backgroundMode = newValue }
                    }
                }
            }
        )
    }
    
    /// The explanation under the picker changes with the choice, so the row
    /// describes the option you are actually on rather than all three at once.
    private var backgroundModeExplanation: String {
        store.backgroundMode.explanation
    }
    
    // MARK: - Background palette
    //
    // Each well binds through hex. The `set` half writes the canonical string
    // form, so what lands in preferences is always something the parser can
    // read back — rather than whatever a wide-gamut picker happened to hand us.
    
    private var color1: Binding<Color> {
        Binding(
            get: { Color(smiHex: hex1) ?? .brandViolet },
            set: { hex1 = $0.smiHex }
        )
    }
    
    private var color2: Binding<Color> {
        Binding(
            get: { Color(smiHex: hex2) ?? .brandPink },
            set: { hex2 = $0.smiHex }
        )
    }
    
    private var color3: Binding<Color> {
        Binding(
            get: { Color(smiHex: hex3) ?? .brandBlue },
            set: { hex3 = $0.smiHex }
        )
    }
    
    // MARK: - Presets
    //
    // The Reset button that used to sit beside the colour wells is gone. It did
    // exactly what choosing Signature now does, and a control that duplicates
    // another control is a control you have to explain. Selecting Signature is
    // the reset, and unlike a Reset button it says what it is returning you to.
    
    private var currentPreset: GradientPreset? {
        GradientPreset.matching([hex1, hex2, hex3])
    }
    
    private var presetExplanation: String {
        if let currentPreset {
            return "\(currentPreset.title). Pick another, or set the three shades yourself below."
        }
        return "Your own colours. Pick a palette to replace them, or keep adjusting below."
    }
    
    private func apply(_ preset: GradientPreset) {
        let hexes = preset.hexes
        smiWithAnimation(SMI.Motion.smooth) {
            hex1 = hexes[0]
            hex2 = hexes[1]
            hex3 = hexes[2]
        }
    }
    
    /// A live rendering of the preset, not a picture of one.
    ///
    /// Drawn from the same colours the background will use, so a swatch can
    /// never fall out of step with what selecting it actually does — which a
    /// hand-tuned preview eventually would.
    private func presetSwatch(_ preset: GradientPreset) -> some View {
        let selected = currentPreset == preset
        let shape = RoundedRectangle(cornerRadius: scale.s(SMI.Radius.chip), style: .continuous)
        
        return Button {
            apply(preset)
        } label: {
            VStack(spacing: scale.s(SMI.Spacing.hair) + 2) {
                shape
                    .fill(
                        LinearGradient(
                            colors: preset.colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: scale.s(46), height: scale.s(26))
                    .overlay(
                        // The selected swatch gains a ring rather than a tick.
                        // A tick would have to sit on top of the colours it is
                        // marking, and there is no single ink colour that stays
                        // legible across four different palettes.
                        shape.strokeBorder(
                            selected ? Color.primary.opacity(0.85) : Color.primary.opacity(0.12),
                            lineWidth: selected ? 2 : 1
                        )
                    )
                // A clear tint renders no shadow, which keeps this one
                // expression rather than branching the view type.
                    .smiShadow(SMI.Elevation.resting(selected ? preset.colors[0] : .clear))
                
                // The name, under the colours it belongs to.
                //
                // The tooltip already carried it, but a tooltip is a reward for
                // hovering — these have names worth knowing, and a row of four
                // unlabelled gradients asks the reader to remember which is
                // which by hue alone.
                Text(preset.title)
                    .font(scale.font(10, selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle(scale: 0.94))
        .help(preset.title)
        .accessibilityLabel("\(preset.title) palette")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
    
    /// A hex field bound to the stored string, validated on commit.
    ///
    /// WHY IT DOES NOT WRITE ON EVERY KEYSTROKE
    ///
    /// Typing "8D42F5" passes through "8", "8D", "8D4" and so on, and all but
    /// the last are invalid. Writing each of those to preferences would repaint
    /// the whole window several times per character and leave the background a
    /// different colour between keystrokes.
    ///
    /// So the text is held locally while it is being typed and committed on
    /// Return or on losing focus. Anything unparseable snaps back to the value
    /// that is actually stored, which tells the reader their input was rejected
    /// without an alert saying so.
    private func hexField(
        _ stored: Binding<String>,
        fallback: Color,
        label: String
    ) -> some View {
        HexColorField(stored: stored, fallback: fallback, accessibilityLabel: label)
            .frame(width: scale.s(76))
            .font(scale.font(11, .regular, .monospaced))
    }
    
    /// `supportsOpacity: false` on purpose. The blobs are drawn at a fixed 0.28
    /// so they blend into a wash rather than three discs; letting someone pick
    /// a transparent colour would multiply two opacities together and produce a
    /// blob that is simply invisible, with no clue why.
    private func colorWell(_ binding: Binding<Color>, label: String) -> some View {
        ColorPicker("", selection: binding, supportsOpacity: false)
            .labelsHidden()
            .frame(width: scale.s(40))
            .accessibilityLabel(label)
    }
}

// MARK: - Analysis

private struct AnalysisSettings: View {
    @Environment(\.smiScale) private var scale
    
    @EnvironmentObject var store: MediaStore
    // PHASE 10 — three states, not a switch. "Manual" is a real answer that a
    // boolean cannot express: eligible, but not until I say so.
    // Reads the shipped default rather than naming a case. This line said
    // `.always` while `HashPolicy.current` said `.manual`, which on a fresh
    // install would have shown "On" selected in this picker while the engine
    // behaved as "Manual" — a settings screen lying about the setting it
    // configures. One name, one place.
    @AppStorage(HashPolicy.key) private var hashPolicyRaw: String = HashPolicy.shippedDefault.rawValue
    
    /// Recomputed when the view redraws, which is enough — the only thing that
    /// changes it inside Settings is the Clear button right next to it.
    @State private var cachedHashCount: Int = 0
    @State private var cachedHashSize: String = "0 bytes"
    @State private var cachedAnalysisCount: Int = 0
    @State private var cachedAnalysisSize: String = "Zero KB"
    @State private var customTimeoutText: String = ""
    
    private var tint: Color { SettingsSection.analysis.tint }
    
    /// The presets, plus a custom option. 60s is the default as of Phase 11:
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
                    Picker("", selection: timeoutChoiceBinding) {
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
            
            SettingsGroup(title: "Checksums", tint: tint) {
                SettingsRow(
                    title: "SHA-256 for files over 10 GB",
                    explanation: "Hashing reads the whole file, so a 50 GB file means several minutes of sustained disk activity. Only files over 10 GB are hashed — smaller files show no checksum. \(HashPolicy.current.explanation)",
                    isFirst: true
                ) {
                    Picker("", selection: hashPolicyBinding) {
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
                        
                        // Fixed size for the same reason as the toolbar labels
                        // in Phase 8b: without it the label is treated as
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

// MARK: - MediaInfo

private struct MediaInfoSettings: View {
    @Environment(\.smiScale) private var scale
    
    // PHASE 9 — the shared instance, so an install started here is visible in
    // the status bar and vice versa, and neither can start a second `brew`
    // while the other is running.
    @ObservedObject private var installer = DependencyInstaller.shared
    
    // Needed so an install started here can re-read whatever file is open in
    // the main window, exactly as the status bar's install does.
    @EnvironmentObject private var store: MediaStore
    
    @State private var version: String? = nil
    @State private var isChecking = false
    @State private var resolvedPath: String? = nil
    
    private var tint: Color { SettingsSection.mediaInfo.tint }
    
    private var isInstalled: Bool { resolvedPath != nil }
    
    private var installExplanation: String {
        if isInstalled {
            return "Already installed. Reinstalling would upgrade it to the latest version Homebrew has."
        }
        if DependencyInstaller.isHomebrewInstalled {
            return "Runs brew install mediainfo for you. Homebrew prints no progress percentage, so there is a spinner rather than a bar that would only be guessing."
        }
        return "Homebrew isn't installed. Opening brew.sh is the first step; come back here afterwards."
    }
    
    @ViewBuilder
    private var installControl: some View {
        switch installer.state {
        case .installing:
            HStack(spacing: scale.s(SMI.Spacing.small)) {
                ProgressView().controlSize(.small)
                Text("Installing…")
                    .font(scale.font(12, .medium))
                    .foregroundStyle(.secondary)
            }
            
        case .succeeded:
            HStack(spacing: scale.s(SMI.Spacing.snug)) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(SMI.Palette.success)
                Text("Installed")
                    .font(scale.font(12, .medium))
                    .foregroundStyle(.secondary)
            }
            
        default:
            Button(isInstalled ? "Reinstall" : "Install") {
                installer.install("mediainfo") {
                    refresh()
                    store.retryAfterDependencyInstall()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .disabled(installer.isInstalling)
        }
    }
    
    private func installFailureNotice(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: scale.s(SMI.Spacing.medium) - 2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SMI.Palette.warning)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Installation didn't finish")
                    .font(scale.font(12, .medium))
                Text(reason)
                    .font(scale.font(11, .regular, .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
            
            Button("Dismiss") { installer.reset() }
                .buttonStyle(.bordered)
        }
        .padding(scale.s(SMI.Spacing.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: scale.s(SMI.Radius.control), style: .continuous)
                .fill(SMI.Palette.warning.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: scale.s(SMI.Radius.control), style: .continuous)
                        .strokeBorder(SMI.Palette.warning.opacity(0.28), lineWidth: 0.7)
                )
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: scale.s(SMI.Spacing.xLarge)) {
            
            SettingsGroup(title: "Installation", tint: tint) {
                SettingsRow(
                    title: "Status",
                    explanation: "SwiftMediaInfo reads metadata by running the MediaInfo command-line tool. Everything the app shows comes from it.",
                    isFirst: true
                ) {
                    statusBadge
                }
                
                SettingsRow(
                    title: "Version",
                    explanation: "Reported by MediaInfo itself."
                ) {
                    Group {
                        if isChecking {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(version ?? "—")
                                .font(scale.font(11, .regular, .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: scale.s(260), alignment: .trailing)
                        }
                    }
                }
                
                SettingsRow(
                    title: "Location",
                    explanation: "Where the binary was found. Homebrew installs to /opt/homebrew on Apple silicon and /usr/local on Intel."
                ) {
                    Text(resolvedPath ?? "Not found")
                        .font(scale.font(11, .regular, .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: scale.s(260), alignment: .trailing)
                }
                
                SettingsRow(
                    title: "Check again",
                    explanation: "Re-scans the usual locations. Useful straight after installing or upgrading MediaInfo."
                ) {
                    Button("Re-detect") { refresh() }
                        .buttonStyle(.bordered)
                        .disabled(isChecking)
                }
            }
            
            SettingsGroup(title: "Getting It", tint: tint) {
                SettingsRow(
                    title: "Install MediaInfo",
                    explanation: installExplanation,
                    isFirst: true
                ) {
                    installControl
                }
                
                SettingsRow(
                    title: "Download page",
                    explanation: "Official builds from MediaArea, if you'd rather not use Homebrew."
                ) {
                    Button("Open") {
                        ProjectLinks.open(ProjectLinks.mediaAreaDownload)
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            if case .failed(let reason) = installer.state {
                installFailureNotice(reason)
            }
        }
        .onAppear { refresh() }
        .smiAnimation(SMI.Motion.smooth, value: installer.state)
    }
    
    private var statusBadge: some View {
        let installed = resolvedPath != nil
        return HStack(spacing: scale.s(SMI.Spacing.snug)) {
            Image(systemName: installed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(installed ? SMI.Palette.success : SMI.Palette.warning)
            Text(installed ? "Installed" : "Not found")
                .font(scale.font(12, .medium))
                .foregroundStyle(.secondary)
        }
    }
    
    private func refresh() {
        isChecking = true
        MediaEngine.refreshBinaryLocation()
        resolvedPath = MediaEngine.resolveBinaryPath()
        
        Task {
            // Forced, because this runs from Re-detect as well as on appear,
            // and the whole point of Re-detect is to ignore what is cached.
            await store.loadMediaInfoVersion(force: true)
            await MainActor.run {
                version = store.mediaInfoVersion
                isChecking = false
            }
        }
    }
}

// MARK: - Hex colour field
//
// Its own view because it needs somewhere to keep what is being typed. A
// computed binding cannot hold a half-finished string, and without one every
// keystroke would either be written straight to preferences or thrown away.

private struct HexColorField: View {
    @Binding var stored: String
    let fallback: Color
    let accessibilityLabel: String
    
    @State private var text: String = ""
    @FocusState private var focused: Bool
    
    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .focused($focused)
            .onAppear { text = stored }
        // Kept in step when something else changes the colour — choosing a
        // preset, using the picker, or Restore Defaults. Without this the
        // field would go on showing whatever it showed before.
            .onChange(of: stored) { _, new in
                if !focused { text = new }
            }
            .onSubmit { commit() }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
            .accessibilityLabel(accessibilityLabel)
            .help("A six-digit hex colour, with or without the leading #")
    }
    
    private func commit() {
        // `Color(smiHex:)` accepts an optional leading # and returns nil on
        // anything malformed, so it is both the parser and the validator.
        if let parsed = Color(smiHex: text) {
            let canonical = parsed.smiHex
            if canonical != stored {
                smiWithAnimation(SMI.Motion.smooth) { stored = canonical }
            }
            // Rewritten in the canonical form, so "8d42f5" becomes "#8D42F5"
            // and the reader can see that it was understood.
            text = canonical
        } else {
            // Rejected. Snapping back is the whole message.
            text = stored
        }
    }
}

// MARK: - Privacy

private struct PrivacySettings: View {
    @Environment(\.smiScale) private var scale
    
    @AppStorage(PrivacyPreference.shareKey) private var shareMode: String = SharePrivacyMode.always.rawValue
    @AppStorage(PrivacyPreference.localKey) private var localMode: String = LocalPrivacyMode.unmodified.rawValue
    
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
        .padding(scale.s(SMI.Spacing.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: scale.s(SMI.Radius.control), style: .continuous)
                .fill(SMI.Palette.warning.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: scale.s(SMI.Radius.control), style: .continuous)
                        .strokeBorder(SMI.Palette.warning.opacity(0.28), lineWidth: 0.7)
                )
        )
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
                    Picker("", selection: $shareMode) {
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
                    Picker("", selection: $localMode) {
                        ForEach(LocalPrivacyMode.allCases) { mode in
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

// MARK: - Advanced

private struct AdvancedSettings: View {
    @Environment(\.smiScale) private var scale
    
    @EnvironmentObject var store: MediaStore
    @State private var showResetConfirmation = false
    @State private var didCopyDiagnostics = false
    
    private var tint: Color { SettingsSection.advanced.tint }
    
    /// Read straight from the store so the summary reflects whatever is known
    /// by the time it is copied.
    private var mediaInfoVersion: String? { store.mediaInfoVersion }
    
    var body: some View {
        VStack(alignment: .leading, spacing: scale.s(SMI.Spacing.xLarge)) {
            
            SettingsGroup(title: "Diagnostics", tint: tint) {
                SettingsRow(
                    title: "Environment summary",
                    explanation: "Version, macOS build, MediaInfo location, and your current settings. Handy to paste into a bug report — it contains no file paths or personal data.",
                    isFirst: true
                ) {
                    Button(didCopyDiagnostics ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(diagnosticsText, forType: .string)
                        
                        smiWithAnimation(SMI.Motion.snap) { didCopyDiagnostics = true }
                        
                        Task {
                            try? await Task.sleep(nanoseconds: 1_600_000_000)
                            await MainActor.run {
                                smiWithAnimation(SMI.Motion.fade) { didCopyDiagnostics = false }
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(didCopyDiagnostics ? SMI.Palette.success : nil)
                }
                
                SettingsRow(
                    title: "Report an issue",
                    explanation: "Opens the project's issue tracker on GitHub."
                ) {
                    Button("Open") {
                        ProjectLinks.open(ProjectLinks.issues)
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            SettingsGroup(title: "Reset", tint: tint) {
                SettingsRow(
                    title: "Restore default settings",
                    explanation: "Returns every preference on every page to its original value. Your recent files and the file currently open are left alone.",
                    isFirst: true
                ) {
                    Button("Reset…", role: .destructive) {
                        showResetConfirmation = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .confirmationDialog(
            "Restore default settings?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore Defaults", role: .destructive) {
                smiWithAnimation(SMI.Motion.smooth) { store.resetSettingsToDefaults() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Appearance, effects, analysis, and text size return to their defaults. Recent files are kept.")
        }
    }
    
    private var diagnosticsText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let arch: String
#if arch(arm64)
        arch = "arm64"
#else
        arch = "x86_64"
#endif
        
        // The palette, named where it has a name and spelled out where it
        // does not. A bug report saying "Ember" is instantly reproducible; one
        // saying "custom" is not, and the three hexes are what make the
        // difference between the two.
        let hexes = BackgroundPalette.current.map(\.smiHex)
        let palette = GradientPreset.matching(hexes)?.title
        ?? "custom (\(hexes.joined(separator: ", ")))"
        
        return """
        SwiftMediaInfo \(short) (\(build))
        macOS: \(os)
        Architecture: \(arch)
        MediaInfo: \(MediaEngine.resolveBinaryPath() ?? "not found")
        MediaInfo version: \(mediaInfoVersion ?? "unknown")
        Analysis timeout: \(Int(store.analysisTimeoutSeconds))s
        Liquid Glass: \(GlassPreference.isEnabled ? "on" : "off")
        Background: \(store.backgroundMode.rawValue)
        Palette: \(palette)
        Appearance: \(store.appearanceMode.rawValue)
        Text size: \(Int(store.fontSize))pt
        """
    }
}
