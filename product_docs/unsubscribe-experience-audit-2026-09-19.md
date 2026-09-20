# Unsubscribe experience: audit and proposed interactions

Date: September 19, 2026. Status: **proposal for review; no product changes approved or implemented by this audit**.

The current experience tells the user what the agent is doing, but gives them too little control over what happens next. The useful mental model is a delegated task: it needs an acknowledgement, a place to find it again, and a clear handoff when the agent cannot finish.

This document combines read-only inspection of the native SwiftUI interface and server contract. Geometry findings are supported by layout code; device rendering, gestures, VoiceOver and performance still require runtime validation. Examples describe synthetic states and contain no user email data or credentials.

## Project grounding and a documentation conflict

- The original [product brief](</Users/craigroberts/email-ai/product_docs/Email App.md:343>) describes local sender filtering and treats external agent unsubscribe as a future capability. Its [flow](</Users/craigroberts/email-ai/product_docs/Email App.md:3139>) promises future messages will be hidden.
- The newer [September 19 Figma audit](/Users/craigroberts/email-ai/product_docs/figma-audit-2026-09-19.md:38) archives those old local-blocking implications and makes the native tray, receipts and actions authoritative. The current app launches the external agent; Settings explicitly says there is no block list.
- The [zero-shot policy](/Users/craigroberts/email-ai/product_docs/zero-shot-philosophy.md:18) permits literal fallback controls and recovery copy, but forbids unsupported success claims. Generated narration cannot substitute for a reliable action or outcome.
- The current visual system is monochrome, with DM Sans for human content and DM Mono for instrumentation. Existing native tokens and platform presentation are the baseline, not evidence that every current layout is successful.

The unresolved product promise is whether “unsubscribe” means requesting removal from the sender's list, hiding future mail locally, or both. This proposal assumes the currently implemented external request; adding local hiding would be a separate decision.

## Findings

| Finding | User consequence | Evidence |
|---|---|---|
| The tray has no outer horizontal gutter or width cap. Its internal text expands to available width. | The bottom surface reads as a broad slab; its internal padding does not create space around the surface. | [FeedView:714](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:714), [UnsubscribeTray:41](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Unsubscribe/UnsubscribeTray.swift:41), [UnsubscribeTray:57](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Unsubscribe/UnsubscribeTray.swift:57). |
| The tray only opens the log; it has no close or swipe-dismiss action. | A background task occupies the feed until the user discovers the indirect clearing route. | [UnsubscribeTray:12](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Unsubscribe/UnsubscribeTray.swift:12), [UnsubscribeTray:61](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Unsubscribe/UnsubscribeTray.swift:61). |
| Log **Done** clears all statuses, including active tasks, before dismissing. A later event can add them back. | Closing a surface also discards its visible record, without stopping the server job; the tray can reappear. | [UnsubscribeRunLog:57](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Unsubscribe/UnsubscribeRunLog.swift:57), [FeedView:378](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:378), [FeedStore:1278](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:1278). |
| “Needs you” has no action. The native payload has no handoff information. | The interface announces a human task but offers no way to perform it. | [UnsubscribeRunLog:18](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Unsubscribe/UnsubscribeRunLog.swift:18), [SSEClient:28](/Users/craigroberts/email-ai/apple/DecisionInbox/Services/SSEClient.swift:28), [server payload:310](/Users/craigroberts/email-ai/server/index.js:310). |
| The agent returns on a manual blocker and closes its browser context. | A proposed **Continue** button cannot resume the stopped session with today's backend. | [unsubscribeAgent:756](/Users/craigroberts/email-ai/server/unsubscribeAgent.js:756), [unsubscribeAgent:856](/Users/craigroberts/email-ai/server/unsubscribeAgent.js:856). |
| `still_sending` falls through to **Done / All done** in the aggregate headline. Needs-you and failure also fill progress segments like successes. | Completion visuals can imply more success than the data supports. A batch headline can also refer to one sender while its detail sentence comes from another. | [UnsubscribeTray:16](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Unsubscribe/UnsubscribeTray.swift:16), [UnsubscribeTray:74](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Unsubscribe/UnsubscribeTray.swift:74), [UnsubscribeTray:95](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Unsubscribe/UnsubscribeTray.swift:95). |
| A successful mailto send is represented as `done`; native Settings stamps every `done` as **CONFIRMED BY THEM**. | “Request sent” becomes “sender confirmed,” although these are different facts. | [server/index.js:1673](/Users/craigroberts/email-ai/server/index.js:1673), [SettingsSendersView:106](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsSendersView.swift:106). |
| The “run log” stores only the latest status, not a sequence. Native storage is in memory; server terminal entries expire after 30 seconds. | A dismissed or interrupted task does not have a durable, complete receipt to return to. Native also ignores server `runId`, evidence and elapsed time. | [FeedStore:359](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:359), [server/index.js:186](/Users/craigroberts/email-ai/server/index.js:186), [server/index.js:329](/Users/craigroberts/email-ai/server/index.js:329), [SSEClient:28](/Users/craigroberts/email-ai/apple/DecisionInbox/Services/SSEClient.swift:28). |
| Settings→Senders reuses the same transient dictionary and labels all its rows **UNSUBSCRIBED**. | Working, failed and human-action tasks appear under a success heading; clearing the tray also removes this recovery route. | [SettingsSendersView:25](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsSendersView.swift:25). |
| The log promises continued monitoring, but the inspected code contains no observed producer of post-confirmation `still_sending` events. | A visible promise exceeds the demonstrated feature. Definitions and copy are not proof of monitoring. | [UnsubscribeRunLog:43](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Unsubscribe/UnsubscribeRunLog.swift:43); repository search of server status producers. |
| Only Feed presents the tray, while Profile, Search, Saved and Old Posts can start work. Repeated native taps have no in-flight guard. | Feedback varies by entry point, and the user can start another request without an explanation. | [FeedView:716](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:716), [SenderProfileView:405](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Profile/SenderProfileView.swift:405), [SearchView:47](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Search/SearchView.swift:47), [FeedStore:1437](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:1437). |

