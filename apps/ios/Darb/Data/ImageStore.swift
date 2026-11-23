import CryptoKit
import ImageIO
import SwiftUI
import UIKit

/// Pictures from partners' own systems, kept on the phone. Each one is downloaded once, saved to disk, and held
/// decoded in memory, so a shop opened again shows its photos at once instead of loading them one by one.
/// Settings can empty it.
actor ImageStore {
    static let shared = ImageStore()

    /// Decoded pictures ready to draw. NSCache is safe across threads and lets go of them when memory is short.
    nonisolated(unsafe) private static let memory: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.totalCostLimit = 160 << 20
        return c
    }()

    private var running: [URL: Task<UIImage?, Never>] = [:]

    nonisolated static let folder: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// The picture, if it is already decoded in memory: drawn in the same frame, with no placeholder.
    nonisolated static func ready(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    /// The picture from memory, then from the phone, then from the network; saved on the way.
    func image(_ url: URL) async -> UIImage? {
        if let m = Self.ready(url) { return m }
        if let t = running[url] { return await t.value }
        let t = Task.detached(priority: .userInitiated) { () -> UIImage? in
            let file = Self.file(url)
            var data = try? Data(contentsOf: file)
            if data == nil {
                var req = URLRequest(url: url); req.timeoutInterval = 20
                guard let (d, r) = try? await URLSession.shared.data(for: req),
                      ((r as? HTTPURLResponse)?.statusCode ?? 200) < 300 else { return nil }
                try? d.write(to: file, options: .atomic)
                data = d
            }
            guard let data, let img = Self.decode(data) else { return nil }
            Self.memory.setObject(img, forKey: url as NSURL, cost: Int(img.size.width * img.size.height * img.scale * img.scale * 4))
            return img
        }
        running[url] = t
        let img = await t.value
        running[url] = nil
        return img
    }

    /// Saves the picture to the phone ahead of time without decoding it, at low priority.
    func keep(_ url: URL) async {
        let file = Self.file(url)
        if Self.ready(url) != nil || FileManager.default.fileExists(atPath: file.path) { return }
        var req = URLRequest(url: url); req.timeoutInterval = 20
        guard let (d, r) = try? await URLSession.shared.data(for: req), ((r as? HTTPURLResponse)?.statusCode ?? 200) < 300 else { return }
        try? d.write(to: file, options: .atomic)
    }

    /// Decodes at most 1000 pixels on the long side, ready for display, off the main thread.
    private nonisolated static func decode(_ data: Data) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 1000,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    private nonisolated static func file(_ url: URL) -> URL {
        let h = SHA256.hash(data: Data(url.absoluteString.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(h)
    }

    /// How much the kept pictures and shop copies take on the phone, in bytes.
    nonisolated static func bytes() -> Int64 {
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        var total: Int64 = 0
        let files = (fm.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL] ?? [])
            + ((try? fm.contentsOfDirectory(at: caches, includingPropertiesForKeys: [.fileSizeKey])) ?? []).filter { $0.lastPathComponent.hasPrefix("shop") }
        for f in files { total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return total + Int64(URLCache.shared.currentDiskUsage)
    }

    /// Empties everything kept: the pictures, the copies of the shops, and the network's own cache.
    nonisolated static func clear() {
        memory.removeAllObjects()
        let fm = FileManager.default
        try? fm.removeItem(at: folder)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        for f in (try? fm.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil)) ?? [] where f.lastPathComponent.hasPrefix("shop") {
            try? fm.removeItem(at: f)
        }
        URLCache.shared.removeAllCachedResponses()
    }
}

/// A picture from a partner's system, through the store: drawn at once when it was seen before, faded in when it
/// arrives from the network for the first time.
struct KeptImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    @State private var loaded: (url: URL, image: UIImage)?

    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url; self.content = content; self.placeholder = placeholder
    }

    var body: some View {
        let shown = url.flatMap { u in loaded?.url == u ? loaded?.image : ImageStore.ready(u) }
        ZStack {
            if let shown { content(Image(uiImage: shown)) } else { placeholder() }
        }
        .task(id: url) {
            guard let url, ImageStore.ready(url) == nil else { return }
            let started = Date.now
            guard let img = await ImageStore.shared.image(url) else { return }
            // from the phone it is near instant: no fade; from the network it fades in
            let slow = Date.now.timeIntervalSince(started) > 0.08
            withAnimation(slow ? .smooth(duration: 0.25) : nil) { loaded = (url, img) }
        }
    }
}

extension KeptImage where Placeholder == Color {
    init(url: URL?, fill: Color, @ViewBuilder content: @escaping (Image) -> Content) {
        self.url = url; self.content = content; self.placeholder = { fill }
    }
}
