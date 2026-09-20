# Communication and content experience audit — September 19, 2026

This is a source audit and proposal for review, not authorization to change the product. No live mail was sent, unsubscribed, archived, or deleted. No runtime behavior was reproduced in this pass. Findings distinguish direct code evidence from experience predictions; acceptance scenarios below remain unexecuted.

## Grounding and coverage

The current client is native SwiftUI. `AGENTS.md`, `product_docs/figma-audit-2026-09-19.md`, `product_docs/improvement-review.md`, `product_docs/zero-shot-philosophy.md`, and `MOTION_AND_DELIGHT_SYSTEM.md` govern this review. The September 19 docs require honest loading/completion states, preserved reading position, real source content, full sender history across connected accounts, and native navigation. Older Figma pages and portions of `Email App.md` describe capabilities that are not implemented. In particular, the older discussion contract promises persistent discussion, full-thread context, attachments and prior turns (`Email App.md:6487–6519`); the present API does not deliver that contract.

The design principle for these surfaces is continuity: the words I wrote, the email I opened, the file I tapped, and the account I am using should remain identifiable from action to result. Animation can make those connections visible once the data and controls preserve them.

| Route/surface | Source reviewed | Existing strengths to preserve |
|---|---|---|
| Original email | `Thread/ThreadView.swift`, `Thread/EmailBodyWeb.swift` | Cached body on entry; readable cached content survives failed refresh; retry without blanking the page; native Back; real bottom inset for Discuss. |
| Discuss | `Thread/Discuss.swift`, `FeedStore`, `APIClient`, server `/discuss` | User question and AI answer have distinct visual treatments; generated output is tied to a real email rather than an invented interpretation. |
| Compose/reply/forward | `Compose/ComposeView.swift`, `GmailClient`, send queue | AI draft is offered explicitly through “Use this”; human author retains Send control; ambiguous send responses are distinguished from a definite refusal. |
| People list | `Messages/DirectMessagesView.swift`, conversation store | Cached conversations remain visible on failure; loaded totals are distinct from complete totals; import errors have recovery. |
| People conversation | `Messages/DirectThreadView.swift`, `ThreadComposer.swift` | Older-page loading preserves an anchor; source hydration updates in place; inline HTTP/mailto links have scheme-specific handling; unread/source completeness is not inferred from the first page. |
| Search and Saved | `Search/SearchView.swift`, `Saved/SavedView.swift` | Reuse the same post component and sender profile routes; original email uses the common sheet. |
| Sender profile | `Profile/SenderProfileView.swift`, relevant store call sites | Shared people/company layout; source-only media grid; complete-history and source-completion gates; file failures have retry. |
| Files and links | `Messages/AttachmentViewer.swift`, `LinkCard.swift` | System Quick Look/Safari components; rich link previews default off; filenames and source URLs remain real. |

All paths in the findings below are relative to `apple/DecisionInbox/` unless explicitly prefixed `server/`.

## Source-backed findings

### C1. A second send cancels the first pending send

**Observed:** `Model/FeedStore.swift:1479–1511` stores one `outgoing` task. Every `queueSend` calls `outgoing?.cancel()` at line 1483 before creating the next task. The task checks cancellation after the undo delay at line 1487. `ThreadComposer.swift:98–108` clears the editor immediately and allows another message to be entered.

**Consequence:** two sends inside the undo window cause the earlier pending message to exit without sending, without a per-message cancellation result or restoration of its text. This follows directly from the task lifecycle; no live send was attempted.

**Decision:** independent queued messages preserve chat-like speed but require per-message state and undo ownership. One allowed pending send is simpler but needs an explicit, visible gate that preserves subsequent writing. Quiet replacement is neither behavior.

**Acceptance:** queue synthetic messages A and B within the undo window; inspect an isolated transport stub. Each intended message must have a distinct outcome. Undo B must not cancel A. Test leaving the route and backgrounding during the window.

### C2. Send feedback and Undo live away from the place people send

**Observed:** `ThreadComposer.swift:106–108` clears text and immediately calls `onSent`; `DirectThreadView.swift:142–144` interprets that as “refresh now,” before the delayed send happens. It adds no pending bubble and no send-result observer. `ComposeView.swift:258–266` dismisses immediately. `RootView.swift:23–43` has no app-level receipt presentation. Repository search finds receipt rendering only in `FeedView.swift:724–745` and `OldPostsView.swift:45–55`.