**Dismissal distinction:** the persistent tray is a custom bottom inset. The log is a native `.sheet`, and its swipe dismissal is not explicitly disabled. Source inspection supports “the tray cannot be dismissed directly”; it does not establish that the system sheet's swipe gesture is broken on device. The sheet currently has no explicit detents at [FeedView:375](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:375).

**Scope distinction:** the older Expo client recognizes only `done` and `error` as terminal. It can misread newer server outcomes such as `needs_you` and `failed` ([UnsubscribeToast:10](/Users/craigroberts/email-ai/components/UnsubscribeToast.tsx:10), [line 30](/Users/craigroberts/email-ai/components/UnsubscribeToast.tsx:30)). This is a compatibility issue if that client remains supported; it is not evidence of the native rendering.

## Three presentation choices

These choices are proposals, not a ranking. Their common requirement is that closing the interface changes visibility rather than silently changing the task.

| Choice | Experience | What it optimizes | What it costs / when it becomes painful |
|---|---|---|---|
| **Compact tray + detail sheet** | Tap Unsubscribe; a compact, inset acknowledgement appears. Tap it for details; close it while work continues. A needs-you state exposes an action in the sheet. | Fast feed cleanup with optional detail; closest to the current structure. | The user still needs a discoverable way back after dismissal. Several exceptions are difficult to explain in one tray. |
| **Auto-open sheet** | Tap Unsubscribe; immediately open a focused sender/task sheet with progress, Close, and the eventual action or outcome. | Makes the agent's scope and human handoff visible at the moment of intent. | Interrupts rapid unsubscribing and competes with the user's main feed task. Batch and repeated actions need careful handling. Closing still needs a recovery destination. |
| **Persistent activity destination** | Keep a compact acknowledgement, with a stable activity list for working, needs-you and completed tasks. Existing Settings→Senders could evolve, or the destination could be more prominent. | Tasks that survive navigation, app restarts and deferred human work; clearer batches and receipts. | Requires durable run data, reconciliation and a navigation decision. It adds conceptual weight for people who unsubscribe rarely. |

An inline sender state can complement any choice: the original control becomes a status or **View task** action so it does not keep initiating duplicate work. It does not solve recovery after that sender scrolls out of view.

For a compact-tray specimen, an outer gutter based on `Metric.gutter` (16 points) would express a floating object more clearly. A wider-window cap, expanded sheet sizing, and large-text layout remain values to review visually. Copy must not be squeezed into the existing one-line title merely to preserve a shape.

## Two human-handoff choices

