//
//  FinderExtension.swift
//  SwiftMediaInfo
//
//  Switches the Finder extension (the OpenInSwiftMediaInfo target, which
//  adds "Open in SwiftMediaInfo" to Finder's right-click menu) on and off,
//  and reads whether it is on. Everything goes through /usr/bin/pluginkit,
//  which reads and writes the same switch as System Settings › General ›
//  Login Items & Extensions — so that page and Settings › General always
//  agree, and neither keeps a copy of its own.
//
//  AT LAUNCH (`switchOnUnlessTurnedOff`)
//
//  macOS leaves a newly installed Finder extension off until it is switched
//  on, so the app does it — unless it has been turned off, which is a choice
//  and is respected:
//  • "+" (on): nothing to do.
//  • "-" (turned off, in System Settings or in Settings › General): left off.
//  • no mark (never decided — a new install), or not registered yet:
//    switched on.
//
//  WHY IT REGISTERS FIRST
//
//  Just asking pluginkit to "use" the extension failed on a first launch:
//  macOS registers an app's extensions on its own, a moment after the app
//  first opens, and an election made before that matches nothing — so new
//  users had to switch it on in System Settings themselves. `-a` registers
//  this copy's extension there and then; the election that follows is then
//  checked, and tried again for about fifteen seconds until it holds.
//
//  All the work happens on one serial background queue, so a launch, the
//  Settings switch and Restore Defaults can never interleave. The answer
//  each one ends with is kept in `lastKnownOn`, so the switch in Settings
//  opens showing it rather than flipping once pluginkit replies.
//

import Foundation

enum FinderExtension {

    /// Where the extension stands, from the mark pluginkit prints before it.
    nonisolated enum State: Sendable {
        /// "+" (or "!", in use under a debugger).
        case on
        /// "-": turned off — in System Settings or in Settings › General.
        case off
        /// No mark: never switched either way. macOS leaves it off.
        case undecided
        /// Not registered (yet), or pluginkit could not be run.
        case unknown
    }

    // MARK: - For the app

    /// Whether the extension was on when last checked or changed.
    private(set) static var lastKnownOn = true

    /// Called once at launch. Returns at once; the work is done in the
    /// background.
    static func switchOnUnlessTurnedOff() {
        Task {
            await run {
                let state = currentState()
                guard state != .on, state != .off else { return state == .on }
                return switchOn()
            }
        }
    }

    /// Whether the extension is on now, for the switch in Settings.
    static func isOn() async -> Bool {
        await run { currentState() == .on }
    }

    /// Switches the extension on or off — from Settings, or on (the default)
    /// from Restore Defaults — and returns whether it is on afterwards.
    @discardableResult
    static func set(_ on: Bool) async -> Bool {
        await run { on ? switchOn() : switchOff() }
    }

    /// Does `work` on the queue and keeps the answer it gives.
    private static func run(_ work: @escaping @Sendable () -> Bool) async -> Bool {
        let isOn = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
        lastKnownOn = isOn
        return isOn
    }

    // MARK: - pluginkit

    nonisolated private static let queue = DispatchQueue(
        label: "app.undisclosed0369.SwiftMediaInfo.finder-extension",
        qos: .utility
    )

    /// The extension inside this copy of the app.
    nonisolated private static var bundleURL: URL? {
        Bundle.main.builtInPlugInsURL?.appendingPathComponent("OpenInSwiftMediaInfo.appex")
    }

    /// Read from the extension itself, so it can never drift from the
    /// target's bundle identifier.
    nonisolated private static var identifier: String? {
        bundleURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
        ?? Bundle.main.bundleIdentifier.map { $0 + ".OpenInSwiftMediaInfo" }
    }

    /// The election of the copy macOS would use (the newest one).
    nonisolated private static func currentState() -> State {
        guard let identifier,
              let output = pluginkit(["-m", "-i", identifier]),
              let line = output.split(separator: "\n").first(where: { $0.contains(identifier) })
        else { return .unknown }

        switch line.first {
        case "+", "!": return .on
        case "-":      return .off
        default:       return .undecided
        }
    }

    /// Registers this copy's extension, elects to use it, and checks that
    /// it took — again after 1, 2, 4 and 8 seconds if it did not, while
    /// macOS finishes registering a newly installed app.
    nonisolated private static func switchOn() -> Bool {
        guard let identifier else { return false }

        for delay in [0, 1, 2, 4, 8] {
            if delay > 0 { Thread.sleep(forTimeInterval: TimeInterval(delay)) }

            // Not from a translocated copy — one run straight from Downloads
            // or a disk image, which macOS moves to a temporary, randomised
            // path. Registering that would point Finder at a path that is
            // gone once the app quits. The election alone still holds for
            // the copy that ends up in Applications.
            if let path = bundleURL?.path(percentEncoded: false), !path.contains("/AppTranslocation/") {
                pluginkit(["-a", path])
            }
            pluginkit(["-e", "use", "-i", identifier])

            if currentState() == .on { return true }
        }
        return false
    }

    /// Elects to ignore the extension — exactly what switching it off in
    /// System Settings does. Returns whether it is still on.
    nonisolated private static func switchOff() -> Bool {
        guard let identifier else { return currentState() == .on }
        pluginkit(["-e", "ignore", "-i", identifier])
        return currentState() == .on
    }

    /// Runs pluginkit and returns what it printed, or nil if it couldn't
    /// be run.
    @discardableResult
    nonisolated private static func pluginkit(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // Read before waiting: a full pipe would otherwise stall pluginkit.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
