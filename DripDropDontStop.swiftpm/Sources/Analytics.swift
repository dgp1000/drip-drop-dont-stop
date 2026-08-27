// Anonymous gameplay analytics — the funnel data: how far players get,
// what they bank, where they die, how long they stay.
//
// Privacy stance (this must stay true, it drives the App Privacy
// answers in ASC): ONE anonymous per-install UUID, gameplay events
// only, no identity, no device fingerprinting, insert-only publishable
// key (RLS: the API cannot read anything back). Events queue in
// UserDefaults when offline and flush on the next opportunity.
//
// NOTE for the next App Store submission: the review notes currently
// say "no network access" — that stops being true with this file. The
// ASC App Privacy questionnaire needs "Product Interaction — not
// linked to identity" declared.

import Foundation

enum Analytics {
    private static let endpoint = URL(
        string: "https://hdsnwuhbmbvrkjctrsbm.supabase.co/rest/v1/dripdrop_events")!
    private static let apiKey = "sb_publishable_8yxzekSbGKHy9SK-HRJWYw_fH7-2KaQ"
    private static let deviceKey = "dripdrop.analytics.device"
    private static let queueKey = "dripdrop.analytics.queue"
    private static var sessionBegan: Date?

    private static var deviceID: String {
        let d = UserDefaults.standard
        if let id = d.string(forKey: deviceKey) { return id }
        let id = UUID().uuidString.lowercased()
        d.set(id, forKey: deviceKey)
        return id
    }

    private static var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
    }

    /// Hardware identifier ("iPhone17,2"). Population-level device data —
    /// shared by millions of units, so the "no fingerprinting, not linked
    /// to identity" stance in the header still holds.
    private static let model: String = {
        var sys = utsname()
        uname(&sys)
        return withUnsafeBytes(of: &sys.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }()

    private static let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

    // MARK: The three events

    static func sessionStart() {
        guard sessionBegan == nil else { return }
        sessionBegan = Date()
        post("session_start", [:])
    }

    /// levelIndex: where they were when they left (1-based), nil on menu.
    static func sessionEnd(levelIndex: Int?) {
        guard let began = sessionBegan else { return }
        sessionBegan = nil
        var fields: [String: Any] = ["duration_s": Date().timeIntervalSince(began)]
        if let levelIndex { fields["level_index"] = levelIndex }
        post("session_end", fields)
    }

    static func levelResult(index: Int, name: String, completed: Bool,
                            banked: Int, deaths: Int, duration: TimeInterval) {
        post("level_result", [
            "level_index": index,
            "level_name": name,
            "completed": completed,
            "banked": banked,
            "deaths": deaths,
            "duration_s": duration,
        ])
    }

    // MARK: Plumbing — queue in defaults, flush fire-and-forget

    private static func post(_ event: String, _ fields: [String: Any]) {
        // Every row carries the FULL column set (nulls padded): PostgREST
        // bulk inserts reject batches whose rows have differing keys.
        var row: [String: Any] = ["device_id": deviceID, "build": build,
                                  "model": model, "os": osVersion,
                                  "event": event,
                                  "level_index": NSNull(), "level_name": NSNull(),
                                  "completed": NSNull(), "banked": NSNull(),
                                  "deaths": NSNull(), "duration_s": NSNull()]
        row.merge(fields) { _, new in new }
        var queue = pendingQueue()
        queue.append(row)
        if queue.count > 200 { queue.removeFirst(queue.count - 200) }
        save(queue)
        flush()
    }

    private static func pendingQueue() -> [[String: Any]] {
        guard let data = UserDefaults.standard.data(forKey: queueKey),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        // Rows queued by a build without model/os would give the batch
        // mixed key sets — PostgREST rejects those wholesale.
        return arr.map { row in
            var r = row
            if r["model"] == nil { r["model"] = NSNull() }
            if r["os"] == nil { r["os"] = NSNull() }
            return r
        }
    }

    private static func save(_ queue: [[String: Any]]) {
        UserDefaults.standard.set(
            (try? JSONSerialization.data(withJSONObject: queue)) ?? Data(),
            forKey: queueKey)
    }

    private static var isFlushing = false

    private static func flush() {
        guard !isFlushing else { return }   // one batch in flight at a time
        let queue = pendingQueue()
        guard !queue.isEmpty,
              let body = try? JSONSerialization.data(withJSONObject: queue) else { return }
        isFlushing = true
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let sent = queue.count
        URLSession.shared.dataTask(with: req) { _, response, _ in
            DispatchQueue.main.async {
                isFlushing = false
                guard let http = response as? HTTPURLResponse else { return }
                // 2xx: delivered. 4xx: the batch is poison (bad shape from
                // an old build?) and will never succeed — drop it rather
                // than wedge the queue forever. 5xx/offline: retry later.
                guard (200..<300).contains(http.statusCode)
                        || (400..<500).contains(http.statusCode) else { return }
                var q = pendingQueue()
                q.removeFirst(min(sent, q.count))
                save(q)
                if !q.isEmpty { flush() }
            }
        }.resume()
    }
}