**Consequence:** the People thread, Search, Saved and profile routes do not provide their own visible send feedback or Undo. A composer presented over `ThreadView` returns to that sheet, where the Feed receipt can remain behind it. Refreshing immediately does not establish delivery. Exact tab/sheet visibility needs runtime verification. There is also no state change removing `.send` Undo when transport begins (`FeedStore.swift:1484–1489`): `undoSend` can still claim “Nothing was sent” (`:1514–1517`) after the safe pre-submission window. Cancellation after transmission starts cannot establish that claim.

**Decision:** attach sending state to the outgoing message, or provide a shared receipt reachable from every initiating route. The first reinforces conversation continuity; the second creates a common global activity model. Either needs a clear point at which Undo stops being valid.

**Acceptance:** send with a stub from each route; remain on that route through queued, confirmed, rejected and unknown outcomes. Undo is reachable during its actual window, and success never appears before transport confirmation. Cross-check the separately documented Feed receipt-cancellation race before adding more animation to receipts.

### C3. Written drafts have no recovery path after leaving, Undo, or rejection

**Observed:** `ComposeView.swift:35–39` keeps fields only in view state; Cancel simply dismisses at line 83. `ThreadComposer.swift:24,106` keeps and clears local text. `FeedStore.swift:1514–1517` cancels the task and says nothing was sent, without returning its draft. Definite send failure at lines 1501–1508 records an error receipt, without draft restoration. No draft persistence operation is present in these paths.

**Consequence:** a long reply can disappear after dismissal or a failed send, and Undo stops transmission but does not bring the words back for editing. “Undo send” and “discard my work” become coupled.

**Decision:** automatic local draft recovery keeps interruptions cheap but needs account/message ownership and retention rules. An explicit discard/save decision adds friction but makes the contract visible. The same preservation rule must cover cancellation gestures and errors.

**Acceptance:** type a distinctive draft; cancel, swipe away, switch routes, restart, undo, and inject a definite send refusal. In each case, recovery or intentional discard must follow the selected contract. An ambiguous timeout must keep the text without silently resending it.

### C4. Forward presents content that is absent from the outgoing message

**Observed:** `ComposeView.swift:65–69,161–169` displays a quoted original; forwarding may also show carousel attachments (`:247–248`). Send serializes `body: text` only (`:258–265`). `Services/GmailClient.swift:14–23` has no attachment field, and `:38–53` creates a plain-text MIME message from `draft.body`. The displayed quote and files are never included in that payload.

**Consequence:** the recipient receives only the newly typed note, even though the Forward screen visually includes the original and may show files. An empty-note forward is also blocked by `canSend` (`ComposeView.swift:221–224`). These are payload/preview mismatches, not motion defects.

**Decision:** support true forwarding with inspectable original content/files, or expose a narrower action whose name and preview accurately describe what it sends. Forwarding complete source content costs more MIME and attachment handling; forwarding a selected excerpt reduces scope but must be explicit.

**Acceptance:** use synthetic original text and a uniquely named file; inspect generated MIME locally, not through a real account. Every item represented as included must be present. Verify what an empty-note forward does. `replyAll` also currently shares sender-only prefill with Reply (`:241–246`); it needs recipient-set tests before becoming an exposed action.

### C5. Standalone links become inert in the default display

**Observed:** `DirectThreadView.swift:561–579` removes standalone HTTP(S) links from the text bubble. Lines 471–474 render those URLs through `LinkCard`. `LinkCard.swift:30` defaults rich previews to false; its offline branch (`:54–92`) is an `HStack` without `Link`, `Button`, tap handler or open-URL action. There is no enclosing action at the call site.

**Consequence:** a pasted URL on its own line looks like a link card but cannot be opened through that card by default. Inline URLs remain linked, creating an inconsistent rule based only on line breaks.

**Decision:** offline metadata and navigation are separate concerns. A URL can remain fully actionable without fetching a preview. The product choice is whether destination inspection happens within the card or on opening the system browser.

