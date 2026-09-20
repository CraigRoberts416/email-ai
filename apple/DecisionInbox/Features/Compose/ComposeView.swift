import SwiftUI

// BEGIN COMPOSE_RECOVERY_STATE
/// Recovery belongs to the hydrated draft, regardless of which route opens it.
/// Kept independent of view rendering so both editor entry paths can be checked.
struct ComposeRecoveryState {
    var originalLoaded = false
    private var requiresSentCheck = false
    private var sentChecked = false

    var needsSentCheck: Bool { requiresSentCheck && !sentChecked }

    mutating func restore(explicit: MailDraftRecord?, cached: MailDraftRecord?) -> MailDraftRecord? {
        guard let record = explicit ?? cached else { return nil }
        originalLoaded = record.originalLoaded
        requiresSentCheck = record.requiresSentCheck
        sentChecked = false
        return record
    }

    mutating func confirmSentChecked() { sentChecked = true }
    func permitsSend(isForward: Bool) -> Bool { !isForward || originalLoaded }
    func offersOriginalReload(isForward: Bool, loading: Bool) -> Bool {
        isForward && !originalLoaded && !loading
    }
}
// END COMPOSE_RECOVERY_STATE

/// The composer, built to `Flows · Thread & Compose / 03–06`.
///
/// Reply, reply-all, forward and new differ only in who is addressed and what
/// is quoted underneath, so they are one screen rather than four.
///
/// Sending is immediate with an undo window rather than a "Send?" dialog. A
/// dialog taxes everybody every time to catch the few who change their mind;
/// an undo charges nothing until you actually use it.
struct ComposeView: View {
    enum Intent: String, Identifiable {
        case reply, replyAll, forward, new
        var id: String { rawValue }

        var subjectPrefix: String? {
            switch self {
            case .reply, .replyAll: return "Re:"
            case .forward: return "Fwd:"
            case .new: return nil
            }
        }
    }

    let intent: Intent
    var message: Message?
    /// Somebody's address, tapped in a thread. An email address in a message
    /// is a person to write to, not a page to visit.
    var prefilledTo: String?
    var restoredDraft: MailDraftRecord?
    var recoveringSendID: UUID?

    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var bodyFocused: Bool

    @State private var to = ""
    @State private var subject = ""
    @State private var text = ""
    @State private var suggestion: String?
    @State private var attachments: [Attachment] = []
    @State private var includedFiles: [GmailClient.FileAttachment] = []
    @State private var selectedMailbox = ""
    @State private var initialized = false
    @State private var forwardedText = ""
    @State private var preparing = false
    @State private var loadingOriginal = false
    @State private var problem: String?
    @State private var draftSaved = true
    @State private var recovery = ComposeRecoveryState()
    @State private var confirmSentCheck = false
    @State private var preparationTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Gmail's ceiling. Naming it here rather than in a string keeps the copy
    /// and the rule from drifting apart.
    private static let attachmentLimit = 25 * 1_000_000