| Choice | Honest action and outcome | Tradeoff |
|---|---|---|
| **Open a fresh sender page** | **Open sender page** opens the saved source URL. Explain that the user may need to repeat steps. Returning to the app leaves completion unverified unless there is actual evidence; a user-reported finish remains labeled as such. | Lower infrastructure cost and a familiar browser. The user's browser does not inherit the remote agent's cookies, redirects or form state. Some original links may be expired or single-use. |
| **Preserve and hand over the remote session** | **Continue with this page** exposes the paused browser session, then offers a defined resume/recheck step. | Better continuity when the agent already did useful work. Requires session lifetime, access, expiry, device interaction and resume contracts, plus operating cost while sessions wait. Current code closes the session, so this is a backend capability, not a cosmetic addition. |

The decision turns on whether restarting on the sender's site is acceptable, or whether “continue where the agent stopped” is central to the product promise. A **Retry** button alone is not a human handoff.

## Proposed state contract behind either presentation

Keep three independent facts: **what the job is doing**, **what evidence exists**, and **whether its surface is visible**. Today one dictionary is asked to carry all three.

| State / action | Proposed meaning |
|---|---|
| Working | The agent has accepted the job. Show the last known step; do not invent a percent from unequal browser steps. |
| Needs you | The run has a blocker, an available action, and enough information to explain what that action does. A closed remote session is not described as paused/resumable. |
| Request sent | The request was transmitted, for example through mailto. This does not establish sender confirmation. |
| Sender confirmed | The sender's page provided specific confirmation evidence. Record its source and time. It still does not promise that no future email will arrive. |
| Failed / outcome unknown | Separate a known failure from a lost connection after submission. Do not retry a possibly completed action blindly. |
| No available link | Explain the limit and any supported next action; do not offer a retry that cannot change the input. |
| Close / Hide | Dismiss presentation and preserve the run. Do not imply cancellation or unsubscribe reversal. |
| Retry | A new attempt belonging to the same task, with an idempotency policy and intelligible result. |
| Clear receipt | Deliberately remove a completed record from visible history according to a chosen retention policy. This is distinct from closing a sheet. |

The contract would need a mailbox-scoped task identity, attempt identity, timestamps, last-known status, structured outcome/evidence, available actions, and any handoff URL/session expiry. Status reconciliation needs to survive app backgrounding, reconnects, duplicate events and process restarts. The UI needs a defined priority for mixed batches, with counts such as completed and needs-you shown as separate outcomes.

There is no current native unsubscribe cancellation or Undo API: the request is dispatched immediately ([APIClient:361](/Users/craigroberts/email-ai/apple/DecisionInbox/Services/APIClient.swift:361)). Any future **Cancel** or **Undo** label requires a real, separately specified effect.

## Motion opportunities for review

The ratings below are **qualitative design/engineering judgments**, not measured benchmarks or priorities. “Tool” names the proposed production layer for this native app; a Motion-based web study may help review an interaction, but does not prove SwiftUI integration or performance. Existing behavior is cited where relevant; these are opportunities to refine it, not claims that all motion is missing.

| Opportunity | Category | User value | Creative upside | Complexity | Performance risk | Tool |
|---|---|---|---|---|---|---|
| Unsubscribe acknowledgement enters once, with a stable footprint | Functional | High: confirms the tap was accepted | Medium: a compact, deliberate arrival | Low | Low: transform/opacity only | SwiftUI transition + existing `Move.crisp` |
| Tray close follows the finger, then settles or dismisses | Tactile | High: clear user control | Medium: tactile release | Medium | Low | SwiftUI gesture + `Move.settle` / `Move.exit` |
| Detail sheet opens from the task, with a clear return | Functional | High: explains where detail belongs | Medium | Low–Medium | Low with native presentation | Native SwiftUI sheet; system-owned transition |
| Step narration crossfades without bouncing or growing the tray repeatedly | Functional / Personality | High: readable status without distraction | Medium | Medium: text/layout stability | Low if updates are bounded | SwiftUI content transition + `Move.crossfade` |
| Needs-you state reveals its action once | Functional | High: moves from observation to agency | High: meaningful punctuation | Medium | Low | SwiftUI layout/opacity; haptic policy requires review |
| Confirmed result resolves into a compact receipt | Reward | High: makes the outcome legible | Medium | Medium: needs trustworthy outcome state | Low | SwiftUI symbol/content transition; no generic success cue for mailto |
| Mixed-batch counts update independently from success/attention labels | Functional | High: avoids false “all done” | Medium | Medium | Low | SwiftUI numeric transitions + stable identity |
| Return from a human handoff shows a bounded recheck state | Signature candidate | High: explains what the app knows now | Medium | High: backend outcome contract | Low rendering; medium service cost | SwiftUI + task reconciliation |
| Feed section counts advance and restore clearly on failure | Functional | High: keeps optimistic counts understandable | Medium | Medium: preserve existing session rules | Medium if tied to scrolling/layout | Existing native numeric transition; [FeedView](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift) |
| New-posts pill admits a chosen batch without moving mail during reading | Functional | High: preserves orientation | Medium | Medium | Medium for a large list update | Existing [NewPostsPill](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/NewPostsPill.swift) + SwiftUI |
| Archive swipe arm, retreat and committed exit remain distinguishable | Tactile | High: makes reversible intent clear | Medium | Medium | Medium on long feeds | Native gesture + haptics if chosen; [PostView](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/PostView.swift) currently leaves its row drag unattached |
| Sender profile lane changes keep selection and content spatially connected | Functional | Medium: preserves context across email/media/files | Medium | Medium | Medium for image grids | SwiftUI selected marker/content transition; [SenderProfileView](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Profile/SenderProfileView.swift) |
| Send control readiness changes quietly while typing | Functional | Medium: explains when sending is available | Low–Medium | Low | Low | Native button state transition; [ThreadComposer](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Messages/ThreadComposer.swift) |
| Reaction picker focus follows the finger with restrained scaling | Tactile | Medium: clarifies the selected reaction | High | Medium | Low for the bounded set | Existing [ReactionPicker](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/ReactionPicker.swift) + native haptics |