**Acceptance:** with rich previews off, open a standalone URL using touch, VoiceOver and keyboard. Merely rendering the card must make no destination request. Verify mailto, inline URLs, unavailable sites and preview-on behavior separately.

### C6. Saved is session memory, although the UI promises a place to keep things

**Observed:** `FeedStore.swift:508` derives Saved from in-memory messages/retained items; `:1431–1434` toggles a Boolean without a persistence call. Refresh carries the previous in-memory value (`:926–932`). Cold-start restoration maps cached API cards (`:425–426`) through `APIClient.swift:574`, which sets `isSaved: false`. `Services/FeedCache.swift:20–26,77–88` persists wire cards rather than bookmark state.

**Consequence:** refreshing in one session can preserve bookmarks while a new store/app launch loses them. `SavedView.swift:13–14` says “Nothing kept yet” and that bookmarked cards land here; it does not disclose session-only retention.

**Decision:** local durable bookmarks are simpler and survive restart; account-synced bookmarks support multiple devices but require a separate persistence contract. Whether Save maps to a provider label/star is another product decision, not implied by the current implementation.

**Acceptance:** save a received, already-read, archived and profile-only message; refresh, restart and reopen offline. Each remains saved according to the chosen scope. Removing a bookmark has a visible, reversible outcome without removing the underlying email.

### C7. Shared cards expose actions whose handlers are absent or discard intent

**Observed:** `Design/Components/PostView.swift:23–25` supplies empty defaults for Reply/Discuss/Forward, and its menu exposes Reply and Forward (`:134–135,310–311`). Search creates posts without those callbacks (`SearchView.swift:41–52`); Saved does the same (`SavedView.swift:20–27`). Profile explicitly maps Reply, Discuss and Forward to the same generic `openPost` operation (`SenderProfileView.swift:430–440`), whose result can be a whole People conversation (`:447–452`). Feed also maps those three actions to generic message opening (`Features/Feed/FeedView.swift:125–127`); `ThreadView.swift:24,80` receives no initial composer intent and does not initialize one.

**Consequence:** matching-looking controls behave differently depending on entry point. Search/Saved menu Reply and Forward have no useful callback; Profile and Feed open content rather than the requested action. A reusable visual component does not by itself guarantee reusable behavior.

**Decision:** central action routing buys consistent behavior across surfaces; hiding unavailable actions keeps each surface simpler. The choice should be explicit rather than relying on no-op defaults.

**Acceptance:** make a route-by-action matrix for Feed, Search, Saved, original email and Profile. Every visible Reply opens the intended recipient/context; Forward retains its intent; Discuss focuses the assistant context. Verify bookmark state reads back after the action, including the already-open original-email sheet.

### C8. Search scope is smaller than “your mail” and changes with loaded feed state

**Observed:** `SearchView.swift:12–20` filters only `store.messages` by display name, subject, quote and summary. It does not search retained/history messages, original body, sender address or files. The entry copy says “Search your mail” (`:28–29`); limited-feed scope is disclosed only in the no-results detail (`:35`).

**Consequence:** a reader can know an email exists in a profile or past history yet fail to find it here. The code supports a fast loaded-feed filter; it does not establish complete-mail search.

**Decision:** a clearly labeled local filter is immediate/offline but incomplete; a server/provider search is broader but needs loading, account scope, pagination and failures. A staged local-then-complete search buys both speeds but must keep partial and final results distinguishable.

**Acceptance:** synthetic targets exist only in unloaded history, original body, sender address, Saved and a second account. Define the intended search scope before asserting results. “No results” may only describe the scope actually searched; whitespace and case changes must not create misleading empty states.

### C9. Discuss looks conversational but each request forgets previous turns

**Observed:** `ThreadView.swift:25` creates a local `DiscussModel`. `Discuss.swift:21–39` stores visible turns only in that model. `APIClient.swift:342–348` sends only message ID and current question. `server/index.js:1728–1758` fetches one message, caps body at 6,000 characters, falls back to snippet on body-fetch failure, and sends no prior discussion turns or attachment contents. The response contains only answer text. `Discuss.swift:35–37,60–67` displays failure text in place of an answer, with no retry action. The input clears and drops focus on submission (`:158–163`); `ThreadView` has no scroll-to-answer mechanism.

