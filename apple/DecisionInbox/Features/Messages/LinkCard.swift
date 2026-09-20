import LinkPresentation
import SwiftUI

/// A link, as Messages draws one.
///
/// `LPLinkView` is the component iMessage itself uses — image, title, site
/// name, favicon, and the correct fallback when a site offers none of them.
/// Same reasoning as QuickLook: the system already ships the thing, and a
/// hand-rolled card would be a worse version of it that breaks on the first
/// site with an unusual `og:image`.
///
/// PRIVACY — and this is why the rich card is OFF by default.
///
/// Building it means this device fetches the destination, which tells that
/// destination somebody looked. Everywhere else in this app the server fetches
/// on the reader's behalf precisely so a sender learns nothing about when mail
/// was opened; a link preview would hand that back. For a portfolio site it is
/// nothing, for a tracking link it is a read receipt, and the reader cannot
/// tell which is which by looking.
///
/// So the default is the offline card, built from the URL alone and costing
/// nothing. Turning previews on is a real trade and belongs to the reader, not
/// to us. Known trackers are never fetched even when it is on — there is no
/// version of that request that is not the thing the tracker was put there to
/// record.
struct LinkCard: View {
    let url: URL
    var onDark = false

    @AppStorage("links.richPreviews") private var richPreviews = false
    @State private var metadata: LPLinkMetadata?
    @State private var resolved = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let metadata {
                LinkPreview(metadata: metadata)
                    .frame(maxWidth: 272)
            } else {
                Button { openURL(url) } label: { offline }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(url.absoluteString)")
            }
        }
        .task {
            guard !resolved else { return }
            resolved = true
            guard richPreviews, Self.isSafeToFetch(url) else { return }
            metadata = await Self.fetch(url)
        }
    }

    /// What a link is before anyone asks the internet about it: where it goes.
    /// Also the permanent card for trackers, and the one shown while a real
    /// preview is still loading — so the row never changes height twice.
    private var offline: some View {
        HStack(spacing: Space.sm + 2) {
            Image(systemName: "link")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(onDark ? Ink.surface.opacity(0.75) : Ink.secondary)
                .frame(width: 38, height: 38)
                .background(
                    onDark ? Ink.surface.opacity(0.14) : Ink.surfaceTertiary,
                    in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(host)
                    .typeStyle(Style.monoCaption)
                    .foregroundStyle(onDark ? Ink.surface : Ink.primary)
                    .lineLimit(1)
                if let path, !path.isEmpty {
                    Text(path)
                        .typeStyle(Style.monoMicro)
                        .foregroundStyle(onDark ? Ink.surface.opacity(0.7) : Ink.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.leading, Space.sm + 2)
        .padding(.trailing, Space.lg)
        .padding(.vertical, Space.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(onDark ? Ink.surface.opacity(0.10) : Ink.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(onDark ? Ink.surface.opacity(0.18) : Ink.border,
                                      lineWidth: Metric.hairline)
                )
        )
        .frame(maxWidth: 272, alignment: .leading)
    }

    private var host: String {
        (url.host() ?? url.absoluteString).replacingOccurrences(of: "www.", with: "")
    }

    private var path: String? {
        let p = url.path()
        return p == "/" || p.isEmpty ? nil : p
    }

    /// Link trackers and redirectors. Asking one of these for a preview is
    /// exactly the request the tracker was put there to record.
    private static let trackers: Set<String> = [
        "l.gourl.es", "click.sfemail.signetjewelers.com", "links.mailsuite.com",
        "click.e.usps.com", "email.mg.substack.com", "url.us.m.mimecastprotect.com",
        "clicks.aweber.com", "trk.klclick.com", "click.mailchimp.com", "list-manage.com",
        "sendgrid.net", "mandrillapp.com", "bit.ly", "t.co", "lnkd.in",
    ]

    static func isSafeToFetch(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        guard url.scheme == "https" || url.scheme == "http" else { return false }
        return !trackers.contains(where: { host == $0 || host.hasSuffix(".\($0)") })
    }

    private static func fetch(_ url: URL) async -> LPLinkMetadata? {
        let provider = LPMetadataProvider()
        provider.timeout = 8
        return try? await provider.startFetchingMetadata(for: url)
    }
}

/// The system card itself.
private struct LinkPreview: UIViewRepresentable {
    let metadata: LPLinkMetadata

    func makeUIView(context: Context) -> LPLinkView {
        let view = LPLinkView(metadata: metadata)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return view
    }

    func updateUIView(_ view: LPLinkView, context: Context) {
        view.metadata = metadata
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: LPLinkView,
                      context: Context) -> CGSize? {
        let width = min(proposal.width ?? 272, 272)
        let fitted = uiView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: fitted.height)
    }
}
