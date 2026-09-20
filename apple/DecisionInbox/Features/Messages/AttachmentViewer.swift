import QuickLook
import SafariServices
import SwiftUI
import UniformTypeIdentifiers

/// Opening the thing somebody sent you.
///
/// QuickLook and not a PDF view, a player and an image view: the system
/// already knows how to render PDFs, photos, audio, video, Office documents,
/// text and archives, with scrubbing, page thumbnails, sharing and rotation
/// for free. Writing three narrower viewers would be less capable than the one
/// iOS ships, and would still fail on the fourth kind of file.
///
/// It previews a file on disk, so the bytes are fetched first. That download is
/// a real wait — somebody else's megabytes over the network — which is the one
/// place in this product where a progress state is the truth rather than a
/// symptom.
@MainActor
@Observable
final class AttachmentOpener {
    enum State: Equatable {
        case idle
        case loading(Attachment.ID)
        case failed(String)
    }

    var state: State = .idle
    var previewing: PreviewItem?

    struct PreviewItem: Identifiable, Equatable {
        let id: String
        let url: URL
    }

    private var operation: Task<Void, Never>?
    private var requestID: UUID?
    private var lastRequest: (Attachment, String?)?

    func cancel() {
        operation?.cancel()
        operation = nil
        requestID = nil
        state = .idle
    }

    func retry() async {
        guard let (attachment, authorization) = lastRequest else { return }
        await open(attachment, authorization: authorization)
    }

    /// A new selection cancels the previous download. Only its request identity
    /// may publish a preview; identical sender filenames never share a file.
    func open(_ attachment: Attachment, authorization: String?) async {
        cancel()
        lastRequest = (attachment, authorization)
        guard let source = attachment.fileURL else {
            state = .failed("This file has no download link.")
            return
        }
        let id = UUID()
        requestID = id
        state = .loading(attachment.id)
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: source)
                request.timeoutInterval = 60
                if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
                let (temporary, response) = try await URLSession.shared.download(for: request)
                try Task.checkCancellation()
                guard self.requestID == id else { return }
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    self.state = .failed("Couldn’t fetch this file. Try again.")
                    return
                }
                let folder = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Attachments/\(id.uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = folder.appendingPathComponent(self.safeName(for: attachment))
                try FileManager.default.moveItem(at: temporary, to: destination)
                guard !Task.isCancelled, self.requestID == id else { return }
                self.state = .idle
                self.previewing = PreviewItem(id: id.uuidString, url: destination)
            } catch {
                guard !Task.isCancelled, self.requestID == id else { return }
                self.state = .failed("Couldn’t open this file. Your place in the email is kept.")
            }
        }
        operation = task
        await task.value
        if requestID == id { operation = nil }
    }

    /// A filename safe for the filesystem that keeps the extension, because the
    /// extension is what decides how it opens.
    private func safeName(for attachment: Attachment) -> String {
        let cleaned = attachment.filename
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let name = cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "attachment" : cleaned
        if URL(fileURLWithPath: name).pathExtension.isEmpty,
           let type = attachment.mimeType.flatMap({ UTType(mimeType: $0) }),
           let ext = type.preferredFilenameExtension {
            return "\(name).\(ext)"
        }
        return name
    }
}

/// A URL that a sheet can be driven by. `URL` is not `Identifiable`, and
/// conforming it globally would reach every other file in the app.
struct LinkTarget: Identifiable, Equatable {
    let url: URL
    var id: String { url.absoluteString }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

extension URL {
    /// The address out of a `mailto:`, without the query a signature may have
    /// hung off it (`?subject=`, `?cc=`).
    var emailAddress: String? {
        guard scheme?.lowercased() == "mailto" else { return nil }
        let raw = absoluteString.dropFirst("mailto:".count)
        let address = raw.split(separator: "?", maxSplits: 1).first.map(String.init) ?? String(raw)
        return address.removingPercentEncoding ?? address
    }
}

/// The system preview, presented as a sheet.
struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

/// A link, opened without leaving.
///
/// `SFSafariViewController` rather than handing the URL to Safari: a link in a
/// message is part of reading the message, and bouncing out of the app to
/// follow one loses your place in the thread. It is also the version that
/// keeps cookies out of this app's control and shows the real address bar, so
/// the reader can always see where a link actually went.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.preferredControlTintColor = .label
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