**Consequence:** “What do you mean by that?” cannot reliably refer to the assistant's preceding answer. Closing/reopening loses discussion. The interface says “Ask about the thread” although available context is one message, sometimes only its snippet; readers do not see that limitation. On a long original email, the resulting turn can also be below the viewport (runtime check required).

**Decision:** single-question email analysis has less stored state but needs honest framing. A real conversation needs prior-turn context, persistence and clear source scope. Long-thread/attachment awareness is a further context choice. Keep factual recovery labels deterministic under the zero-shot exception.

**Acceptance:** ask a follow-up referring solely to the previous answer; reopen discussion; inject a missing body, long body, missing attachment and network refusal. Verify source-scope disclosure, draft retention, retry and accessible answer arrival. Auto-scroll only if the reader is already following the response; otherwise offer a “new answer” affordance.

### C10. The HTML remote-content promise exceeds the implemented blocker

**Observed:** `ThreadView.swift:277–291` promises images are blocked until Load. `EmailBodyWeb.swift:68–83` rewrites quoted `src`/`background` starting with HTTP(S) and CSS `url(...)`; there is no content-rule list or CSP in the document/configuration (`:31–41,87–102`). Unquoted image `src`, `srcset`, scheme-relative URLs and stylesheet `href` are not covered by those expressions. `server/index.js:939–961` returns the raw HTML directly.

**Consequence:** source inspection establishes coverage gaps in the claimed network policy. It does **not** prove that a particular live email triggered a request; WebKit/network verification remains necessary. Disabled JavaScript is valuable but does not block HTML/CSS resource fetches.

**Decision:** a true network-level remote-content boundary supports the existing privacy promise, while a narrower promise would disclose the limited protection. Rich email fidelity and remote-resource consent need explicit tests, rather than a reassuring label alone.

**Acceptance:** render synthetic HTML pointed at an isolated request recorder. Before Load, verify zero remote image/style/font/frame/media requests across quoted/unquoted/protocol-relative/srcset/CSS cases. After explicit consent, verify expected resources load while scripts stay disabled. Navigation remains separate from automatic fetching.

### C11. People covers only the first account without labeling that scope

**Observed:** `FeedStore.swift:653,771–773,791–793` loads People and its message pages from `auth.accounts.first`. `Conversation.swift:11–21,37–50` has no mailbox identity. `ThreadComposer.swift:98–104` supplies no `from` argument, so `FeedStore.swift:1481` uses that same first account. `DirectMessagesView.swift:128–145` and the thread composer do not display a selected account.

**Consequence:** People cannot currently establish a full all-account view, even though sender profiles are designed for all-account history. Source does **not** establish a wrong-account send in the normal present People flow: reading and sending both use the first account. The control problem is invisible scope and no explicit sender choice, especially for new mail.

**Decision:** account-scoped People is simpler but needs visible scope/selection; unified People needs mailbox identity through list, thread and reply. An aggregated sender history must still reveal which account a particular reply will use.

**Acceptance:** two synthetic accounts have mail from the same person and unique conversations. Verify scope labels, selection, counts and send identity. Reorder/connect/disconnect accounts and ensure no existing draft silently changes sender.

### C12. File opening lacks user control over a real wait and can race in People

**Observed:** `AttachmentViewer.swift:38–67` downloads full `Data` with a 60-second timeout and a shared loading/preview state, without a stored cancel handle, byte progress, or latest-request guard. Temporary destinations depend only on the cleaned filename (`:57–61,72–82`). `DirectThreadView.swift:451–456` starts a new task per tap without disabling other attachments. Its failure message disappears after three seconds (`:197–209`). Profile does guard concurrent opening and retains a retry target (`SenderProfileView.swift:227–235,459–467`).

**Consequence:** rapid taps in People can let an earlier request open after a later selection; identically named files share a destination. Large downloads offer no cancel and do not reveal whether progress is known. These are source-supported race/control risks, not a measured corruption or memory incident.

**Decision:** one explicit cancelable open at a time is easier to reason about; concurrent downloads require per-file ownership and a clear active preview. Use measured bytes only when available; a fabricated progress ring would be worse than honest indeterminate loading.

**Acceptance:** select A then B with reversed response delays, cancel, leave the route, and open two different files sharing a name. Only the selected intent may present. Failure remains actionable through retry. Verify a large synthetic file without blocking scrolling or exceeding the chosen memory budget.

