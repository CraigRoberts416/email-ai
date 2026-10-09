import Foundation
import CoreGraphics
import ImageIO

final class ImageProtocol: URLProtocol {
    static let lock = NSLock()
    static var requests = 0
    static var status = 200
    static var data = Data()
    private var work: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "image.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests += 1
        let status = Self.status
        let data = Self.data
        Self.lock.unlock()
        let job = DispatchWorkItem { [self] in
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                httpVersion: nil, headerFields: ["Content-Type": "image/png"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        work = job
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.06, execute: job)
    }
    override func stopLoading() { work?.cancel() }
}

@main struct RemoteImagePipelineTests {
    @MainActor static func main() async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let context = CGContext(data: nil, width: 2_400, height: 1_600, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2_400, height: 1_600))
        let bytes = NSMutableData()
        let encoder = CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(encoder, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(encoder))
        ImageProtocol.data = bytes as Data
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ImageProtocol.self]
        config.urlCache = nil
        let session = URLSession(configuration: config)
        let store = RemoteImageStore(session: session, directory: folder)
        let url = URL(string: "https://image.test/a")!
        let departingRow = Task { await store.load(url, key: "a") }
        try? await Task.sleep(for: .milliseconds(15))
        departingRow.cancel()
        let image = await store.load(url, key: "a")
        precondition(image != nil && ImageProtocol.requests == 1, "Rows share downloads even after one leaves")
        precondition(image?.cgImage?.width == 1_200 && image?.cgImage?.height == 800, "Decode is sized for display")
        let departed = await departingRow.value
        precondition(departed === image)
        let again = await store.load(url, key: "a")
        precondition(again === image && ImageProtocol.requests == 1, "Decoded pixels are reused")
        let relaunched = RemoteImageStore(session: session, directory: folder)
        let disk = await relaunched.load(url, key: "a")
        precondition(disk != nil && ImageProtocol.requests == 1, "Disk cache survives a new store")
        ImageProtocol.status = 503
        let failedURL = URL(string: "https://image.test/retry")!
        let firstFailure = await store.load(failedURL, key: "retry")
        precondition(firstFailure == nil)
        let failureRequests = ImageProtocol.requests
        let throttled = await store.load(failedURL, key: "retry")
        precondition(throttled == nil && ImageProtocol.requests == failureRequests)
        ImageProtocol.status = 200
        let retried = await store.load(failedURL, key: "retry", retry: true)
        precondition(retried != nil,
                     "Explicit retry bypasses the brief failure backoff")
        store.clearCache()
        precondition(store.image(for: "a") == nil)
        let beforeClearReload = ImageProtocol.requests
        let reloaded = await store.load(url, key: "a")
        precondition(reloaded != nil && ImageProtocol.requests == beforeClearReload + 1,
                     "Clearing removes both decoded and disk caches before loading again")
        let insecure = await store.load(URL(string: "http://image.test/insecure")!, key: "insecure")
        precondition(insecure == nil)
        print("PASS: 11 image pipeline checks (shared loads, viewport cancellation, bounded decode, memory/disk reuse, retry, clear, HTTPS)")
        session.invalidateAndCancel()
    }
}
