# Communication and content implementation — September 19, 2026

Implemented after the user approved the app-wide audit. Grounding: `audit-communication-content-2026-09-19.md`, `MOTION_AND_DELIGHT_SYSTEM.md`, and the current native app. No real mail was sent, modified or deleted; no service was deployed.

The organizing idea is continuity: keep the same words, account, source and operation identity visible as an action moves from intent to result.

## Implemented behavior

- **C1–C3: sending and recovery.** `FeedStore` owns independent UUID send jobs. One queued send cannot cancel another. Undo is available only before provider submission and keeps the draft. Provider acceptance, definite refusal and unknown outcomes have distinct states. Queue/submission intent is persisted before transmission; a restart holds queued work and marks interrupted submission unknown, without automatic resending. Local drafts and jobs use protected, backup-excluded storage. Every relevant navigation/sheet route has Activity access, and People shows the outgoing words and their current status in place. Activity provides editable drafts; dismissing an unknown outcome retains its mandatory Check Sent acknowledgement even after reopening the editor. Disconnect removes only that account’s work and cancels owned operations.
- **C4: truthful forwarding.** Forward loads actual original text, or attaches the original HTML document when no plain text exists. The composer distinguishes included forward content from reply reference context. Displayed source attachments are downloaded and included as MIME bytes; combined files over 25 MB are rejected, and missing downloads keep the draft open. Closing during preparation cancels it. Incomplete forwards preserve their intent and remain blocked until the source loads. A standalone local MIME parser verifies the generated payload. No Gmail resource ID is forged into an RFC Message-ID.
- **C5/C7: functional routes.** Offline link cards are real accessible buttons, using the enclosing URL routing without fetching a preview. Search, Saved and Profile route Reply/Forward/Discuss to the same initial intent in `ThreadView`; Thread actions read current bookmark/reaction state. Feed/OldPosts integration uses the same initializer. Thread displays which one email is open, rather than suggesting the entire correspondence is on screen.
- **C8/C11: honest scope.** Search filters loaded feed and saved emails, including sender address and original snippet, with scope visible before and after searching. People identifies its current mailbox and passes it explicitly into sending. This does not introduce whole-mail retrieval or a unified multi-account People index.
- **C9: discussion continuity.** Questions, answers and unsent input survive reopening on this device. Requests include bounded prior user/assistant turns; the server rejects privileged history roles and reports source coverage: one email body or snippet, whether truncated, prior-message count, no attachment contents. HTML-only source uses extracted readable text. Retry keeps the question. The input retains focus; a reader-controlled latest-answer action reaches the response without dragging readers away when an answer finishes. Late requests cannot recreate discussion records after that account disconnects.
- **C10: remote content.** Email HTML loads in a nonpersistent WebKit store with page JavaScript disabled. A deny-by-default CSP precedes sender markup; a WebKit content rule blocks HTTP(S) resources before loading the document. A rule compilation failure fails closed. Explicit Load permits image/style/font resources, while scripts, frames, forms, objects and programmatic connections remain disabled. Automatic navigation is blocked; deliberate supported links open externally.
- **C12: file ownership.** Each file request owns a cancellable download and UUID destination directory. A newer selection cancels the previous request, and stale completions cannot replace the chosen preview. File content streams to disk. People/Profile provide Cancel and persistent retry instead of an expiring error toast. Leaving the route cancels pending work.

Root implementation owns C6 durable Saved and the shared Activity presentation; these views use those APIs.

## Motion and control

People’s outgoing row preserves identity through queue, sending and result, with Undo beside the actual words. The Activity row uses the same state continuity. Discussion answer arrival uses a restrained transition and an accessible announcement, with explicit scrolling when requested. Profile’s selected-lane marker moves between tabs while content is replaced without animating the whole media grid. Send controls use 44-point targets. These additions use existing motion tokens and Reduce Motion fallbacks; there are no new success haptics or per-character AI animation.

## Verification

