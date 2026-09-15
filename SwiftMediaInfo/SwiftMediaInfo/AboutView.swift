//
//  AboutView.swift
//  SwiftMediaInfo
//
//  PHASE 11 — rebuilt on the Liquid Glass design system.
//
//  WHAT WAS HERE BEFORE
//
//  The last pre-v2 view in the app. A flat `.ultraThinMaterial` rectangle, a
//  column of `Text` with hard-coded point sizes, three stock `Divider`s and two
//  system buttons. Nothing in it read from the SMI tokens, nothing scaled with
//  the app zoom, and it was the one window that still looked like v1.5. Opening
//  it from a window built in Phase 2 was a visible seam.
//
//  WHAT IT IS NOW
//
//  The same content, drawn the way the rest of the app is drawn: the animated
//  gradient behind frosted glass, three GlassCards, the SMI type scale, the SMI
//  motion vocabulary, and full zoom scaling so ⌘+ enlarges this window's
//  contents the way it enlarges Settings and Keyboard Shortcuts.
//

import SwiftUI
import AppKit

/// Thin wrapper. Same reason as SettingsView and KeyboardShortcutsView: a view
/// cannot both receive an environment value from a modifier applied to it and
/// read that value in its own body, so the scale is read one level down.
struct AboutView: View {
    var body: some View {
        AboutContent()
    }
}