    var body: some View {
        VStack(spacing: 0) {
            header
            Rule()

            HStack {
                Text("FROM").typeStyle(Style.fieldLabel).foregroundStyle(Ink.secondary)
                Picker("Send from", selection: $selectedMailbox) {
                    ForEach(store.auth.accounts, id: \.id) { account in Text(account.id).tag(account.id) }
                }
                .tint(Ink.primary)
            }.padding(.horizontal, Space.xl).padding(.vertical, Space.sm).disabled(preparing)
            Rule()

            field("TO", text: $to, keyboard: .emailAddress).disabled(preparing)
            Rule()
            field("SUBJECT", text: $subject, keyboard: .default).disabled(preparing)
            Rule()

            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    TextEditor(text: $text)
                        .typeStyle(Style.body)
                        .foregroundStyle(Ink.primary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 88)
                        .focused($bodyFocused)
                        .padding(.horizontal, -5)

                    if recovery.needsSentCheck {
                        Text("This email may already be sent. Check Sent before sending another copy.")
                            .typeStyle(Style.bodySmall).foregroundStyle(Ink.secondary)
                    }
                    if let suggestion { suggestedDraft(suggestion) }
                    if loadingOriginal { ProgressView("Loading the original email…") }
                    if !forwardedText.isEmpty {
                        Text("INCLUDED IN FORWARD").typeStyle(Style.chip).foregroundStyle(Ink.secondary)
                        Text(forwardedText).typeStyle(Style.quoted).textSelection(.enabled)
                    } else if let message, intent != .new && intent != .forward { quoted(message) }
                    if let problem {
                        Text(problem).typeStyle(Style.bodySmall).foregroundStyle(Ink.primary)
                    }
                    if recovery.offersOriginalReload(isForward: intent == .forward, loading: loadingOriginal) {
                        Text("The original email has not loaded yet. Your note is kept.")
                            .typeStyle(Style.bodySmall).foregroundStyle(Ink.secondary)
                        Button("Load original again") { Task { await loadForward() } }
                            .frame(minHeight: Metric.tapTarget)
                    }
                    ForEach(attachments) { attachment in
                        attachmentRow(attachment)
                    }
                    ForEach(Array(includedFiles.enumerated()), id: \.offset) { index, file in
                        HStack {
                            Label(file.filename, systemImage: "paperclip").lineLimit(2)
                            Spacer()
                            Button("Remove") {
                                includedFiles.remove(at: index)
                                if intent == .forward && file.filename == "original-email.html" {
                                    forwardedText = ""; recovery.originalLoaded = false
                                    problem = "The original HTML email was removed. Load the original to forward it."
                                }
                                persistDraft()
                            }
                        }.typeStyle(Style.bodySmall)
                    }
                    Text(draftSaved ? "DRAFT KEPT ON THIS DEVICE" : "COULDN’T SAVE THIS DRAFT. KEEP THIS SCREEN OPEN.")
                        .typeStyle(Style.monoMicro).foregroundStyle(Ink.secondary)
                }
                .padding(Space.xl)
                .disabled(preparing)
            }
            .scrollIndicators(.hidden)
        }
        .background(Ink.surface)
        .task { await prefill() }
        .onChange(of: to) { persistDraft() }
        .onChange(of: subject) { persistDraft() }
        .onChange(of: text) { persistDraft() }
        .onChange(of: selectedMailbox) { persistDraft() }
        .interactiveDismissDisabled(preparing)
        .onDisappear { preparationTask?.cancel() }
        .confirmationDialog("This draft may already be sent", isPresented: $confirmSentCheck, titleVisibility: .visible) {
            Button("I checked Sent — send this copy") { recovery.confirmSentChecked(); send() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Check this mailbox’s Sent folder before sending again. Another copy could duplicate an email already delivered.") }
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            Button("Close") { preparationTask?.cancel(); persistDraft(); dismiss() }
                .typeStyle(Style.body)
                .foregroundStyle(Ink.secondary)
                .buttonStyle(.plain)
                .frame(minWidth: Metric.tapTarget, minHeight: Metric.tapTarget)

            Spacer(minLength: 0)
            ActivityToolbarButton()

            Button(action: send) {
                Text(preparing ? "Preparing…" : "Send")
                    .typeStyle(Style.button)
                    .foregroundStyle(canSend ? Ink.onInverse : Ink.secondary)
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.sm)
                    .frame(minHeight: Metric.tapTarget)
                    .background(canSend ? Ink.inverse : Ink.border, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .animation(Move.resolved(Move.crisp, reduceMotion), value: canSend)
        }
        .padding(.horizontal, Space.xl - 4)
        .padding(.vertical, Space.lg + 6)
    }

    private func field(
        _ label: String,
        text binding: Binding<String>,
        keyboard: UIKeyboardType
    ) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .typeStyle(Style.fieldLabel)
                .foregroundStyle(Ink.secondary)
                .frame(width: 70, alignment: .leading)
            TextField("", text: binding)
                .typeStyle(Style.body)
                .foregroundStyle(Ink.primary)
                .tint(Ink.primary)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
                .autocorrectionDisabled(keyboard == .emailAddress)
        }
        .padding(.horizontal, Space.xl - 4)
        .padding(.vertical, Space.md + 2)
    }

    // MARK: Blocks

    /// The model's draft, and the label is the whole point of it: yours to
    /// edit, yours to send. Nothing here goes out because the model wrote it.
    private func suggestedDraft(_ draft: String) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("SUGGESTED \u{2014} YOURS TO EDIT, YOURS TO SEND")
                .typeStyle(Style.chip)
                .foregroundStyle(Ink.secondary)

            Text("\u{201C}\(draft)\u{201D}")
                .typeStyle(Style.draft)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Use this") {
                text = draft
                suggestion = nil
                bodyFocused = true
            }
            .typeStyle(Style.quoted)
            .foregroundStyle(Ink.primary)
            .buttonStyle(.plain)
            .padding(.top, Space.xs)
        }
        .padding(.leading, Space.md)
        .overlay(alignment: .leading) {
            Rectangle().fill(Ink.border).frame(width: 1)
        }
    }

    /// The original, greyed and unedited — the same shape a quote-tweet takes
    /// in the feed, for the same reason.
    private func quoted(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("\(message.sender.displayName.uppercased()) \u{00B7} \(message.receivedAt.threadStamp.uppercased())")
                .typeStyle(Style.chip)
                .foregroundStyle(Ink.secondary)
            Text(message.snippet)
                .typeStyle(Style.quoted)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("ORIGINAL CONTEXT · NOT INCLUDED IN REPLY").typeStyle(Style.monoMicro)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.lg)
        .background(Ink.surfaceTertiary, in: RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
    }

    /// Too large is drawn with a heavier black border, not a red one. The
    /// product has no colour to spend on alarm, and weight carries it fine.
    private func attachmentRow(_ attachment: Attachment) -> some View {
        let oversized = attachment.byteCount > Self.attachmentLimit
        return HStack(spacing: Space.md) {
            Image(systemName: "doc.text")
                .font(.system(size: 16))
                .foregroundStyle(Ink.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .typeStyle(Style.quoted)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(oversized
                     ? "\(attachment.sizeLabel.uppercased()) \u{00B7} GMAIL STOPS AT 25 MB\nSEND A LINK INSTEAD, OR REMOVE IT"
                     : "\(attachment.sizeLabel.uppercased()) \u{00B7} \(attachment.kindLabel)")
                    .typeStyle(Style.fileMeta)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.sm)

            Button {
                attachments.removeAll { $0.id == attachment.id }
                persistDraft()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(Ink.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(attachment.filename)")
        }
        .padding(.horizontal, Space.md + 2)
        .padding(.vertical, Space.md)
        .overlay(
            RoundedRectangle(cornerRadius: Corner.md, style: .continuous)
                .strokeBorder(oversized ? Ink.primary : Ink.border, lineWidth: oversized ? 2 : 1)
        )
    }

    // MARK: Behaviour

    private var canSend: Bool {
        !selectedMailbox.isEmpty && !recipients.isEmpty
            && recipients.allSatisfy { $0.contains("@") && $0.rangeOfCharacter(from: .newlines) == nil }
            && (!outgoingBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !includedFiles.isEmpty)
            && attachments.reduce(0, { $0 + $1.byteCount }) + includedFiles.reduce(0, { $0 + $1.data.count }) <= Self.attachmentLimit
            && recovery.permitsSend(isForward: intent == .forward)
            && !loadingOriginal && !preparing
    }

    private var recipients: [String] { to.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
    private var draftKey: String {
        restoredDraft?.id ?? "\(intent.rawValue):\(message?.feedKey ?? selectedMailbox):\(prefilledTo ?? "")"
    }
    private var outgoingBody: String { text + (forwardedText.isEmpty ? "" : "\n\n" + forwardedText) }

    private func prefill() async {
        guard !initialized else { return }
        selectedMailbox = restoredDraft?.mailboxID ?? message?.mailboxID ?? store.auth.accounts.first?.id ?? ""
        if let record = recovery.restore(explicit: restoredDraft, cached: MailDraftStore.draft(draftKey)) {
            to = record.draft.to.joined(separator: ", ")
            subject = record.draft.subject
            text = record.draft.body
            includedFiles = record.draft.attachments
            attachments = record.pendingAttachments
            initialized = true
            bodyFocused = true
            return
        }
        initialized = true
        // An address tapped in a thread fills the TO field and puts the cursor
        // in the body — the recipient is the one thing already decided.
        if let prefilledTo, to.isEmpty {
            to = prefilledTo
            bodyFocused = true
        }
        guard let message else {
            if prefilledTo == nil { bodyFocused = true }
            persistDraft(); return
        }
        if let prefix = intent.subjectPrefix {
            subject = message.subject.hasPrefix(prefix) ? message.subject : "\(prefix) \(message.subject)"
        }
        switch intent {
        case .reply, .replyAll:
            to = message.sender.address
            // Offered, never inserted. A draft that types itself into the body
            // is one careless tap away from being sent as though you wrote it.
            Task { suggestion = try? await store.suggestReply(to: message) }
        case .forward:
            attachments = message.attachments
            if attachments.isEmpty, case .carousel(let items) = message.shape { attachments = items }
            await loadForward()
        case .new:
            break
        }
        bodyFocused = true
        persistDraft()
    }

    private func loadForward() async {
        guard let message else { return }
        loadingOriginal = true
        defer { loadingOriginal = false }
        do {
            let original = try await store.body(of: message)
            let prefix = "---------- Forwarded email ----------\nFrom: \(message.sender.displayName) <\(message.sender.address)>\nDate: \(message.receivedAt.formatted())\nSubject: \(message.subject)\n\n"
            if !original.plainText.isEmpty { forwardedText = prefix + original.plainText }
            else if !original.htmlRaw.isEmpty {
                forwardedText = prefix + "The original HTML email is attached."
                includedFiles.append(.init(filename: "original-email.html", mimeType: "text/html", data: Data(original.htmlRaw.utf8)))
            } else { throw GmailError.send("The original email has no readable body.") }
            recovery.originalLoaded = true
            problem = nil
            persistDraft()
        } catch { problem = "Couldn’t load the original for forwarding. Your note is kept." }
    }

    private func persistDraft() {
        guard initialized, store.auth.accounts.contains(where: { $0.id == selectedMailbox }) else { return }
        draftSaved = MailDraftStore.save(.init(id: draftKey, mailboxID: selectedMailbox,
            draft: .init(to: recipients, subject: subject, body: outgoingBody,
                         threadID: intent == .forward ? nil : message?.threadID,
                         inReplyTo: nil, attachments: includedFiles), pendingAttachments: attachments, originalLoaded: recovery.permitsSend(isForward: intent == .forward),
            requiresSentCheck: recovery.needsSentCheck,
            composeIntent: intent.rawValue, sourceMessage: message))
    }

    /// Dismisses at once. The send sits behind the undo window and its result
    /// arrives as a receipt over the feed, so the composer is never a waiting
    /// room.
    private func send() {
        guard canSend else { return }
        if recovery.needsSentCheck { confirmSentCheck = true; return }
        preparing = true
        persistDraft()
        preparationTask = Task {
            defer { preparing = false }
            do {
                var files = includedFiles
                for attachment in attachments {
                    guard let url = attachment.fileURL else { throw GmailError.send("\(attachment.filename) has no download link. Remove it to send without it.") }
                    let (data, response) = try await URLSession.shared.data(from: url)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw GmailError.send("Couldn’t load \(attachment.filename). Try again or remove it.") }
                    files.append(.init(filename: attachment.filename, mimeType: attachment.mimeType ?? "application/octet-stream", data: data))
                    guard files.reduce(0, { $0 + $1.data.count }) <= Self.attachmentLimit else { throw GmailError.send("The combined files exceed 25 MB. Remove a file or send a link.") }
                }
                let draft = GmailClient.Draft(to: recipients, subject: subject, body: outgoingBody,
                    threadID: intent == .forward ? nil : message?.threadID, inReplyTo: nil, attachments: files)
                try Task.checkCancellation()
                guard store.queueSend(draft, from: selectedMailbox, draftKey: draftKey) != nil else {
                    problem = "Couldn’t queue this email. Your draft is kept."; return
                }
                if let recoveringSendID {
                    // The replacement now owns the work; retire its old receipt.
                    store.sendJobs.removeValue(forKey: recoveringSendID)
                    MailDraftStore.saveJobs(store.sendJobs)
                }
                dismiss()
            } catch is CancellationError {
                // Closing during preparation keeps the draft and sends nothing.
            } catch { if !Task.isCancelled { problem = error.localizedDescription } }
        }
    }
}

extension Attachment {
    var kindLabel: String {
        (filename as NSString).pathExtension.uppercased()
    }
}