## Interaction and motion opportunities

These are design candidates, not a ranking or implementation instruction. Value/complexity/risk are qualitative engineering judgments, not measured user research. Existing SwiftUI `Move` tokens and system presentations are the runtime; no web animation package is needed for these native controls.

| Candidate | Classification | Why it moves / user value | Creative upside | Complexity | Performance risk |
|---|---|---|---|---|---|
| Draft → queued message → confirmed/recovery | Functional; Tactile | Keep the user's words visible through send; high value after C1–C3 are resolved. | Medium: continuity can feel exceptionally precise. | High: data lifecycle before animation. | Low–medium; animate one message, not the thread. |
| Undo returns the actual draft to its editor | Functional; Tactile | Show where the interrupted work went; high value. | Medium. | Medium–high; draft ownership needed. | Low; focus/keyboard stability dominates. |
| Forward inclusion preview | Functional | Make actual outgoing content inspectable; high trust value. | Low–medium. | High for real attachments/MIME. | Low–medium; avoid loading every attachment preview. |
| Offline link press → in-app browser | Tactile; Functional | Make a real destination immediately actionable while preserving reading position; high value. | Medium through consistent press/release. | Low after routing fix. | Low; metadata remains opt-in. |
| Bookmark settles into persistent Saved state | Functional; Reward | Acknowledge a durable action and preserve the item; high value after persistence. | Medium, restrained. | Medium for local state; higher for sync. | Low. |
| Search's partial results → complete results | Functional | Explain search scope and arrival without suggesting false zero; high value if broad search selected. | Medium. | Medium–high depending scope. | Medium; preserve stable rows/scroll anchor. |
| Discuss answer arrival with a catch-up control | Functional; Personality | Make an answer discoverable without pulling the reader away; medium–high value. | Medium through pacing/type hierarchy. | Medium. | Low–medium; do not animate every character by default. |
| Attachment tile → actual download → Quick Look | Functional; Tactile | Connect selected file to the object that opens; high value. | Medium. | Medium. | Medium for large files; use native streaming/caching choices. |
| Profile lane selection and return position | Tactile; Functional | Preserve place across Emails/Media/Docs and a preview; medium value. | Medium. | Low–medium. | Medium for large grids; no whole-grid animation. |
| Source/email/AI boundary | Functional; Personality | A small disclosure makes “original words” versus “AI answer” unmistakable; high trust value. | Medium. | Low for labeling; higher for verified context data. | Low. |
| Continuous source → quoted excerpt → reply handoff | Signature candidate | An inspectable excerpt moves into the editor while preserving attribution; potentially high value for frequent replies. | High, if useful rather than decorative. | High: selection, source fidelity, draft state and accessibility. | Medium. Must have a static route and remain optional. |

For every candidate: preserve focus, allow interruption, keep controls usable during slow operations, stop work/loops when the owner disappears, and use `Move.resolved`/system Reduce Motion behavior. VoiceOver needs meaningful state announcements rather than narration of every network update. Effective touch targets, long names, large text, multiline drafts and one-handed keyboard use require runtime checks. Existing 32-point send glyphs (`ThreadComposer.swift:48`, `Discuss.swift:111`) warrant effective-target inspection rather than assuming surrounding padding enlarges the button itself.

## Decisions to review

1. **Sending:** independent message queue or one visibly pending send? This trades rapid chat-like entry against lifecycle simplicity; either must preserve drafts and expose outcome where the action began.
2. **Saved and drafts:** durable on this device or synchronized across devices/accounts? Persistence scope sets the user's trust contract and future migration work.
3. **Search and People:** explicitly scoped local/account views or complete unified retrieval? Speed is useful only when the reader understands what was searched.
4. **Discuss:** single-question analysis or persistent conversation with verifiable thread/attachment context? The visual interaction should promise exactly the context the API supplies.
5. **Forwarding and file work:** full email fidelity or a deliberately smaller action? Preview and payload must agree before motion communicates completion.

The proposed motions do not resolve these decisions. They make a selected, working contract easier to understand. The audit has identified specific source gaps; it does not claim current Simulator/device verification or authorize implementation.
