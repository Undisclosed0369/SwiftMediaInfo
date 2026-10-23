//
//  AppearanceSettings.swift
//  SwiftMediaInfo
//
//  Settings › Appearance: theme, Liquid Glass, the background (mode, preset
//  palettes, custom colours with hex fields, and where the blobs sit in
//  Static), Easy View's Overview, and syntax highlighting. Settings that change the look apply through
//  deferred bindings (see "Effect bindings").
//

import SwiftUI

// MARK: - Appearance

struct AppearanceSettings: View {
    @Environment(\.smiScale) private var scale
    
    @EnvironmentObject var store: MediaStore
    @AppStorage(GlassPreference.key) private var glassEnabled: Bool = true
    @AppStorage(OverviewExpansion.key) private var overviewExpansion: String = OverviewExpansion.shippedDefault.rawValue
    @AppStorage(SyntaxHighlighting.key) private var syntaxHighlighting: String = SyntaxHighlighting.shippedDefault.rawValue
    
    // Stored as hex strings; the wells work in Color, so each one
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
                    Picker("Appearance", selection: appearanceBinding) {
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
                    Toggle("Liquid Glass", isOn: glassBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(tint)
                }
                
                SettingsRow(
                    title: "Background",
                    explanation: backgroundModeExplanation
                ) {
                    Picker("Background", selection: backgroundModeBinding) {
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
                    
                    // Presets come first: it is the easier choice
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
                    
                    // Static only: Animated moves the blobs itself, so a
                    // placement there would be undone a second later.
                    if store.backgroundMode == .staticGradient {
                        SettingsRow(
                            title: "Blob positions",
                            explanation: "Drag the three colours to where you want them. The window follows as you drag."
                        ) {
                            BlobPositionEditor(colors: [
                                Color(smiHex: hex1) ?? .brandViolet,
                                Color(smiHex: hex2) ?? .brandPink,
                                Color(smiHex: hex3) ?? .brandBlue
                            ])
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
            
            SettingsGroup(title: "Code Views", tint: tint) {
                SettingsRow(
                    title: "Syntax highlighting",
                    explanation: "Colours the names, values and punctuation in the JSON and XML views so the structure is easier to follow. Turn it off, or keep it for just one of the two, if you prefer plain text.",
                    isFirst: true
                ) {
                    Picker("Syntax highlighting", selection: $syntaxHighlighting) {
                        ForEach(SyntaxHighlighting.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            
            SettingsGroup(title: "Easy View", tint: tint) {
                SettingsRow(
                    title: "Overview",
                    explanation: "Whether the summary at the top of Easy View starts open. Remember Last keeps it the way you left it; with the other two, clicking its header still opens or closes it for that file.",
                    isFirst: true
                ) {
                    Picker("Overview", selection: $overviewExpansion) {
                        ForEach(OverviewExpansion.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
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
        .settingsNotice(tint: tint, fill: 0.08, stroke: 0.22, scale: scale)
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
    // Each of these defers its write by one run-loop turn. Writing straight
    // through produces "Publishing changes from within view updates is not
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

// MARK: - Blob positions
//
// A small picture of the window's background with the three blobs on it, each
// with a handle to drag. Positions are fractions of the picture, which is the
// window's own shape in miniature, and are written as they change — the
// window behind follows the drag live. Arrow keys move the focused handle for
// anyone not using a pointer.

private struct BlobPositionEditor: View {
    let colors: [Color]

    @Environment(\.smiScale) private var scale
    @AppStorage(StaticBlobLayout.key) private var raw: String = ""
    @FocusState private var focused: Int?

    private static let names = ["First", "Second", "Third"]

    private var points: [CGPoint] { StaticBlobLayout.decode(raw) ?? StaticBlobLayout.defaults }

    var body: some View {
        VStack(alignment: .trailing, spacing: scale.s(SMI.Spacing.snug)) {
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    Rectangle().fill(Color(nsColor: .windowBackgroundColor))
                    // The wash, drawn as the window draws it: the same radii
                    // and opacity, with the blur scaled down to this size.
                    ForEach(0..<3, id: \.self) { index in
                        let r = min(size.width, size.height) * GradientLayerHost.radiusFractions[index]
                        Circle()
                            .fill(colors[index].opacity(Double(GradientLayerHost.discOpacity) * 1.6))
                            .frame(width: r * 2, height: r * 2)
                            .blur(radius: 12)
                            .position(location(index, in: size))
                    }
                    ForEach(0..<3, id: \.self) { index in
                        handle(index, in: size)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: scale.s(SMI.Radius.control), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: scale.s(SMI.Radius.control), style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.7)
                )
            }
            .frame(width: scale.s(210), height: scale.s(131))

            Button("Reset") { raw = "" }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(raw.isEmpty)
                .help("Put the blobs back where they started")
        }
    }

    private func location(_ index: Int, in size: CGSize) -> CGPoint {
        CGPoint(x: points[index].x * size.width, y: points[index].y * size.height)
    }

    private func handle(_ index: Int, in size: CGSize) -> some View {
        Circle()
            .fill(colors[index])
            .frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .overlay(
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(-4)
                    .opacity(focused == index ? 1 : 0)
            )
            .contentShape(Circle().inset(by: -6))
            .position(location(index, in: size))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        move(index, to: CGPoint(x: value.location.x / size.width,
                                                y: value.location.y / size.height))
                    }
            )
            .focusable()
            .focused($focused, equals: index)
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                let step = 0.02
                var p = points[index]
                switch press.key {
                case .leftArrow:  p.x -= step
                case .rightArrow: p.x += step
                case .upArrow:    p.y -= step
                default:          p.y += step
                }
                move(index, to: p)
                return .handled
            }
            .accessibilityElement()
            .accessibilityLabel("\(Self.names[index]) background colour position")
            .accessibilityValue("\(Int(points[index].x * 100)) percent across, \(Int(points[index].y * 100)) percent down")
            .accessibilityHint("Use the arrow keys to move it")
    }

    private func move(_ index: Int, to point: CGPoint) {
        var next = points
        next[index] = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
        raw = StaticBlobLayout.encode(next)
    }
}
