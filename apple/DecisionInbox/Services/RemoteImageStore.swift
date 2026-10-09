import Foundation
import ImageIO
import Observation
import SwiftUI
import UIKit

private struct StoredRemoteImage: Codable, Sendable {
    let data: Data
    let url: URL
    let loadedAt: Date
}

/// Disk reads, image decoding and writes never occupy the scrolling thread.
private actor RemoteImageDisk {
    let directory: URL?
    init(directory: URL?) { self.directory = directory }
    func load(_ key: String) -> (StoredRemoteImage, UIImage)? {
        guard let stored = IdentityDiskCache(directory: directory).load(StoredRemoteImage.self, key: "image:" + key),
              let image = Self.decode(stored.data) else { return nil }
        return (stored, image)
    }

    func decodeAndSave(_ stored: StoredRemoteImage, key: String) -> UIImage? {
        guard let image = Self.decode(stored.data) else { return nil }
        IdentityDiskCache(directory: directory).save(stored, key: "image:" + key)
        return image
    }

    func clear() { IdentityDiskCache(directory: directory).clear() }

    private static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_200,
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: pixels)
    }
}

@MainActor @Observable
final class RemoteImageStore {
    static let shared = RemoteImageStore()
    private final class Cached: NSObject {
        let image: UIImage
        let url: URL
        let loadedAt: Date
        init(_ image: UIImage, url: URL, loadedAt: Date) {
            self.image = image; self.url = url; self.loadedAt = loadedAt
        }
    }
    private struct Load {
        let id: UUID
        let url: URL?
        let task: Task<UIImage?, Never>
    }
    @ObservationIgnored private let images = NSCache<NSString, Cached>()
    @ObservationIgnored private let disk: RemoteImageDisk
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var clearing: Task<Void, Never>?
    @ObservationIgnored private var loading: [String: Load] = [:]
    @ObservationIgnored private var failed: [String: Date] = [:]
    private var revision = 0

    init(session: URLSession = .shared, directory: URL? = nil) {
        self.session = session
        self.disk = RemoteImageDisk(directory: directory)
        images.totalCostLimit = 48 * 1_024 * 1_024
        images.countLimit = 128
    }

    func image(for key: String) -> UIImage? {
        _ = revision
        guard let cached = images.object(forKey: key as NSString),
              Date().timeIntervalSince(cached.loadedAt) < IdentityDiskCache.lifetime else { return nil }
        return cached.image
    }

    /// A row can leave the viewport without canceling its download. Every
    /// consumer awaits the same task; revisiting a row reuses decoded pixels.
    @discardableResult
    func load(_ url: URL?, key: String, retry: Bool = false) async -> UIImage? {
        if let cached = images.object(forKey: key as NSString), cached.url == url,
           Date().timeIntervalSince(cached.loadedAt) < 86_400 { return cached.image }
        if let existing = loading[key], existing.url == url { return await existing.task.value }
        loading[key]?.task.cancel()
        let id = UUID()
        let task = Task<UIImage?, Never> { [self] in
            defer { if loading[key]?.id == id { loading.removeValue(forKey: key) } }
            await clearing?.value
            guard !Task.isCancelled, loading[key]?.id == id else { return nil }
            if image(for: key) == nil, let (stored, image) = await disk.load(key) {
                guard !Task.isCancelled, loading[key]?.id == id else { return nil }
                publish(image, key: key, url: stored.url, date: stored.loadedAt)
                if stored.url == url, Date().timeIntervalSince(stored.loadedAt) < 86_400 { return image }
            }
            guard let url, url.scheme?.lowercased() == "https" else { return image(for: key) }
            let attemptKey = key + ":" + url.absoluteString
            guard retry || Date().timeIntervalSince(failed[attemptKey] ?? .distantPast) > 5 else { return image(for: key) }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                let (data, response) = try await session.data(for: request)
                guard !Task.isCancelled, loading[key]?.id == id,
                      let http = response as? HTTPURLResponse, http.statusCode == 200,
                      http.mimeType?.hasPrefix("image/") == true, data.count < 8_000_000 else {
                    if !Task.isCancelled { failed[attemptKey] = .now }
                    return image(for: key)
                }
                let stored = StoredRemoteImage(data: data, url: url, loadedAt: .now)
                guard let image = await disk.decodeAndSave(stored, key: key),
                      !Task.isCancelled, loading[key]?.id == id else { return image(for: key) }
                failed.removeValue(forKey: attemptKey)
                publish(image, key: key, url: url, date: stored.loadedAt)
                return image
            } catch {
                if !Task.isCancelled { failed[attemptKey] = .now }
                return image(for: key)
            }
        }
        loading[key] = Load(id: id, url: url, task: task)
        return await task.value
    }

    private func publish(_ image: UIImage, key: String, url: URL, date: Date) {
        let cost = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
        images.setObject(Cached(image, url: url, loadedAt: date), forKey: key as NSString, cost: cost)
        revision += 1
    }

    func clearCache() {
        for load in loading.values { load.task.cancel() }
        loading.removeAll(); failed.removeAll(); images.removeAllObjects()
        revision += 1
        clearing = Task { await disk.clear() }
    }
}

struct CachedRemoteImage<Placeholder: View>: View {
    let url: URL?
    let cacheKey: String
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var images = RemoteImageStore.shared

    var body: some View {
        Group {
            if let image = images.image(for: cacheKey) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else { placeholder() }
        }
        .task(id: cacheKey + (url?.absoluteString ?? "")) {
            await images.load(url, key: cacheKey)
        }
    }
}
