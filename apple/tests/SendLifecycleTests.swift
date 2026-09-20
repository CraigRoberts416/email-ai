import Foundation

/// Production FeedStore with a controlled Gmail boundary. All data is synthetic.
@main @MainActor struct SendLifecycleTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ reason: String) {
        guard value() else { fatalError(reason) }; checks += 1
    }
    static func until(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(2)
        while !condition() && Date() < deadline { try? await Task.sleep(for: .milliseconds(2)) }
        check(condition(), "Timed out waiting for controlled send state")
    }
    static func draft(_ body: String) -> GmailClient.Draft {
        .init(to: ["recipient@example.invalid"], subject: "Synthetic", body: body, threadID: nil, inReplyTo: nil)
    }
    static func fixture() -> (FeedStore, HarnessAccount, String) {
        MailDraftStore.clear()
        let id = "synthetic-\(UUID())@example.invalid"
        let account = HarnessAccount(); HarnessTransport.accounts[id] = account
        return (FeedStore(auth: AuthService(accounts: [id])), account, id)
    }

    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("send-tests-\(UUID())")
        MailDraftStore.directoryOverride = directory
        DiscussionStore.directoryOverride = directory
        defer { try? FileManager.default.removeItem(at: directory) }

        let (both, transport, accountID) = fixture()
        let first = both.queueSend(draft("First"), from: accountID)!
        let second = both.queueSend(draft("Second"), from: accountID)!
        check(first != second, "Two sends must have independent identity")
        await until { both.sendJobs[first]?.phase == .sent && both.sendJobs[second]?.phase == .sent }
        check(Set(transport.sentDrafts.map(\.body)) == ["First", "Second"], "Second send must not cancel first")

        let (undo, selective, undoID) = fixture()
        let keep = undo.queueSend(draft("Keep"), from: undoID)!
        let stop = undo.queueSend(draft("Restore these words"), from: undoID, draftKey: "edited")!
        undo.undoSend(stop)
        await until { undo.sendJobs[keep]?.phase == .sent }
        check(selective.sentDrafts.map(\.body) == ["Keep"], "Undo only stops the chosen send")
        check(undo.sendJobs[stop]?.phase == .held, "Undo retains a held send")
        check(MailDraftStore.draft("edited")?.draft.body == "Restore these words", "Undo restores original text")

        let (late, blocked, lateID) = fixture()
        let gate = HarnessGate()
        blocked.send = { _ in _ = await gate.wait() }
        let submitted = late.queueSend(draft("Already submitting"), from: lateID)!
        await until { gate.waiting }
        late.undoSend(submitted)
        check(late.sendJobs[submitted]?.phase == .sending, "Undo cannot assert cancellation after submission")
        gate.finish(HarnessReply(json: [:]))
        await until { late.sendJobs[submitted]?.phase == .sent }

        let (unknown, uncertain, uncertainID) = fixture()
        uncertain.send = { _ in throw URLError(.timedOut) }
        let unknownJob = unknown.queueSend(draft("Possibly sent"), from: uncertainID)!
        await until { unknown.sendJobs[unknownJob]?.phase == .unknown }
        check(uncertain.sentDrafts.count == 1, "Unknown send is not automatically repeated")
        unknown.dismissSendJob(unknownJob)
        check(MailDraftStore.drafts(for: [uncertainID]).first?.requiresSentCheck == true, "Dismissing unknown result preserves duplicate-send guard")

        let (refused, rejecting, refusedID) = fixture()
        rejecting.send = { _ in throw HarnessFailure(message: "Rejected by provider") }
        let rejection = refused.queueSend(draft("Keep on refusal"), from: refusedID)!
        await until { refused.sendJobs[rejection]?.phase == .failed }
        check(refused.sendJobs[rejection]?.draft.body == "Keep on refusal", "Definite refusal retains draft")

        let incompleteForward = MailDraftRecord(id: "unfinished-forward", mailboxID: refusedID, draft: draft("A note awaiting the original"), originalLoaded: false, composeIntent: "forward")
        check(MailDraftStore.save(incompleteForward), "Incomplete forward can be preserved")
        let restoredForward = MailDraftStore.draft(incompleteForward.id)
        check(restoredForward?.originalLoaded == false && restoredForward?.composeIntent == "forward", "Reopen retains forward intent and blocks sending until original loads")
        check(restoredForward?.draft.body == "A note awaiting the original", "Incomplete forward keeps the user's note")

        let unknownDraft = MailDraftRecord(id: "unknown-edit", mailboxID: refusedID, draft: draft("Possibly accepted"), requiresSentCheck: true)
        check(MailDraftStore.save(unknownDraft), "Unknown draft is editable and preserved")
        check(MailDraftStore.draft(unknownDraft.id)?.requiresSentCheck == true, "Unknown draft keeps resend acknowledgement after editor closes")

        // These policies are extracted directly from ComposeView, not mirrored
        // by the harness. Both entry routes must hydrate the same saved guard.
        var explicitEditor = ComposeRecoveryState()
        let explicitRecord = explicitEditor.restore(explicit: unknownDraft, cached: nil)
        check(explicitRecord?.draft.body == unknownDraft.draft.body && explicitEditor.needsSentCheck,
              "Activity edit hydrates unknown-send guard")
        var ordinaryReplyEditor = ComposeRecoveryState()
        let cachedRecord = ordinaryReplyEditor.restore(explicit: nil, cached: MailDraftStore.draft(unknownDraft.id))
        check(cachedRecord?.draft.body == unknownDraft.draft.body && ordinaryReplyEditor.needsSentCheck,
              "Normal reply route hydrates the same unknown-send guard from disk")
        MailDraftStore.save(.init(id: unknownDraft.id, mailboxID: refusedID, draft: cachedRecord!.draft,
                                 requiresSentCheck: ordinaryReplyEditor.needsSentCheck))
        check(MailDraftStore.draft(unknownDraft.id)?.requiresSentCheck == true,
              "Saving through normal reply route cannot erase an unchecked resend guard")
        ordinaryReplyEditor.confirmSentChecked()
        check(!ordinaryReplyEditor.needsSentCheck, "Explicit Check Sent acknowledgement unlocks submission")
        _ = ordinaryReplyEditor.restore(explicit: nil, cached: MailDraftStore.draft(unknownDraft.id))
        check(ordinaryReplyEditor.needsSentCheck, "Fresh hydration does not inherit another editor's acknowledgement")

        var reopenedForward = ComposeRecoveryState()
        _ = reopenedForward.restore(explicit: nil, cached: restoredForward)
        check(!reopenedForward.permitsSend(isForward: true), "Incomplete forward stays unsendable on normal reopen")
        check(reopenedForward.offersOriginalReload(isForward: true, loading: false),
              "Incomplete forward offers retry without requiring an ephemeral error string")
        check(!reopenedForward.offersOriginalReload(isForward: true, loading: true),
              "Retry cannot create a duplicate original-load operation")
        reopenedForward.originalLoaded = true
        check(reopenedForward.permitsSend(isForward: true) && !reopenedForward.offersOriginalReload(isForward: true, loading: false),
              "Successful source load removes retry and permits forward")
        check(!reopenedForward.offersOriginalReload(isForward: false, loading: false),
              "Ordinary new/reply composers do not acquire a forward-only retry control")

        let queued = SendJob(id: UUID(), mailboxID: refusedID, draftKey: "restart", draft: draft("Restart"), phase: .queued)
        let sending = SendJob(id: UUID(), mailboxID: refusedID, draftKey: "uncertain", draft: draft("Uncertain"), phase: .sending)
        MailDraftStore.saveJobs([queued.id: queued, sending.id: sending])
        let recovered = MailDraftStore.recoveredJobs()
        check(recovered[queued.id]?.phase == .held, "Restart holds queued mail for explicit editing")
        check(recovered[sending.id]?.phase == .unknown, "Restart cannot infer submission outcome")

        let generation = DiscussionStore.generation(for: refusedID)
        check(DiscussionStore.save(.init(mailboxID: refusedID, turns: [.init(question: "Question", answer: "Answer")], draft: "Follow-up"), key: "email", generation: generation), "Discussion saves")
        check(DiscussionStore.load("email")?.draft == "Follow-up", "Unsent question survives reopen")
        DiscussionStore.remove(accountID: refusedID)
        check(!DiscussionStore.save(.init(mailboxID: refusedID), key: "email", generation: generation), "Late completion cannot resurrect disconnected discussion")

        print("PASS: \(checks) send, draft, and discussion checks")
    }
}
