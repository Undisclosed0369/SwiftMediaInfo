//
//  UsageTracker.swift
//  SwiftMediaInfo
//
//  Total time spent in SwiftMediaInfo (the empty screen's time card), and
//  the fun facts that put it in perspective. The facts are listed in full in
//  "SwiftMediaInfo v2.1 Fun Facts.md" beside the project.
//
//  WHAT COUNTS
//
//  Time with SwiftMediaInfo as the frontmost app and someone at the keyboard.
//  Leaving it open behind other windows does not count, and neither does
//  leaving it frontmost while you make a coffee: after two minutes without any
//  keyboard or mouse input the clock stops, and starts again with the next
//  keypress. A total that grows overnight on an idle Mac would be a number
//  about the Mac, not about you.
//
//  WHERE IT LIVES — AND WHY IT SURVIVES UPDATES
//
//  Twice, on purpose:
//
//    1. User defaults, under a key nothing else writes. Defaults belong to the
//       bundle identifier (app.undisclosed0369.SwiftMediaInfo), not to the
//       app's version or location, so replacing the app with a newer one —
//       or deleting it and installing again — keeps the total.
//    2. A small file in ~/Library/Application Support/SwiftMediaInfo. If the
//       preferences are ever lost or reset — a `defaults delete`, a profile
//       migration that skips them — the file brings the total back, and the
//       other way round. On launch the larger of the two wins, since the
//       total only ever grows.
//
//  Both depend only on the bundle identifier staying the same, which it must
//  anyway for Settings, Recent Files and Favorites to carry over.
//
//  Each tick re-reads the stored total before adding to it, so two copies of
//  the app running at once (a development build beside an installed one) add
//  their time together instead of overwriting each other.
//
//  Restore Defaults in Settings deliberately leaves it alone: it is a record,
//  not a setting. Hiding it from the empty screen hides it; it keeps counting.
//
//  Nothing about it ever leaves the Mac.
//

import SwiftUI
import AppKit
import CoreGraphics
internal import Combine

@MainActor
final class UsageTracker: ObservableObject {

    static let totalKey = "totalTimeSpentSeconds"

    /// Seconds of real use, ever.
    @Published private(set) var totalSeconds: Double

    /// No input for this long and the clock stops.
    private let idleLimit: TimeInterval = 120

    /// How often time is added. Short enough that quitting loses at most a
    /// few seconds, long enough not to matter to anyone's battery.
    private let interval: TimeInterval = 5

    private var timer: Timer?
    private var lastTick: Date?

