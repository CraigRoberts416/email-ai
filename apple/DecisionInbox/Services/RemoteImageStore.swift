import Foundation
import Observation
import SwiftUI
import UIKit

@MainActor @Observable
final class RemoteImageStore {
    static let shared = RemoteImageStore()
    private struct StoredImage: Codable { let data: Data; let url: URL; let loadedAt: Date }
    @ObservationIgnored private var images: [String: StoredImage] = [:]
    @ObservationIgnored private var checked: Set<String> = []
    private var revision = 0
    private var loading: [String: URL] = [:]
    private var attempted: [String: Date] = [:]
    private var generation = 0

    func image(for key: String) -> UIImage? {
        _ = revision
        if checked.insert(key).inserted,
           let stored = IdentityDiskCache().load(StoredImage.self, key: "image:" + key) {
            images[key] = stored
        }
        guard let stored = images[key], Date().timeIntervalSince(stored.loadedAt) < IdentityDiskCache.lifetime else {
            return nil
        }
        return UIImage(data: stored.data)
    }

    func load(_ url: URL, key: String) async {
        _ = image(for: key)
        guard url.scheme == "https" else { return }
        if let current = images[key], current.url == url,
           Date().timeIntervalSince(current.loadedAt) < 86_400 { return }
        let attemptKey = key + ":" + url.absoluteString
        guard loading[key] != url, Date().timeIntervalSince(attempted[attemptKey] ?? .distantPast) > 60 else { return }
        loading[key] = url
        attempted[attemptKey] = .now
        let version = generation
        defer { if version == generation, loading[key] == url { loading.removeValue(forKey: key) } }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 25
            // An avatar leaving the viewport must not cancel its shared image.
            let (data, response) = try await Task { try await URLSession.shared.data(for: request) }.value
            guard version == generation, loading[key] == url,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.mimeType?.hasPrefix("image/") == true, data.count < 8_000_000,
                  UIImage(data: data) != nil else { return }
            let stored = StoredImage(data: data, url: url, loadedAt: .now)
            images[key] = stored
            IdentityDiskCache().save(stored, key: "image:" + key)
            revision += 1
        } catch {
            // Keep the last successful image. A timeout isn't a new identity.
        }
    }

    func clearCache() {
        generation += 1
        images.removeAll(); checked.removeAll(); loading.removeAll(); attempted.removeAll()
        revision += 1
        IdentityDiskCache().clear()
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
            if let url { await images.load(url, key: cacheKey) }
        }
    }
}