Existing unsubscribe entry/exit motion already respects Reduce Motion at [FeedView:702](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:702). The explicit clear-all animation at line 378 bypasses that resolver. The native [haptic policy](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Haptics.swift:123) intentionally keeps routine SSE updates silent; any attention cue would need a once-per-meaningful-transition rule rather than buzzing on every status event.

## Decisions still open

1. How much ongoing work should the feature own after the user leaves the email: a brief request receipt, or a resumable task with a durable home?
2. Should unsubscribe start in the background, or open its detail sheet immediately?
3. Is a fresh browser page sufficient for human handoff, or is preserved-session continuation part of the promise?
4. What counts as success in the UI: request transmitted, sender confirmation, or a separately implemented observation that sending stopped?
5. Does local sender hiding belong in this scope? The current implementation does not supply it.
6. Where should deferred tasks live, how long should receipts remain, and what should a cleared record mean?
7. Is the legacy Expo client still supported against this server, or outside the active product scope?

## Acceptance and validation plan after a design is chosen

No live unsubscribe is required for these initial checks. Use synthetic fixtures and a controlled sender page; reserve a real mailbox action for a separately authorized end-to-end check.

- **Geometry:** small/large phone, landscape, wider supported windows, and all Dynamic Type sizes. The tray has visible outer space; controls remain reachable; long sender names and blocker reasons do not hide the action. Expanded details scroll without clipping.
- **Dismissal:** close button, downward gesture and system-sheet dismissal have the same documented visibility effect. Working and needs-you tasks remain recoverable. Closing cannot silently clear history, cancel work, or reappear on every routine event.
- **Human actions:** each blocker offers a real supported action. Opening a fresh page is labeled honestly. A preserved-session flow handles expiry and return without claiming completion automatically.
- **Outcome truth:** mailto sent, page confirmed, needs-you, no-link, known failure, unknown outcome, and mixed batches each have distinct assertions. `still_sending` never produces **All done**. No monitoring promise appears without an implemented and verified producer.
- **Entry points:** Feed, Profile, Search, Saved and Old Posts acknowledge a request and link to the same task. Repeated taps do not launch duplicate work unintentionally.
- **Continuity:** test app background/return, network loss/reconnect, duplicate/out-of-order events, server restart, multiple mailboxes, and retry while an earlier result arrives. Durable-state behavior must match the chosen scope.
- **Accessibility:** VoiceOver exposes the tray as an actionable control, close and handoff actions have clear names, focus returns to a useful location, and status announcements avoid repeated interruption. Verify keyboard/Switch Control, adequate action targets, contrast and non-color outcome distinctions.
- **Reduce Motion:** replace spatial movement with stable changes or fades; check explicit action animations as well as entry/exit. No repeated pulse or ornamental loader is necessary to know work continues.
- **Performance:** inspect on a supported device with realistic feed volume and rapid status updates. Measure scrolling responsiveness and layout churn; do not infer quality from a desktop motion study.
- **History semantics:** closing, clearing completed receipts and cancelling an attempt are tested as separate actions if offered. A “run log” either presents actual event history or uses a more accurate name.

The presentation choice determines how intrusive the feature feels. The state and handoff choices determine whether the user can trust it after the attractive surface closes.
