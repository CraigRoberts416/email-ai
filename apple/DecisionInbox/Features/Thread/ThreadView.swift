import SwiftUI

/// The real message.
///
/// The feed is the interpretation; this is the artifact. So the order is
/// interpretation first — it is why you tapped — then the sender's own words,
/// unedited. The AI never gets the last word on this screen.
struct ThreadView: View {
    let message: Message
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var body_: APIClient.Body?
    @State private var failed = false
    @State private var showRemoteContent = false
    @State private var compose: ComposeView.Intent?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                interpretation
                Rule()
                original
            }
        }
        .scrollIndicators(.hidden)
        .background(Ink.surface)
        .safeAreaInset(edge: .bottom) { replyBar }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(message.sender.displayName)
                    .typeStyle(Style.sender)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Save", systemImage: message.isSaved ? "bookmark.fill" : "bookmark") {
                        store.toggleSaved(message)
                    }
                    Button("Archive", systemImage: "archivebox") {
                        store.archive(message)
                        dismiss()
                    }
                    if message.isPromotion {
                        Button("Unsubscribe", systemImage: "xmark") {
                            store.unsubscribe(from: message)
                            dismiss()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Ink.primary)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            store.markRead(message)
            await load()
        }
        .sheet(item: $compose) { intent in
            ComposeView(intent: intent, message: message)
        }
    }

    // MARK: Interpretation

    @ViewBuilder private var interpretation: some View {
        if message.quote != nil || message.summary != nil {
            VStack(alignment: .leading, spacing: Space.md) {
                KickerLabel(message.kicker)

                if let quote = message.quote {
                    Text("\u{201C}\(quote)\u{201D}")
                        .typeStyle(Style.display)
                        .foregroundStyle(Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, -8)
                }

                if let summary = message.summary {
                    SummaryBlock(text: summary, density: .standard,
                                 emphasised: message.kicker == .possibleScam)
                }

                if let label = message.actionLabel, let url = message.actionURL {
                    CTAButton(label: label) { UIApplication.shared.open(url) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metric.gutter)
            .padding(.vertical, Space.xl)
        }
    }

    // MARK: The message itself

    private var original: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.md) {
                    AvatarView(sender: message.sender, size: Metric.avatar)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.sender.displayName)
                            .typeStyle(Style.sender)
                            .foregroundStyle(Ink.primary)
                        Text(message.sender.address)
                            .typeStyle(Style.monoSmall)
                            .foregroundStyle(Ink.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                Text(message.subject)
                    .typeStyle(Style.body)
                    .foregroundStyle(Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message.receivedAt.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
                    .typeStyle(Style.monoSmall)
                    .foregroundStyle(Ink.secondary)
            }
            .padding(.horizontal, Metric.gutter)

            content
        }
        .padding(.top, Space.xl)
        .padding(.bottom, Space.xxl)
    }

    @ViewBuilder private var content: some View {
        if let body_ {
            if !body_.htmlRaw.isEmpty {
                VStack(alignment: .leading, spacing: Space.md) {
                    EmailBodyWeb(html: body_.htmlRaw, loadRemoteContent: showRemoteContent)
                    if !showRemoteContent {
                        remoteContentNotice
                    }
                }
            } else {
                Text(body_.plainText.isEmpty ? message.snippet : body_.plainText)
                    .typeStyle(Style.body)
                    .foregroundStyle(Ink.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metric.gutter)
            }
        } else if failed {
            // Degraded, never blocking: the snippet is already on the device.
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(message.snippet)
                    .typeStyle(Style.body)
                    .foregroundStyle(Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { Task { await load() } }
                    .typeStyle(Style.bodySmall)
                    .foregroundStyle(Ink.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metric.gutter)
        } else {
            Text(message.snippet)
                .typeStyle(Style.body)
                .foregroundStyle(Ink.tertiary)
                .redacted(reason: .placeholder)
                .padding(.horizontal, Metric.gutter)
        }
    }

    /// Remote images in email are read receipts. Blocking them by default is
    /// the only honest position for a product that reads your mail for you.
    private var remoteContentNotice: some View {
        HStack(spacing: Space.md) {
            Text("IMAGES BLOCKED \u{2014} THEY TELL THE SENDER YOU OPENED THIS")
                .typeStyle(Style.chip)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Load") { showRemoteContent = true }
                .typeStyle(Style.bodySmall)
                .foregroundStyle(Ink.primary)
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.vertical, Space.md)
        .background(Ink.surfaceTertiary)
    }

    // MARK: Reply bar

    private var replyBar: some View {
        HStack(spacing: Space.xl) {
            Button { compose = .reply } label: {
                HStack(spacing: Space.sm) {
                    Image(systemName: "arrowshape.turn.up.left")
                    Text("Reply").typeStyle(Style.body)
                }
                .foregroundStyle(Ink.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { compose = .replyAll } label: {
                Image(systemName: "arrowshape.turn.up.left.2").foregroundStyle(Ink.secondary)
            }
            Button { compose = .forward } label: {
                Image(systemName: "arrowshape.turn.up.right").foregroundStyle(Ink.secondary)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: Metric.iconAction))
        .padding(.horizontal, Metric.gutter)
        .padding(.vertical, Space.md)
        .background(Ink.surface)
        .overlay(alignment: .top) { Rule() }
    }

    private func load() async {
        failed = false
        do { body_ = try await store.body(of: message) } catch { failed = true }
    }
}