private struct AboutContent: View {
    @Environment(\.smiScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var store: MediaStore
    
    @State private var easterEggCounter = 0
    @State private var iconNudge = false
    
    // PHASE 13n. The three project URLs that used to live here now live in
    // ProjectLinks, alongside the website and donate addresses this phase
    // adds. Six addresses across three files was one too many places.
    
    private let easterEggURLs = [
        "https://www.youtube.com/watch?v=IAYhEkVtNuQ",
        "https://www.youtube.com/watch?v=figEzfMTwQQ",
        "https://www.youtube.com/watch?v=4NJYWgb6dQM",
        "https://www.youtube.com/watch?v=oNXzMBA9VU4",
        "https://www.youtube.com/watch?v=kPa7bsKwL-c",
        "https://www.youtube.com/watch?v=hOT2XC9nmSU",
        "https://www.youtube.com/watch?v=qA8n3SF_Ths",
        "https://www.youtube.com/watch?v=QCIGciNcCbU",
        "https://www.youtube.com/watch?v=V09yWF2TPRM",
        "https://www.youtube.com/watch?v=f1-eY31Bw7A",
        "https://www.youtube.com/watch?v=89zwKGlc7Yw",
        "https://www.youtube.com/watch?v=m7Bc3pLyij0",
        "https://www.youtube.com/watch?v=gK8J1EDk0iA",
        "https://www.youtube.com/watch?v=_tkb95pZCeA",
        "https://www.youtube.com/watch?v=1RKqOmSkGgM",
        "https://www.youtube.com/watch?v=QMssNXBCCl0",
        "https://www.youtube.com/watch?v=WSJQcgBAyys",
        "https://www.youtube.com/watch?v=5LGUgChapj4",
        "https://www.youtube.com/watch?v=SnXkhkEvNIM",
        "https://www.youtube.com/watch?v=vu-Pf-wxqVk",
        "https://www.youtube.com/watch?v=6PcAb_8ahZE",
        "https://www.youtube.com/watch?v=mp8qmRnyF6w",
        "https://www.youtube.com/watch?v=9wNKEBWD378",
        "https://www.youtube.com/watch?v=m70w-33z6AM",
        "https://www.youtube.com/watch?v=eh31zcCFKaE",
        "https://www.youtube.com/watch?v=0aDIjhtfZqs",
        "https://www.youtube.com/watch?v=IA1wX7wXxKs",
        "https://www.youtube.com/watch?v=ewOPQZZn4SY",
        "https://www.youtube.com/watch?v=ZzeNFsJ8c_E",
        "https://www.youtube.com/watch?v=VRzSqdV9Vl0",
        "https://www.youtube.com/watch?v=dY8wckyLAX4",
        "https://www.youtube.com/watch?v=R0sgfKqikNo",
        "https://www.youtube.com/watch?v=IkOrohzIc5A",
        "https://www.youtube.com/watch?v=nREZsuhN1XI",
        "https://www.youtube.com/watch?v=ZjuA_o6Jzyo",
        "https://www.youtube.com/watch?v=QjihRb2E-YA",
        "https://www.youtube.com/watch?v=NgSFun7F8dI",
        "https://www.youtube.com/watch?v=mV3qKK4b7iI",
        "https://www.youtube.com/watch?v=4FAM-s3vSPY",
        "https://www.youtube.com/watch?v=Oa_I83n2dXk",
        "https://www.youtube.com/watch?v=skQWVrxhe94",
        "https://www.youtube.com/watch?v=ZswilWSyMvI",
        "https://www.youtube.com/watch?v=dYfeWmodOQc",
        "https://www.youtube.com/watch?v=taIeJaL6nR0",
        "https://www.youtube.com/watch?v=fViiLeK24jQ",
        "https://www.youtube.com/watch?v=DjnhLWzytXE",
        "https://www.youtube.com/watch?v=umdWhwZdQds",
        "https://www.youtube.com/watch?v=Xq0joZ24D9Y",
        "https://www.youtube.com/watch?v=UrAhnndvrSU",
        "https://www.youtube.com/watch?v=CY5HP5Q6Ukk",
        "https://www.youtube.com/watch?v=gBkWR-WfEeU",
        "https://www.youtube.com/watch?v=tGv7CUutzqU",
        "https://www.youtube.com/watch?v=Ifr4s3MHdNo",
        "https://www.youtube.com/watch?v=tBoyEVBYvJI",
        "https://www.youtube.com/watch?v=0lagRQ0FzYU",
        "https://www.youtube.com/watch?v=T_lC2O1oIew",
        "https://www.youtube.com/watch?v=4sBKvm14J_g",
        "https://www.youtube.com/watch?v=EMFec9WIXKk",
        "https://www.youtube.com/watch?v=I85OndHTw1E",
        "https://www.youtube.com/watch?v=iOjAO1qMBy0",
        "https://www.youtube.com/watch?v=tJYpZKU81lc",
        "https://www.youtube.com/watch?v=L_2_VqSY2kc",
        "https://www.youtube.com/watch?v=vitil9qMN6A",
        "https://www.youtube.com/watch?v=hW6j9yVo1zI",
        "https://www.youtube.com/watch?v=6woZey07zjM",
        "https://www.youtube.com/watch?v=Qwh0JXQPAXc",
        "https://www.youtube.com/watch?v=urdlQGTtkMs",
        "https://www.youtube.com/watch?v=HHq3WJOHvYk",
        "https://www.youtube.com/watch?v=6RL4Yxu9ccE"
    ]
    
    // MARK: - Bundle facts
    
    private var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
    
    /// Marketing version only. The build number is deliberately not shown
    /// anywhere in the app: it is an internal counter that means something to
    /// whoever cut the release and nothing at all to whoever is reading this
    /// window, and a version that looks like "2.0 (14)" invites the question
    /// "what is 14?" — a question with no useful answer.
    private var versionString: String {
        "Version \(shortVersion)"
    }
    
    private var copyrightText: String {
        let startYear = 2026
        let currentYear = Calendar.current.component(.year, from: Date())
        
        return currentYear == startYear
        ? "© \(startYear) Undisclosed / Data Lass"
        : "© \(startYear)–\(currentYear) Undisclosed / Data Lass"
    }
    
    // MARK: - Body
    
    var body: some View {
        ScrollView {
            VStack(spacing: scale.s(SMI.Spacing.xLarge)) {
                hero
                authorCard
                provenanceCard
                linksCard
                footer
            }
            .padding(.horizontal, scale.s(SMI.Spacing.xxLarge))
            .padding(.top, scale.s(SMI.Spacing.huge))
            .padding(.bottom, scale.s(SMI.Spacing.xLarge))
            .frame(maxWidth: .infinity)
        }
        .frame(width: scale.s(460), height: scale.s(700))
        .background {
            ZStack {
                // Half strength, as in Settings. At full strength the gradient
                // competes with three stacked cards in a narrow window; the
                // glass still has colour to pick up at 0.5.
                GradientBackground()
                    .opacity(0.5)
                Rectangle().fill(.ultraThinMaterial)
            }
            .ignoresSafeArea()
        }
        .background(PanelWindowBehaviour())
    }
    
    // MARK: - Hero
    
    private var hero: some View {
        VStack(spacing: scale.s(SMI.Spacing.medium)) {
            
            // Taken from the running application rather than an asset name, so
            // it always matches whatever the bundle actually ships — including
            // any future icon change.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: scale.s(112), height: scale.s(112))
                .smiShadow(SMI.Elevation.floating(.brandViolet))
                .scaleEffect(iconNudge && !reduceMotion ? 0.94 : 1.0)
                .smiAnimation(SMI.Motion.snap, value: iconNudge)
                .onTapGesture { tapIcon() }
            // The icon is the app's portrait, not a control. Named, so it
            // is not announced as "image"; the tap gesture stays private.
                .accessibilityLabel("SwiftMediaInfo icon")
            
            VStack(spacing: scale.s(SMI.Spacing.snug)) {
                Text("SwiftMediaInfo")
                    .font(scale.font(28, .semibold))
                    .foregroundStyle(.primary)
                
                // PHASE 13a — the finished subtitle, replacing the placeholder.
                //
                // A tagline, not a description, so it is set differently from
                // the line it replaced. The old text explained what the app
                // was and wanted to read like body copy; this one asserts
                // something and wants a little room around it.
                //
                // Kerning and a slightly heavier weight do that without making
                // it louder — the restraint is the point. A tagline that shouts
                // in a window opened by someone who already owns the app would
                // be selling to a customer who has already bought.
                //
                // It is deliberately never shown next to the plain descriptor
                // used on GitHub and Homebrew. Wherever someone is looking at
                // the app itself, they get this; wherever a stranger or a
                // machine is scanning, they get the plain one. Putting a
                // keyword line under an evocative one is what makes a product
                // page read as marketing.
                Text("Beyond the File.")
                    .font(scale.font(13, .medium))
                    .kerning(0.3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                // PHASE 13n. Moved below the subtitle. The name and the
                // tagline are one thought and belong together; the version is
                // a fact about the copy you happen to be running, and reading
                // it between the two split a sentence in half.
                Text(versionString)
                    .font(scale.font(12, .medium, .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, scale.s(SMI.Spacing.medium))
                    .padding(.vertical, scale.s(SMI.Spacing.tight))
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.brandViolet.opacity(0.22), lineWidth: 0.7)
                    )
                    .padding(.top, scale.s(SMI.Spacing.snug))
            }
        }
        // One heading, spoken once: "SwiftMediaInfo, Beyond the File., Version
        // 2.0" rather than four separate stops.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
    
    // MARK: - Author
    
    private var authorCard: some View {
        GlassCard(tint: .brandViolet) {
            cardHeader("Author", icon: "person.crop.square", tint: .brandViolet)
        } content: {
            VStack(alignment: .leading, spacing: scale.s(SMI.Spacing.tight)) {
                // PHASE 13n. The name is now the way to the studio site.
                //
                // It opens the root rather than the app page on purpose: this
                // card is crediting the person, and the person is the studio.
                // Someone clicking a name wants to know who made this, not to
                // be sold the thing they already have open.
                AuthorNameLink(scale: scale)
                
                Text("Designed and directed by one person.")
                    .font(scale.font(12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(scale.s(SMI.Spacing.large))
        }
    }
    
    // MARK: - Provenance
    //
    // The reframed disclosure. Three verifiable claims first, the AI credit
    // last — in that order on purpose, because the order is the argument.
    
    private var provenanceCard: some View {
        GlassCard(tint: .brandTeal) {
            cardHeader("How this app was built", icon: "checkmark.seal", tint: .brandTeal)
        } content: {
            VStack(alignment: .leading, spacing: scale.s(SMI.Spacing.medium)) {
                
                assurance(
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: "Open source",
                    detail: "Every line is public on GitHub and free to audit."
                )
                
                assurance(
                    icon: "eye",
                    title: "Read-only analysis",
                    detail: "Reading metadata never alters a file. Renaming and moving to the Trash happen only when you ask."
                )
                
                assurance(
                    icon: "lock",
                    title: "Stays on your Mac",
                    detail: "Nothing is uploaded unless you choose to share, and you see exactly what is removed first."
                )
                
                Divider().opacity(0.4)
                
                VStack(alignment: .leading, spacing: scale.s(SMI.Spacing.tight)) {
                    Text("Written with AI")
                        .font(scale.font(12, .semibold))
                    
                    // PHASE 13n. Rewritten in the first person, to match the
                    // way the same disclosure is worded on the website and in
                    // the release notes. Said as "human direction and review"
                    // it reads like a policy notice written by a company; the
                    // point of the disclosure is that a person is standing
                    // behind it, so a person should be the one speaking.
                    Text("The code was written by Claude, under my direction and review. I say so plainly because the source is public — you do not have to take any of it on trust. Read it, build it yourself, or have someone you trust look at it.")
                        .font(scale.font(12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(scale.s(SMI.Spacing.large))
        }
    }
    
    private func assurance(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: scale.s(SMI.Spacing.medium)) {
            Image(systemName: icon)
                .font(scale.font(13, .semibold))
                .foregroundStyle(Color.brandTeal)
                .frame(width: scale.s(20), alignment: .center)
                .padding(.top, scale.s(1))
            
            VStack(alignment: .leading, spacing: scale.s(1)) {
                Text(title)
                    .font(scale.font(12, .semibold))
                
                Text(detail)
                    .font(scale.font(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .smiReadAsOne("\(title). \(detail)")
    }
    
    // MARK: - Links
    
    private var linksCard: some View {
        GlassCard(tint: .brandBlue) {
            cardHeader("Project", icon: "link", tint: .brandBlue)
        } content: {
            VStack(spacing: 0) {
                // PHASE 13n. Website first: it is the front door, and the one
                // address someone is most likely to want to keep.
                linkRow(
                    icon: "globe",
                    title: "Website",
                    subtitle: "undisclosed0369.app",
                    url: ProjectLinks.appPage
                )
                
                Divider().opacity(0.3)
                
                linkRow(
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: "View on GitHub",
                    subtitle: "Source, releases and documentation",
                    url: ProjectLinks.github
                )
                
                Divider().opacity(0.3)
                
                linkRow(
                    icon: "ladybug",
                    title: "Report an issue",
                    subtitle: "Bugs, requests and questions",
                    url: ProjectLinks.issues
                )
                
                Divider().opacity(0.3)
                
                // PHASE 13n. The subtitle does the work here. A donate row
                // with no qualifier reads as an ask; this one says the app is
                // free before it says anything else, which is the same order
                // the donate page itself uses.
                linkRow(
                    icon: "heart",
                    title: "Donate",
                    subtitle: "Everything is free — this is only if you would like to",
                    url: ProjectLinks.donate
                )
                
                Divider().opacity(0.3)
                
                linkRow(
                    icon: "doc.text",
                    title: "MIT License",
                    subtitle: "Free to use, modify and redistribute",
                    url: ProjectLinks.license
                )
            }
        }
    }
    
    private func linkRow(
        icon: String,
        title: String,
        subtitle: String,
        url: String
    ) -> some View {
        AboutLinkRow(
            icon: icon,
            title: title,
            subtitle: subtitle,
            url: url,
            scale: scale
        )
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        VStack(spacing: scale.s(SMI.Spacing.tight)) {
            Text(copyrightText)
                .font(scale.font(11))
                .foregroundStyle(.tertiary)
            
            Text("Press Esc to close")
                .font(scale.font(11))
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .padding(.top, scale.s(SMI.Spacing.tight))
    }
    
    // MARK: - Shared card header
    
    private func cardHeader(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: scale.s(SMI.Spacing.snug)) {
            Image(systemName: icon)
                .font(scale.font(11, .bold))
                .foregroundStyle(tint)
            
            Text(title.uppercased())
                .font(scale.font(11, .medium))
                .kerning(0.6)
                .foregroundStyle(.secondary)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, scale.s(SMI.Spacing.large))
        .padding(.vertical, scale.s(SMI.Spacing.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
    
    // MARK: - Easter egg
    
    private func tapIcon() {
        // The nudge fires on every tap, including the ones that do nothing —
        // otherwise three of the four taps feel like a dead icon.
        iconNudge = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 130_000_000)
            iconNudge = false
        }
        
        easterEggCounter += 1
        
        guard easterEggCounter >= 4 else { return }
        easterEggCounter = 0
        
        if let randomURLString = easterEggURLs.randomElement(),
           let url = URL(string: randomURLString) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Link row
//
// Pulled out into its own view rather than built inline, because it needs
// hover state and a `@State` property cannot live inside a function that
// returns a view.

private struct AboutLinkRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let url: String
    let scale: SMIScale
    
    @State private var isHovering = false
    
    var body: some View {
        Button {
            ProjectLinks.open(url)
        } label: {
            HStack(spacing: scale.s(SMI.Spacing.medium)) {
                Image(systemName: icon)
                    .font(scale.font(14, .medium))
                    .foregroundStyle(isHovering ? Color.brandBlue : Color.primary.opacity(0.7))
                    .frame(width: scale.s(22))
                
                VStack(alignment: .leading, spacing: scale.s(1)) {
                    Text(title)
                        .font(scale.font(13, .medium))
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(scale.font(11))
                        .foregroundStyle(.secondary)
                }
                
                Spacer(minLength: 0)
                
                Image(systemName: "arrow.up.right")
                    .font(scale.font(10, .semibold))
                    .foregroundStyle(isHovering ? Color.brandBlue : Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, scale.s(SMI.Spacing.large))
            .padding(.vertical, scale.s(SMI.Spacing.medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? SMI.Palette.hoverWash : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle(scale: 0.985))
        .onHover { isHovering = $0 }
        .smiAnimation(SMI.Motion.fade, value: isHovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint("\(subtitle). Opens in your browser.")
        .accessibilityAddTraits([.isButton, .isLink])
    }
}

// MARK: - Author name link
//
// PHASE 13n. The author's name, as a way to the studio site.
//
// Deliberately not styled as a button. A bordered control in the middle of a
// card that is otherwise plain text would announce itself, and this is a
// credit line, not a call to action. So it looks exactly like the text it
// replaced until the pointer is over it, at which point it picks up the brand
// tint and shows the same small arrow the link rows use.
//
// Its own view for the same reason AboutLinkRow is: it needs hover state, and
// `@State` cannot live in a function that returns a view.

private struct AuthorNameLink: View {
    let scale: SMIScale
    
    @State private var isHovering = false
    
    var body: some View {
        Button {
            ProjectLinks.open(ProjectLinks.website)
        } label: {
            HStack(spacing: scale.s(SMI.Spacing.snug)) {
                Text("Undisclosed / Data Lass")
                    .font(scale.font(15, .semibold))
                    .foregroundStyle(isHovering ? Color.brandViolet : Color.primary)
                
                Image(systemName: "arrow.up.right")
                    .font(scale.font(10, .semibold))
                    .foregroundStyle(Color.brandViolet)
                    .opacity(isHovering ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .smiAnimation(SMI.Motion.fade, value: isHovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Undisclosed / Data Lass")
        .accessibilityHint("Opens undisclosed0369.app in your browser.")
        .accessibilityAddTraits([.isButton, .isLink])
    }
}

// MARK: - Panel window behaviour
//
// Two jobs, both about making an auxiliary window behave like a panel rather
// than like a document.
//
// ESC CLOSES IT. Standard for a reference window you opened to glance at.
//
// ⌘M DOES NOTHING. PHASE 12c fix. ⌘M is AppKit's Minimize, which lives in the
// Window menu and is matched before the key press reaches any SwiftUI shortcut
// — so pressing it here folded the window into the Dock, while in the main
// window ⌘M cycles the appearance. The same chord doing two unrelated things
// depending on which window happened to be frontmost is the kind of
// inconsistency that makes an app feel unfinished.
//
// The fix is not to intercept the key. It is to say what this window is:
// removing `.miniaturizable` tells AppKit this is a panel, and AppKit then
// disables its own menu item — so ⌘M does nothing, the Window menu greys
// Minimize out, and the yellow traffic light dims. One property, and every
// route to minimizing agrees with the others.
//
// Reapplied in `updateNSView` because the window is not attached during
// `makeNSView`, and because a restored window can arrive with its original
// style mask.

private struct PanelWindowBehaviour: NSViewRepresentable {
    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
            configure(view.window)
        }
        return view
    }
    
    func updateNSView(_ nsView: KeyView, context: Context) {
        configure(nsView.window)
    }
    
    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        if window.styleMask.contains(.miniaturizable) {
            window.styleMask.remove(.miniaturizable)
        }
    }
    
    class KeyView: NSView {
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { // Escape
                window?.close()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
