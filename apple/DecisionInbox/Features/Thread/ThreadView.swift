import SwiftUI

/// The thread, built to `Flows · Thread & Compose / 01 · Open Email`.
///
/// This is the one screen that inverts. The feed is our reading of someone's
/// mail; a thread is their actual words, so it arrives as a dark sheet with
/// their own hero image at the top and each message on a white card of its
/// own. The inversion is what makes the cards read as theirs rather than ours.
///
/// Below the messages sits Discuss — asking the model about the thread you are
/// looking at, rather than about mail in the abstract.
struct ThreadView: View {
    let message: Message

    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var body_: APIClient.Body?
    @State private var failed = false
    @State private var showRemoteContent = false
    @State private var compose: ComposeView.Intent?
    @State private var discuss = DiscussModel()

    private let heroHeight: CGFloat = 320
    /// How much of the hero is shown untouched before the fade begins. Sits
    /// below the status bar and the back-button row, so what it buys is a band
    /// of picture the reader actually sees rather than one hidden by chrome.
    private let heroClear: CGFloat = 176

    /// The sheet takes its colour from the sender's generated image, so a
    /// thread arrives looking like the sender rather than like the app. The
    /// navy in the Figma is simply what Delta's image extracted to.
    private var sheetColor: Color { .sheet(fromHex: message.heroBackground) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                masthead
                messageCard
                DiscussSection(model: discuss)
            }
        }
        .scrollIndicators(.hidden)
        .feedEdges()
        // A real inset, not an overlay in a ZStack.
        //
        // Stacked, the bar floated over the scroll view: the last line of a
        // thread sat underneath it, the padding meant to clear it was a guess
        // that was wrong for every message of a different length, and the
        // keyboard had nothing to push. `safeAreaInset` reserves the space, so
        // content ends above the field and scrolls to a true bottom — and the
        // field rides the keyboard up on its own, which is the behaviour of
        // every messaging app on the phone.
        .safeAreaInset(edge: .bottom, spacing: 0) { askBar }
        .background(sheetColor)
        .overlay(alignment: .top) { floatingControls }
        // Both bars, and owned here rather than by whoever pushed this view.
        // The feed's destination hid the tab bar and search's did not, so the
        // same thread was clean from one tab and, from the other, arrived with
        // a tab bar across its ask field and a second back button above its
        // own. A full-bleed sheet with its own chrome needs the system's gone;
        // that is this screen's requirement to state, not every caller's to
        // remember.
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task {
            store.markRead(message)
            await load()
        }
        .sheet(item: $compose) { ComposeView(intent: $0, message: message) }
    }

    // MARK: Masthead — the sender's image, their name, and the subject

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Clears the hero so the sender row lands where the gradient has
            // taken hold — past the clear band, with the picture still faintly
            // under it rather than behind a solid block of colour.
            Color.clear.frame(height: 236)

            HStack(spacing: Space.sm) {
                AvatarView(sender: message.sender, size: Metric.avatarCompact)
                Text(message.sender.displayName)
                    .typeStyle(Style.body)
                    .foregroundStyle(Ink.onSheet)
                Spacer(minLength: Space.md)
                if let url = message.actionURL ?? message.unsubscribeURL {
                    Button { UIApplication.shared.open(url) } label: {
                        Text(message.actionLabel ?? "Go to page")
                            .typeStyle(Style.chip)
                            .foregroundStyle(Ink.onSheet)
                            .lineLimit(1)
                            .padding(.horizontal, Space.lg)
                            .padding(.vertical, 5)
                            .overlay(
                                RoundedRectangle(cornerRadius: Corner.sm, style: .continuous)
                                    .strokeBorder(Ink.onSheet.opacity(0.35), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.xxl)

            // The subject is the headline here, not a label. It is the only
            // thing on this screen written by a human that we have not touched.
            Text(message.subject)
                .typeStyle(Style.display)
                .foregroundStyle(Ink.onSheet)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.xxl)

            HStack(spacing: Space.sm) {
                Image(systemName: "tray.full")
                    .font(.system(size: 13))
                Text(threadLabel)
                    .typeStyle(Style.meta)
            }
            .foregroundStyle(Ink.onSheetSecondary)
            .padding(.horizontal, Space.xxl)
            .padding(.top, Space.xxl + Space.md)

            if let summary = message.summary {
                Text(summary)
                    .typeStyle(Style.body)
                    .foregroundStyle(Ink.onSheet)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.xxl)
                    .padding(.top, Space.md)
            }
        }
        .padding(.bottom, Space.xl)
        .background(alignment: .top) { hero }
    }

    /// The generated sender image, given a band it actually owns before it
    /// fades into the sheet.
    ///
    /// It used to start fading at 52pt — under the status bar — so by the time
    /// the eye reached the sender row the picture was seven-tenths covered and
    /// the whole thing read as a flat colour wash. The image was being fetched,
    /// decoded and then hidden. It is clear through `heroClear` now and fades
    /// only across the remainder, which is what keeps the subject legible where
    /// it crosses the seam; the fade was always the right idea and was simply
    /// starting in the wrong place.
    private var hero: some View {
        ZStack(alignment: .bottom) {
            if let url = message.heroImageURL {
                AsyncImage(url: url, transaction: Transaction(animation: Move.crossfade)) { phase in
                    if case .success(let image) = phase {
                        // Fit, not fill, and no fixed height. A 320pt box with
                        // `scaledToFill` crops every picture to the same
                        // letterbox regardless of what it is — a product shot
                        // lost its own packaging that way. The sender chose
                        // the proportions; this shows them.
                        image.resizable().aspectRatio(contentMode: .fit)
                    } else {
                        // Never a spinner. A picture that has not arrived is
                        // the sender's own colour, which is already theirs.
                        sheetColor.frame(height: heroHeight)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                sheetColor.frame(height: heroHeight)
            }

            // The fade rides the bottom of whatever height the picture turned
            // out to be, rather than a slot measured from a height nothing
            // guarantees any more.
            LinearGradient(
                colors: [sheetColor.opacity(0), sheetColor.opacity(0.85), sheetColor],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: heroHeight - heroClear)
        }
        .frame(maxWidth: .infinity)
    }

    private var threadLabel: String {
        message.threadCount == 1 ? "1 email in thread" : "\(message.threadCount) emails in thread"
    }

    // MARK: The message itself, on its own white card

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(spacing: Space.sm) {
                    AvatarView(sender: message.sender, size: Metric.avatarCompact)
                    Text(message.sender.displayName)
                        .typeStyle(Style.body)
                        .foregroundStyle(Ink.primary)
                }
                HStack(spacing: Space.sm) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                    Text(message.receivedAt.threadStamp)
                        .typeStyle(Style.meta)
                }
                .foregroundStyle(Ink.secondary)
            }

            content

            Rule()

            ActionRow(
                message: message,
                onReply: { compose = .reply },
                onForward: { compose = .forward },
                onSave: { store.toggleSaved(message) },
                onArchive: { store.archive(message); dismiss() },
                onUnsubscribe: { store.unsubscribe(from: message); dismiss() }
            )
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: Corner.lg, style: .continuous))
        .padding(.horizontal, Space.md)
    }

    @ViewBuilder private var content: some View {
        if let body_ {
            if !body_.htmlRaw.isEmpty {
                // The sender's own layout, on their own card — which is why the
                // card is white. Their HTML was never designed for our ground.
                VStack(alignment: .leading, spacing: Space.md) {
                    // The card already provides the margin. The email used to
                    // add its own 16pt inside that, so a 390pt screen gave the
                    // sender 286pt to lay out in — every table squeezed, every
                    // line broken early. One margin, owned by the card.
                    EmailBodyWeb(html: body_.htmlRaw, loadRemoteContent: showRemoteContent)
                        .padding(.horizontal, -Space.lg)
                    if !showRemoteContent { remoteContentNotice }
                }
            } else {
                Text(body_.plainText.isEmpty ? message.snippet : body_.plainText)
                    .typeStyle(Style.body)
                    .foregroundStyle(Ink.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
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
        } else {
            Text(message.snippet)
                .typeStyle(Style.body)
                .foregroundStyle(Ink.tertiary)
                .redacted(reason: .placeholder)
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
        .padding(Space.md)
        .background(Ink.surfaceTertiary, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
    }

    // MARK: Chrome

    private var floatingControls: some View {
        VStack(spacing: Space.md) {
            // No grabber. The zoom transition already gives drag-down
            // dismissal, and a drawn handle on a pushed view is a control that
            // does not exist — the corners say "sheet" without claiming a
            // gesture nothing is listening for.
            HStack {
                circleButton("chevron.left") { dismiss() }
                Spacer()
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
                    circleLabel("ellipsis")
                }
            }
            .padding(.horizontal, Space.md)
        }
        .padding(.top, Space.lg)
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { circleLabel(symbol) }.buttonStyle(.plain)
    }

    private func circleLabel(_ symbol: String) -> some View {
        // Glass rather than a flat scrim disc. These two sit on a photograph
        // whose tone is whatever the sender's image happened to be, so a fixed
        // black wash is a guess that is wrong for a bright hero and heavy on a
        // dark one. Glass takes its value from what is actually behind it,
        // which is the only thing that holds across every sender.
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .medium))
            // Not white. Glass lifts whatever is behind it, so white on it is
            // unreadable over any hero; the scrim fallback still wants white.
            .foregroundStyle(GlassInk.onScrim)
            .frame(width: 40, height: 40)
            .glassControl(fallback: Ink.scrim, in: Circle())
            // Glass draws but does not hit-test, so the tappable area was the
            // glyph rather than the disc around it.
            .contentShape(.circle)
    }

    private var askBar: some View {
        DiscussInput(message: message, model: discuss, sheetColor: sheetColor)
            .padding(.horizontal, Space.lg)
            // Room above and below. It was landing in the home-indicator
            // strip, which is why it read as jammed against the bezel.
            .padding(.top, Space.lg)
            // Clear of the home indicator, not resting on it.
            .padding(.bottom, Space.lg)
            // The sheet's own colour behind it, carried to the screen edge.
            // Without this the bar sat on whatever happened to scroll under it
            // and its contrast changed as you moved — and this sheet's colour
            // is extracted from a photograph, so "whatever is behind it" is
            // not a value anything can be checked against.
            // A real blur, masked to fade in.
            //
            // A colour gradient is not what ChatGPT does and does not look
            // like it: a gradient paints *over* the content in one flat
            // colour, so on this sheet — whose colour is extracted from the
            // sender's photograph — it read as a dark smear. `.ultraThinMaterial`
            // is the system blur, it samples whatever is actually behind it,
            // and masking it with a gradient makes the blur itself fade in
            // rather than starting at a hard line.
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(sheetColor.opacity(0.55))
                    .mask(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.85), .black],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
            }
    }

    private func load() async {
        failed = false
        do { body_ = try await store.body(of: message) } catch { failed = true }
    }
}

// MARK: - Date

extension Date {
    /// Absolute enough to be useful, relative enough to read. The feed says
    /// "2h"; a thread is where you want to know it was this morning.
    var threadStamp: String {
        let seconds = Date.now.timeIntervalSince(self)
        if seconds < 3600 { return "\(max(1, Int(seconds / 60))) minutes ago" }
        if seconds < 86_400 {
            let hours = Int(seconds / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }
        if seconds < 7 * 86_400 {
            let days = Int(seconds / 86_400)
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }
        return formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