- `apple/tests/run-send-lifecycle-tests.sh`: **35 checks passed**, compiling production FeedStore and persistence models against controlled transport doubles. Covers two simultaneous sends, selective Undo, the submission boundary, preserved refusal, ambiguous timeout without retry, restart recovery, unknown-send guard across editor persistence, incomplete-forward state persistence, discussion draft recovery, and disconnect late-write invalidation.
- `apple/tests/run-gmail-mime-tests.sh`: **passed** against production MIME generation and Python’s independent email parser. Covers original text, exact binary bytes, Unicode filename/subject, CC, genuine reply header handling, CRLF injection and attachment size limit. The tests exposed and fixed a Swift CRLF grapheme validation edge.
- `server/discussionContext.test.js`: **3 tests passed** for prior-answer continuity/role restrictions, history bounds/order and truthful source fallback/truncation.
- `EmailHTMLPolicyTests.swift`: **passed** for policy ordering, deny-by-default directives and the consent boundary. This is a policy-construction check, not a claim of recorded WebKit traffic.
- `python3 apple/tests/run-email-webkit-tests.py`: **passed on macOS 26.5.1 / WebKit 21624.2.5.11.4** using the production policy and extracted current configuration, content rule and navigation delegate in a hidden native view. The loopback recorder saw 0 requests before consent, 8 image/style/font requests after consent, and 0 after revocation. Script/fetch/form/media/frame resources stayed blocked; automatic navigation reached the delegate and was cancelled; deliberate HTTP/mailto actions reached a recorded external-open boundary without opening apps. Nonpersistent storage was verified. This is actual WebKit runtime evidence, separate from the construction test.
- Native Simulator builds were run while integrating this work. Final whole-app build status is recorded in the parent implementation note.

## Practical limits

Drafts and discussions are local to this device, not synchronized provider drafts. People still uses the first mailbox; its identity is now visible. Search remains a loaded-content search. Discussion reads one email and bounded recent conversation, not all thread emails or attachment contents. Forwarding uses actual text plus files rather than attempting to reproduce arbitrary sender HTML as the outgoing body. Reply-all remains unexposed because the present message model does not supply the full recipient set; existing conversation grouping does not guarantee provider thread grouping without a real RFC reply header.

No live account or real AI call was used. Device/VoiceOver/keyboard interaction, narrow and large-text geometry, frame timing, attachment cancellation over a real network, and iOS-specific WebKit verification remain separate runtime verification items. The hidden macOS WebKit request-recorder test described above has passed. The code and synthetic tests establish state/payload boundaries; they do not establish measured animation performance or external delivery.

## Final review follow-up: unsubscribe task ownership

Independent review found two ways an unsubscribe could remain queued forever:
an app closing before server acknowledgement, and a fresh local attempt being
rejected as a duplicate while the server still owned an earlier attempt. The
POST response now returns the authoritative accepted task. Only that direct
response can adopt a different existing attempt; ordinary stale stream/list
updates still cannot overwrite a new user intent. A recovered unacknowledged
intent, or an unchanged active record missing from a successful server snapshot,
becomes explicitly unconfirmed with manual recovery, never an automatic retry.
A snapshot started before newer evidence arrived cannot erase that evidence.

`node --test server/tests/unsubscribeAcknowledgement.test.js` passes four
production-route fixtures for initial acknowledgement, both existing-worker
paths, and queued-storage failure. A failure before external work now publishes
`failed/not_started` with “No request was sent to the sender,” even when the
second persistence attempt also fails. Native adoption/recovery checks are maintained in the shared interaction
lifecycle suite. No external unsubscribe work is performed by these fixtures.

## Composer recovery entry routes

A final interaction review found that reopening an incomplete forward could
lose its transient error message, leaving Send disabled with no retry control.
The retry now derives from durable `originalLoaded` state and remains available
on reopening, independently of any error string.

The same review found that an unknown-send draft reopened through ordinary
Reply could load its text without loading the Check Sent guard. One production
recovery-state object now hydrates both explicit Activity drafts and drafts
looked up by the normal editor route. Warning, persistence and the Send gate
all use that hydrated state. Closing/reopening cannot silently remove the guard.
The send lifecycle runner extracts this production helper from ComposeView;
ten regression checks exercise both routes, guard re-persistence, explicit
acknowledgement, and incomplete-forward retry/loading/success states.