    init() {
        let restored = max(UserDefaults.standard.double(forKey: Self.totalKey), Self.readMirror())
        totalSeconds = restored
        Self.store(restored)

        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.start() }
        }
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }

        if NSApp?.isActive == true { start() }
    }

    private func start() {
        guard timer == nil else { return }
        lastTick = Date()

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Common modes, so time keeps counting while a menu is open or a list
        // is being scrolled.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        tick()
        timer?.invalidate()
        timer = nil
        lastTick = nil
    }

    private func tick() {
        guard let lastTick else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTick)
        self.lastTick = now

        // A gap far longer than the timer's interval means the Mac slept with
        // the app in front. That time was not spent here.
        guard elapsed > 0, elapsed < interval * 6 else { return }
        guard secondsSinceLastInput < idleLimit else { return }

        // Added to what is stored now, not to what was loaded at launch —
        // another running copy may have added time since.
        let stored = max(UserDefaults.standard.double(forKey: Self.totalKey), totalSeconds)
        totalSeconds = stored + elapsed
        Self.store(totalSeconds)
    }
    
    // MARK: Storage
    
    /// Write both copies. Cheap enough for every tick: one defaults value
    /// and a file of a few dozen bytes, every five seconds of use.
    private static func store(_ total: Double) {
        UserDefaults.standard.set(total, forKey: totalKey)
        writeMirror(total)
    }
    
    private static var mirrorURL: URL? {
        AppSupport.folder?.appendingPathComponent("TimeSpent.plist")
    }
    
    private static func readMirror() -> Double {
        guard let url = mirrorURL,
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let total = plist["totalSeconds"] as? Double else { return 0 }
        return total
    }
    
    private static func writeMirror(_ total: Double) {
        guard let url = mirrorURL else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let plist: [String: Any] = ["totalSeconds": total, "updated": Date()]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Seconds since any keyboard, mouse or trackpad input, system-wide.
    private var secondsSinceLastInput: TimeInterval {
        // ~0 is "any input event type".
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    // MARK: Presentation

    /// "3 hours, 12 minutes" — the two largest units, which is as precise as
    /// a running total needs to be.
    var formattedTotal: String {
        guard totalSeconds >= 60 else { return "Less than a minute" }

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = totalSeconds >= 86_400 ? [.day, .hour, .minute] : [.hour, .minute]
        return formatter.string(from: totalSeconds) ?? ""
    }
}

// MARK: - Fun facts

/// Something surprising about how long you have spent here.
///
/// Each fact turns the total into a different measure — planets turning,
/// light travelling, hearts beating — and words itself for the size of the
/// number, so a first-day total reads as well as a thousand-hour one.
struct FunFact: Identifiable {
    let id: String
    let icon: String
    let tint: Color
    /// Builds the sentence for a total in seconds.
    let text: (Double) -> String
}

enum FunFacts {

    static let all: [FunFact] = [
        FunFact(id: "jupiter", icon: "globe.americas.fill", tint: .brandAmber) { s in
            let spins = s / 35_730            // 9 h 55 m 30 s
            return spins >= 1
                ? "Jupiter has spun around \(count(spins)) \(plural(spins, "time")) — a day there lasts under ten hours."
                : "Jupiter has turned \(percent(spins)) of the way through one of its ten-hour days."
        },
        FunFact(id: "earth-orbit", icon: "sun.max.fill", tint: .brandAmber) { s in
            "Earth has carried you \(distance(s * 29.78)) along its orbit around the Sun."
        },
        FunFact(id: "galaxy", icon: "sparkles", tint: .brandViolet) { s in
            "The Solar System has swept \(distance(s * 230)) around the centre of the Milky Way."
        },
        FunFact(id: "light", icon: "light.max", tint: .brandBlue) { s in
            let trips = s / 499               // light, Sun to Earth
            return trips >= 1
                ? "Sunlight could have made the trip to Earth \(count(trips)) \(plural(trips, "time"))."
                : "Light could have travelled \(distance(s * 299_792)) — \(count(s * 299_792 / 40_075)) laps of Earth."
        },
        FunFact(id: "iss", icon: "airplane.circle.fill", tint: .brandTeal) { s in
            let orbits = s / 5_561            // ~92.7 minutes
            return orbits >= 1
                ? "The International Space Station has circled Earth \(count(orbits)) \(plural(orbits, "time"))."
                : "The International Space Station has flown \(distance(s * 7.66)) — \(percent(orbits)) of an orbit."
        },
        FunFact(id: "moon", icon: "moon.fill", tint: .brandBlue) { s in
            "The Moon has travelled \(distance(s * 1.022)) along its path around Earth."
        },
        FunFact(id: "mars", icon: "circle.hexagongrid.fill", tint: .brandPink) { s in
            let sols = s / 88_775             // a Martian day
            return sols >= 1
                ? "That's \(count(sols)) \(plural(sols, "sol")) — full days on Mars."
                : "That's \(percent(sols)) of a day on Mars, where a day runs 40 minutes longer than ours."
        },
        FunFact(id: "venus", icon: "circle.fill", tint: .brandAmber) { s in
            "A single day on Venus lasts 243 Earth days. You're \(percent(s / (243 * 86_400))) of the way through one."
        },
        FunFact(id: "voyager", icon: "antenna.radiowaves.left.and.right", tint: .brandTeal) { s in
            "Voyager 1 has drifted another \(distance(s * 16.9)) into interstellar space."
        },
        FunFact(id: "pulsar", icon: "dot.radiowaves.left.and.right", tint: .brandViolet) { s in
            "The Crab Pulsar, a city-sized dead star, has spun \(count(s * 30.2)) times."
        },
        FunFact(id: "equator", icon: "globe.europe.africa.fill", tint: .brandGreen) { s in
            "Standing on the equator, Earth's spin would have carried you \(distance(s * 0.465))."
        },
        FunFact(id: "heart", icon: "heart.fill", tint: .brandPink) { s in
            "Your heart has beaten about \(count(s * 70 / 60)) times."
        },
        FunFact(id: "breaths", icon: "wind", tint: .brandTeal) { s in
            "You've taken roughly \(count(s * 14 / 60)) breaths."
        },
        FunFact(id: "blinks", icon: "eye.fill", tint: .brandBlue) { s in
            "You've blinked something like \(count(s / 4)) times — fewer while reading bit rates."
        },
        FunFact(id: "hair", icon: "scissors", tint: .brandViolet) { s in
            let mm = s / 86_400 * 0.35
            let cells = mm * 1000 / 7.5       // a red blood cell is ~7.5 µm across
            if mm >= 1 { return "Your hair has grown about \(decimal(mm)) millimetres." }
            if cells >= 1 {
                return "Your hair has grown about \(decimal(mm * 1000)) micrometres — the width of \(count(cells)) red blood \(plural(cells, "cell"))."
            }
            return "Your hair has grown about \(decimal(mm * 1000)) micrometres — less than the width of a red blood cell."
        },
        FunFact(id: "hummingbird", icon: "bird.fill", tint: .brandGreen) { s in
            "A hummingbird would have beaten its wings \(count(s * 53)) times."
        },
        FunFact(id: "bee", icon: "ladybug.fill", tint: .brandAmber) { s in
            "A honeybee would have flapped its wings \(count(s * 230)) times."
        },
        FunFact(id: "bamboo", icon: "leaf.fill", tint: .brandGreen) { s in
            let cm = s / 86_400 * 91
            if cm >= 100 { return "The fastest-growing bamboo could have grown \(decimal(cm / 100)) metres." }
            return cm >= 1
                ? "The fastest-growing bamboo could have grown \(decimal(cm)) centimetres."
                : "The fastest-growing bamboo could have grown \(decimal(cm * 10)) millimetres."
        },
        FunFact(id: "snail", icon: "tortoise.fill", tint: .brandGreen) { s in
            "A garden snail could have crawled \(distance(s * 0.000013))."
        },
        FunFact(id: "sound", icon: "speaker.wave.3.fill", tint: .brandBlue) { s in
            "Sound could have travelled \(distance(s * 0.343))."
        },
        FunFact(id: "songs", icon: "music.note", tint: .brandPink) { s in
            let songs = s / 210                // 3½ minutes
            return songs >= 1
                ? "That's about \(count(songs)) \(plural(songs, "song")) played back to back."
                : "That's \(percent(songs)) of an average song."
        },
        FunFact(id: "films", icon: "film.fill", tint: .brandViolet) { s in
            let films = s / 7_200              // two hours
            return films >= 1
                ? "Long enough to watch \(count(films)) feature \(plural(films, "film")) — or to read the metadata of a lot more."
                : "That's \(percent(films)) of a feature film. Metadata first, then popcorn."
        },
        FunFact(id: "saturn", icon: "circle.circle.fill", tint: .brandAmber) { s in
            let spins = s / 38_018             // 10 h 33 m 38 s
            return spins >= 1
                ? "Saturn has turned \(count(spins)) \(plural(spins, "time")) on its axis, rings and all."
                : "Saturn has made \(percent(spins)) of one turn, rings and all."
        },
        FunFact(id: "reading", icon: "book.fill", tint: .brandBlue) { s in
            "At an average reading pace, that's around \(count(s / 60 * 238)) words."
        },
        
        // ── Your body ──────────────────────────────────────────────────
        FunFact(id: "calories", icon: "flame.fill", tint: .brandAmber) { s in
            "Sitting here, you've burned roughly \(count(s / 60 * 1.4)) calories — just by being alive."
        },
        FunFact(id: "new-cells", icon: "circle.grid.3x3.fill", tint: .brandPink) { s in
            "Your body has made about \(count(s * 3_800_000)) new cells."
        },
        FunFact(id: "red-cells", icon: "drop.circle.fill", tint: .brandPink) { s in
            "Your bone marrow has produced around \(count(s * 2_400_000)) red blood cells."
        },
        FunFact(id: "blood", icon: "drop.fill", tint: .brandPink) { s in
            "Your heart has pumped about \(volume(s / 60 * 5)) of blood."
        },
        FunFact(id: "nails", icon: "hand.raised.fill", tint: .brandViolet) { s in
            let µm = s / 86_400 * 115         // ~3.5 mm a month
            return µm >= 1000
                ? "Your fingernails have grown about \(decimal(µm / 1000)) millimetres."
                : "Your fingernails have grown about \(decimal(µm)) micrometres."
        },
        
        // ── Getting around ─────────────────────────────────────────────
        FunFact(id: "motorway", icon: "car.fill", tint: .brandBlue) { s in
            "Driving at 100 km/h, you could have covered \(distance(s / 3600 * 100))."
        },
        FunFact(id: "formula1", icon: "flag.checkered", tint: .brandPink) { s in
            "A Formula 1 car flat out at 300 km/h would have gone \(distance(s / 3600 * 300))."
        },
        FunFact(id: "walking", icon: "figure.walk", tint: .brandGreen) { s in
            "Walking instead, you'd have taken about \(count(s / 60 * 100)) steps and gone \(distance(s / 3600 * 5))."
        },
        FunFact(id: "marathon", icon: "figure.run", tint: .brandGreen) { s in
            let marathons = s / 7_235         // world record, 2:00:35
            return marathons >= 1
                ? "At world-record pace, a runner could have finished \(count(marathons)) \(plural(marathons, "marathon"))."
                : "At world-record pace, a runner would be \(percent(marathons)) of the way through a marathon."
        },
        FunFact(id: "bolt", icon: "bolt.fill", tint: .brandAmber) { s in
            "Usain Bolt could have run his 9.58-second 100 metres \(count(s / 9.58)) times."
        },
        FunFact(id: "airliner", icon: "airplane", tint: .brandTeal) { s in
            "A jet airliner cruising at 900 km/h would have flown \(distance(s / 3600 * 900))."
        },
        FunFact(id: "parker", icon: "sun.horizon.fill", tint: .brandAmber) { s in
            "The Parker Solar Probe, the fastest object ever built, could have covered \(distance(s * 191.7)) at top speed."
        },
        
        // ── The planet ─────────────────────────────────────────────────
        FunFact(id: "lightning", icon: "cloud.bolt.fill", tint: .brandViolet) { s in
            "Lightning has struck somewhere on Earth about \(count(s * 44)) times."
        },
        FunFact(id: "rain", icon: "cloud.rain.fill", tint: .brandBlue) { s in
            "About \(count(s * 16_000_000)) tonnes of rain and snow have fallen on Earth."
        },
        FunFact(id: "atlantic", icon: "water.waves", tint: .brandTeal) { s in
            let nm = s * 0.79                 // ~2.5 cm a year
            return nm >= 1000
                ? "The Atlantic Ocean has grown about \(decimal(nm / 1000)) micrometres wider as the continents drift apart."
                : "The Atlantic Ocean has grown about \(count(nm)) nanometres wider as the continents drift apart."
        },
        FunFact(id: "moon-recedes", icon: "moon.stars.fill", tint: .brandBlue) { s in
            let nm = s * 1.2                  // ~3.8 cm a year
            return nm >= 1000
                ? "The Moon has drifted about \(decimal(nm / 1000)) micrometres further from Earth."
                : "The Moon has drifted about \(count(nm)) nanometres further from Earth."
        },
        FunFact(id: "niagara", icon: "drop.triangle.fill", tint: .brandTeal) { s in
            "Niagara Falls has poured over about \(volume(s * 2_400_000))."
        },
        FunFact(id: "amazon", icon: "leaf.circle.fill", tint: .brandGreen) { s in
            "The Amazon has emptied about \(volume(s * 209_000_000)) into the Atlantic."
        },
        
        // ── The Sun ────────────────────────────────────────────────────
        FunFact(id: "sun-mass", icon: "sun.max.circle.fill", tint: .brandAmber) { s in
            "The Sun has turned about \(count(s * 4_000_000)) tonnes of itself into pure light and energy."
        },
        FunFact(id: "sun-fusion", icon: "atom", tint: .brandAmber) { s in
            "The Sun has fused about \(count(s * 600_000_000)) tonnes of hydrogen into helium."
        },
        
        // ── People ─────────────────────────────────────────────────────
        FunFact(id: "births", icon: "figure.and.child.holdinghands", tint: .brandPink) { s in
            "Around \(count(s * 4.3)) babies have been born worldwide."
        },
        FunFact(id: "population", icon: "person.3.fill", tint: .brandViolet) { s in
            "The world's population has grown by about \(count(s * 2.2)) people."
        },
        FunFact(id: "coffee", icon: "cup.and.saucer.fill", tint: .brandAmber) { s in
            "People around the world have drunk about \(count(s * 26_000)) cups of coffee."
        },
        FunFact(id: "searches", icon: "magnifyingglass", tint: .brandBlue) { s in
            "Google has answered roughly \(count(s * 99_000)) searches."
        },
        FunFact(id: "youtube", icon: "play.rectangle.fill", tint: .brandPink) { s in
            "About \(count(s / 60 * 500)) hours of video have been uploaded to YouTube."
        },
        FunFact(id: "cars-built", icon: "car.2.fill", tint: .brandBlue) { s in
            "Factories have built about \(count(s * 2.9)) new cars and trucks."
        },
    ]

    // MARK: Number wording

    /// Whole numbers with separators; millions, billions and trillions in words, because
    /// "4.2 billion" is something you can feel and 4,213,557,902 is not.
    static func count(_ value: Double) -> String {
        switch value {
        case 1_000_000_000_000...: return "\(decimal(value / 1_000_000_000_000)) trillion"
        case 1_000_000_000...: return "\(decimal(value / 1_000_000_000)) billion"
        case 1_000_000...:     return "\(decimal(value / 1_000_000)) million"
        case 10...:            return value.formatted(.number.precision(.fractionLength(0)))
        default:               return value.formatted(.number.precision(.fractionLength(0...1)))
        }
    }

    static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    static func percent(_ fraction: Double) -> String {
        let value = fraction * 100
        return value < 0.1
            ? "\(value.formatted(.number.precision(.significantDigits(1...2))))%"
            : "\(value.formatted(.number.precision(.fractionLength(0...1))))%"
    }

    /// Kilometres, falling back to metres for short distances.
    static func distance(_ km: Double) -> String {
        km >= 1 ? "\(count(km)) km" : "\(count(km * 1000)) metres"
    }

    /// Litres, or millions and billions of them.
    static func volume(_ litres: Double) -> String {
        litres >= 1 ? "\(count(litres)) \(litres.rounded() == 1 ? "litre" : "litres")" : "\(count(litres * 1000)) millilitres"
    }
    
    static func plural(_ value: Double, _ word: String) -> String {
        value.rounded() == 1 ? word : word + "s"
    }
}
