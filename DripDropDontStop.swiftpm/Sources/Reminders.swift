// Intelligent local reminders: the cave calls you back.
//
// Three rules make them respectful instead of spammy:
//  1. Permission is asked ONCE, right after the first banked basin — a
//     win moment — never at cold launch.
//  2. A 2-day / 7-day / 21-day ladder is wiped and rescheduled every
//     time the app leaves the foreground, so a reminder only ever fires
//     if the player actually stops playing. Playing again resets it.
//  3. Everything is scheduled for 19:00 local — nobody wants a 4 AM drip.
//
// "Intelligent" is the copy: each slot is generated from real progress —
// the next dry basin by name, the level closest to gold (with how close),
// or the standing best run — so it reads like the game remembers you.

import UserNotifications
import Foundation

final class Reminders {
    static let shared = Reminders()

    private static let askedKey = "dripdrop.reminders.asked"
    /// (delay in days, category flavor) — momentum, comeback, long-lost.
    private static let ladder: [(days: Int, flavor: Flavor)] =
        [(2, .momentum), (7, .comeback), (21, .longLost)]

    enum Flavor { case momentum, comeback, longLost }

    /// Ask for permission exactly once, after the first banked basin.
    /// If granted, the ladder schedules immediately.
    func requestAfterFirstBank(bestScores: [Int], bestRun: Int) {
        let d = UserDefaults.standard
        guard !d.bool(forKey: Self.askedKey) else { return }
        d.set(true, forKey: Self.askedKey)
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
                if granted { self?.sync(bestScores: bestScores, bestRun: bestRun) }
            }
    }

    /// Wipe and reschedule the ladder from current progress. Call when
    /// the app leaves the foreground — the timers only run while the
    /// player is away.
    func sync(bestScores: [Int], bestRun: Int) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            center.removeAllPendingNotificationRequests()
            for (i, rung) in Self.ladder.enumerated() {
                let content = UNMutableNotificationContent()
                let line = Self.line(flavor: rung.flavor,
                                     bestScores: bestScores, bestRun: bestRun)
                content.title = line.title
                content.body = line.body
                content.sound = .default
                guard let fire = Calendar.current.date(
                    byAdding: .day, value: rung.days, to: Date()) else { continue }
                var comps = Calendar.current.dateComponents(
                    [.year, .month, .day], from: fire)
                comps.hour = 19
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: comps, repeats: false)
                center.add(UNNotificationRequest(
                    identifier: "dripdrop.reminder.\(i)",
                    content: content, trigger: trigger))
            }
        }
    }

    // MARK: Copy generation

    private static func line(flavor: Flavor, bestScores: [Int], bestRun: Int)
        -> (title: String, body: String) {
        // The most interesting true fact about this player, in priority
        // order: a dry basin > a near-gold > a best run to beat.
        let nextDry = zip(Levels.all, bestScores).first { $0.1 == 0 }?.0.name
        // Nearest gold: highest best still under the 525 gold line.
        let nearGold = zip(Levels.all, bestScores)
            .filter { $0.1 > 0 && $0.1 < 525 }
            .max { $0.1 < $1.1 }

        switch flavor {
        case .momentum:
            if let name = nextDry {
                return ("The basin in \(name) is still dry",
                        "You were on a roll. One more level?")
            }
            if let (level, best) = nearGold {
                return ("\(525 - best) points from gold",
                        "\(level.name) almost gave it up last time. Finish the job.")
            }
            return ("The cave is dripping without you",
                    "Every level, gold — but is the best run safe?")
        case .comeback:
            if let (level, best) = nearGold {
                return ("\(level.name) remembers you",
                        "Your best is \(best) — gold starts at 525. It's closer than it sounds.")
            }
            if let name = nextDry {
                return ("\(name) is waiting",
                        "The droplet doesn't dry out. Neither should the streak.")
            }
            return ("A week without a drop",
                    "Your best run still stands at \(bestRun). For now.")
        case .longLost:
            if bestRun > 0 {
                return ("The cave kept your score",
                        "\(bestRun) points, still on the board. Come see if you can beat it.")
            }
            return ("Drip. Drop. Dont stop?",
                    "The droplet is right where you left it.")
        }
    }
}
