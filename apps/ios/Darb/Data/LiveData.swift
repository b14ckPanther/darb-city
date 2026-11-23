import Foundation

/// Keeps the app's map in step with Darb's server, the same database the website and the admin use. A business
/// added or edited in the admin reaches the phone the next time the app opens or comes back to the front.
///
/// The server sends the whole map (`GET /app/data`) in the shape the bundle carries. The app keeps it in the app
/// group as three files: darb.json for the app, needs.json (the nine everyday needs only) for the widget and Siri,
/// and details.json for the place pages. It asks again with the copy's ETag, so an unchanged map costs nothing.
enum LiveData {
    private static let etagKey = "darbLiveETag"
    private static let checkedKey = "darbLiveChecked"

    /// Fetches the map when it changed; returns it decoded, or nil when the phone's copy is current or the server
    /// cannot be reached. `force` asks even when the last check was moments ago.
    static func sync(force: Bool = false) async -> DarbData? {
        let defaults = Shared.defaults
        let last = defaults.double(forKey: checkedKey)
        if !force, Date.now.timeIntervalSince1970 - last < 30 { return nil }
        defaults.set(Date.now.timeIntervalSince1970, forKey: checkedKey)

        var req = URLRequest(url: DarbAPI.base.appendingPathComponent("app/data"))
        req.timeoutInterval = 30
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if LiveFiles.url("darb") != nil, let tag = defaults.string(forKey: etagKey) { req.setValue(tag, forHTTPHeaderField: "If-None-Match") }
        guard let (body, response) = try? await URLSession.shared.data(for: req), let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return nil }
        return Perf.time("live.store") { () -> DarbData? in
            guard var all = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
                  (all["version"] as? Int) == 2 else { return nil }
            let details = all.removeValue(forKey: "details") ?? [String: Any]()
            guard let core = try? JSONSerialization.data(withJSONObject: all),
                  let decoded = try? DarbData.decode(core),
                  !decoded.businesses.isEmpty || defaults.string(forKey: etagKey) != nil,
                  let folder = LiveFiles.folder else { return nil }
            let fm = FileManager.default
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            do {
                try core.write(to: folder.appendingPathComponent("darb.json"), options: .atomic)
                try JSONSerialization.data(withJSONObject: details).write(to: folder.appendingPathComponent("details.json"), options: .atomic)
                try needs(all).write(to: folder.appendingPathComponent("needs.json"), options: .atomic)
            } catch { return nil }
            if let tag = http.value(forHTTPHeaderField: "ETag") { defaults.set(tag, forKey: etagKey) }
            return decoded
        }
    }

    /// The same map with only the businesses of the nine everyday needs: what the widget and Siri read.
    private static func needs(_ all: [String: Any]) throws -> Data {
        var out = all
        guard let kinds = all["kinds"] as? [[String: Any]], let cols = all["businesses"] as? [String: Any],
              let kindCol = cols["kind"] as? [Int] else { return try JSONSerialization.data(withJSONObject: all) }
        let wanted = Set(Need.all.flatMap(\.kinds))
        let keepKinds = Set(kinds.indices.filter { (kinds[$0]["slug"] as? String).map(wanted.contains) ?? false })
        let keep = kindCol.indices.filter { keepKinds.contains(kindCol[$0]) }
        var sub: [String: Any] = [:]
        for (key, value) in cols {
            if let byLang = value as? [String: [Any]] {
                sub[key] = byLang.mapValues { arr in keep.map { arr[$0] } }
            } else if let arr = value as? [Any] {
                sub[key] = keep.map { arr[$0] }
            }
        }
        out["businesses"] = sub
        return try JSONSerialization.data(withJSONObject: out)
    }
}
