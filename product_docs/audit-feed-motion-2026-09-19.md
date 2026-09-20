# Native feed, navigation, gesture and motion audit

September 19, 2026 · **Review and proposals only** · Source inspected on `codex/unsubscribe-motion-audit`.

The feed already has a useful foundation: a stable reading session, explicit admission of new mail, and counts that distinguish provisional progress from provider confirmation. Its largest gaps are where an attractive control does not finish its interaction, or a background state becomes difficult to see or recover from.

This is a read-only source audit of Feed, Old Posts, root navigation, shared post/actions, receipts, loading, tokens and haptics. No app code, account data, or unrelated working changes were modified. No live mailbox action, Simulator gesture or device performance test was performed. “Confirmed” below means the behavior or missing path is established in inspected source; platform rendering and gesture outcomes are identified separately where they still need runtime validation.

## The contract being audited

The [September 19 feed contract](</Users/craigroberts/email-ai/product_docs/Email App.md:5259>) supersedes immediate disappearance on read. A real forward scroll past a whole post marks it seen; posts remain in their session positions. Opening a detail preserves the session. App return, Feed-tab return and pull-to-refresh start a fresh session. New mail waits for explicit admission. Archive has its own delayed provider action and Undo. **No more emails** means the history endpoint; verified zero additionally requires confirmed unread totals and no pending arrivals.

The [Figma audit](/Users/craigroberts/email-ai/product_docs/figma-audit-2026-09-19.md:30) distinguishes current native screens from archived concepts. [MOTION_AND_DELIGHT_SYSTEM.md](/Users/craigroberts/email-ai/MOTION_AND_DELIGHT_SYSTEM.md) preserves the monochrome DM Sans/DM Mono identity, native platform behavior, and reduced-motion/haptic rules. Earlier design prose and comments are not proof of a shipped gesture.

## Existing strengths worth preserving

- Read detection rejects programmatic motion and cancels when geometry changes; the displayed session freezes during a real scroll. This protects the user's place ([FeedView:243](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:243), [line 424](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:424)).
- The new-posts pill uses separate show/hide thresholds, then cancels scroll-reading, admits the batch and returns to the top deliberately. Reduced Motion avoids the animated camera move, and admission posts a VoiceOver layout notification ([FeedView:208](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:208), [line 516](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:516)).
- Provider-confirmed completion is separate from optimistic section counts; a missing total is not treated as zero ([FeedStore:54](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:54), [line 209](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:209)).
- The ordinary action row has 44-point targets and changes to a labeled menu at accessibility text sizes. Receipt content can reflow into a vertical arrangement ([ActionRow:44](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/ActionRow.swift:44), [ToastView:156](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/NewPostsPill.swift:156)).
- Motion and haptics share a vocabulary. Routine server events remain silent; the caret has a static reduced-motion alternative. These are useful constraints for personality in a reading product ([Tokens:525](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Tokens.swift:525), [Haptics:123](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Haptics.swift:123), [Caret:23](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/Caret.swift:23)).

## Confirmed interaction and state gaps

### 1. The reaction picker opens, but its visible choices cannot be tapped

Tap React opens a six-item picker. The picker renders `Text` emoji and has no selection callback, button or tap handler. Selection only exists in the original React target's long-press/drag completion. The comments promise that the open picker can be tapped, but that path is absent.

Evidence: [ActionRow:192](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/ActionRow.swift:192), [line 260](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/ActionRow.swift:260), [ReactionPicker:83](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/ReactionPicker.swift:83). A tap on a choice has no picker-owned effect; whether it falls through to the post's opening gesture requires device testing.

**User implication:** the animation reveals what looks like a menu, but the easiest next action does not work. Selection, cancellation, outside tap, scroll dismissal and focus return need one complete interaction contract before more expressive motion.

### 2. A cancelled receipt timer can clear a newer receipt

The receipt task is keyed to `receipt.id`. Replacing receipt A with receipt B cancels A's task. Its `try? Task.sleep` ignores cancellation and continues to unconditional `store.dismissReceipt()`, which clears whichever receipt is current. This is a source-established race, not a measured frequency.

Evidence: [FeedView:733](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:733), [FeedStore:1520](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:1520).

**User implication:** rapid archive actions, Undo, or a new outcome can lose the newest acknowledgement or reversal control. Animation cancellation and task cancellation are part of the user experience, not just cleanup.

### 3. Several archive operations share only one visible Undo

Archive work is retained in a dictionary per message, but every operation replaces the single receipt. Even with the timer race fixed, archiving B replaces A's Undo while A's five-second provider deadline continues.

Evidence: [FeedStore:1346](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:1346), [line 400](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:400), [line 416](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:416).

**User implication:** “each action has Undo” and “only the latest action is undoable from this surface” are different promises. The current presentation implements the latter without explaining the limitation.

### 4. Offline feedback is immediately overwritten

The feed-load catch sets `condition` to an OFFLINE strip for transport errors, then calls `resolveCondition()`. If no mailbox needs authentication repair, that resolver sets the condition back to normal. Existing cached cards remain usable, but their failed refresh can lose the visible freshness warning.

Evidence: [FeedStore:1015](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:1015), [line 1171](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:1171).

**User implication:** a calm screen can be mistaken for a current screen. A persistent, compact status can preserve confidence without blocking reading.

### 5. First-sync failure can remain behind “Reading your mailbox…”

An empty mailbox raises the first-sync flag before registration and keeps it through repeated loads. The retry schedule contains 80 seconds of sleeps before request time is included. The footer checks first-sync before load failure, so a failing empty mailbox continues to display the loading headline while this cycle runs.

Evidence: [FeedStore:590](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:590), [line 625](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:625), [FeedView:642](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:642).

**User implication:** at 30 seconds the person may know no more than at one second, even when a request has already failed. Loading, retrying, disconnected and waiting for background synchronization need distinct meanings; elapsed time alone is not proof of failure.

### 6. Pull-refresh acknowledgement disappears during a cached-mail refresh

While `refreshing` is true, the pull strip is hidden. The comment says the masthead supplies a reading state, but the actual `isReading` expression only covers first sync or an empty active feed checking completion. With cached unread cards, there is no explicit refresh-in-progress message from either path; the held spacer can remain while requests finish. Refresh also awaits the optional recap and badge fetch after feed loads.

Evidence: [FeedView:46](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:46), [line 279](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:279), [line 587](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:587), [FeedStore:844](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:844).

**User implication:** deliberate input loses its acknowledgement during the period when waiting needs explanation. This is separate from whether a ring, caret or static sentence is used.

### 7. Two “show new mail” paths have different behavior

The pill uses `admitPending()`, which cancels read tracking, scrolls to the top and adjusts accessibility focus. The endpoint's **See new posts** button calls only the store's insertion method. That method inserts at the top without making a navigation request.

Evidence: [FeedView:516](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:516), [line 665](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:665), [FeedStore:1522](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:1522).

**User implication:** a button that promises to show new posts may leave the reader at the old endpoint, or subject to layout anchoring behavior. Runtime testing must establish the exact viewport result; the differing code paths are confirmed.

### 8. The custom Feed-tab reselect handler cannot be reached through a value change

Root navigation increments `scrollTop` only when `previous == 0 && current == 0` inside `onChange(of: tab)`. A same-value selection is not a tab value change, so this custom handler does not implement the described re-tap behavior.

Evidence: [RootView:45](/Users/craigroberts/email-ai/apple/DecisionInbox/App/RootView.swift:45). Native TabView behavior may supply a separate default interaction; that must be tested before claiming the overall re-tap gesture is broken on every supported OS.

### 9. A CTA can look actionable without having a destination

PostView renders a CTA whenever the label is nonempty, but its action only opens a non-nil URL. The data model permits label and URL independently, and a built-in synthetic fixture already contains a label with no URL.

Evidence: [PostView:508](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/PostView.swift:508), [line 563](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/PostView.swift:563), [Message:108](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/Message.swift:108), [sample fixture:1616](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:1616).

**User implication:** the strongest-looking action can do nothing. A label alone does not establish whether the destination is a link, an attachment, a reply or the original email. That action type must be known before presenting it as executable.

### 10. The source contains motion that is not actually attached

PostView explicitly omits its row-level swipe gesture because it blocked scrolling. The swipe thresholds, background track and commit code remain in the file, but are dormant. Similarly, `pressed` starts false and is never changed: `PostPressStyle` exists without a call site. The old `CaughtUp` component also has no production call site; the actual footer is `feedFooter`.

Evidence: [PostView:42](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/PostView.swift:42), [line 100](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/PostView.swift:100), [Controls:32](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/Controls.swift:32), [FeedView:641](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:641). Repository call-site search found no attached row swipe, `PostPressStyle(...)`, or `CaughtUp(...)`.

**User implication:** proposals and verification must start from visible action buttons and tap navigation, not assume a polished swipe or press interaction already ships. Removing a broken gesture preserved scrolling; restoring one is a separate implementation/design decision.

## Accessibility and visual risks requiring runtime review

| Area | Source observation | What to verify / decide |
|---|---|---|
| Sender header | Accessibility-size handling changes HStack alignment; the name, metadata and unsubscribe control still share the same horizontal allocation. Name and unsubscribe labels remain one line ([PostView:638](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/PostView.swift:638)). | Long sender names, translated labels and large text may need true layout reflow rather than stronger compression priority. |
| Compact unsubscribe target | The chip has 10-point type plus five points vertical padding, without a 44-point minimum frame ([PostView:679](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/PostView.swift:679)). | Measure the effective target and gesture competition with the post. A visually small chip can still have a larger usable hit area. |
| Action-row width | Six 44-point controls plus group padding, minimum separation and outer gutters require at least 328 points before unusually wide counters. The large-text menu switches by type category, not available width ([ActionRow:69](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/ActionRow.swift:69)). | Test the narrowest supported window/display setting, long thread counts and layout compression. |
| VoiceOver action coverage | The post combines children and explicitly supplies Open, Unsubscribe/Reply/Forward, Discuss, Profile, Save and Archive. React, the CTA destination and attachments are not in that explicit root list ([PostView:120](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/PostView.swift:120)). | Inspect actual merged accessibility actions. Do not assume nested custom actions survive or disappear without runtime evidence. Confirm every visible action remains reachable. |
| Important low-contrast status | `Ink.tertiary` is documented as nonessential metadata, but is used for loading/count labels and read text ([Tokens:32](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Tokens.swift:32), [FeedView:883](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:883), [PostView:465](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/PostView.swift:465)). Local color calculation gives #8F8F8F on white 3.23:1, on #F8F8F8 3.05:1. | Review which text remains necessary after reading. Increase Contrast is handled by some components, not a universal correction for functional copy. |
| Failure discoverability | Read failure/retry is placed after all session posts ([FeedView:164](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:164)). | A failure near the top of a long feed may not be encountered for some time. Compare a compact persistent notice with contextual failed-post status. |
| Reduced Motion | Counts, pill travel, caret and small control scale have explicit alternatives. Direct animations remain in some shared controls; the atmosphere repeats independently of explicit visibility/scene gating. | Audit all call sites, including setting changes while an animation is running. A short animation is not automatically a reduced-motion alternative. |
| Loading vocabulary | The caret file says the app has no spinners, but feed pagination/completion and Old Posts use `ProgressView`. `EmptyStateView` says empty/error differ, yet callers use it for both. | These are design-documentation inconsistencies, not proof that a spinner is wrong. Choose semantics based on whether the wait is writing, fetching, failed or empty. |

## Interaction choices, without choosing for the user

### Rapid actions and reversal

| Concept | Buys | Costs / works less well when |
|---|---|---|
| **Latest-action receipt** | Lowest visual weight; one clear undo action. | Earlier rapid actions become unavailable to reverse from the receipt. The limitation must be intentional and understandable. |
| **Grouped action receipt** | A burst can read “3 archived” with a defined Undo last or Undo all. | Group boundaries and mixed action types need clear rules; reversing all may exceed the user's intent. |
| **Recent-actions destination** | Each action and result can be inspected and reversed where a real inverse exists. | Adds navigation and retained state for a task that should often remain quick. |

### Reactions

| Concept | Buys | Costs / works less well when |
|---|---|---|
| **Tappable popover, optional press-and-drag** | Discoverable tap selection plus the expressive finger-following interaction already explored in code. | More gesture/focus/dismissal paths to verify. It needs real buttons and a clear local-only meaning. |
| **Native menu of labeled reactions** | Familiar selection and cancellation with fewer custom mechanics. | Less visual personality and an extra menu-style step. |

### Filing gestures

Keeping visible Save/Archive controls preserves the current reliable scroll surface. Adding native row swipes could reduce repeated targeting effort, but changes row/list composition and requires a new gesture-arbitration test. Either concept still needs visible and accessible alternatives. Restoring dormant `DragGesture` code is not itself a completed design.

## The 10-second / 30-second experience

These are proposed test checkpoints, not new production timeout values. [APIClient:423](/Users/craigroberts/email-ai/apple/DecisionInbox/Services/APIClient.swift:423) sets a 15-second request timeout, but a multi-step workflow can last longer; the direct archive request does not set the same explicit timeout ([GmailClient:72](/Users/craigroberts/email-ai/apple/DecisionInbox/Services/GmailClient.swift:72)).

| Scenario | At 10 seconds, inspect | At 30 seconds, inspect | Interruption / cancellation contract |
|---|---|---|---|
| Empty first sync | Loading explains what is known and the user can leave. | Any known failure is visible; automatic retries are not disguised as unchanged progress. | Leaving does not turn unknown mail into zero or restart an endless visual cycle on return. |
| Refresh with cached posts | Existing mail stays readable and refresh has an explicit acknowledgement. | Feed failure is separate from a slow optional recap/badge update. | A newer refresh cannot be dismissed or mislabeled by an older completion. |
| Scroll-read queue | Provisional counts and confirmed read state remain distinguishable. | Multiple timed-out writes expose recoverable failure; no false zero. | Leaving cancels unsent work only; already sent confirmation is reconciled. |
| Archive after Undo deadline | The UI does not still promise cancellation once provider work is underway. | A failed or unknown provider operation has an honest receipt. | Rapid archive, Undo, navigation and app backgrounding preserve the defined reversal scope. |
| Pagination / old posts | The existing list remains usable, with a named loading state. | Retry does not duplicate posts or silently reorder already read content. | Dismissal stops view-owned loading as appropriate; late results cannot reopen a closed sheet. |
| Image / interpretation wait | The email remains understandable from source text and status. | A permanent failure differs from “still loading”; an original-email route remains available. | New content does not move a card while the reader is actively scrolling. |

## Performance and history considerations

- Feed offset sampling uses a plain reference, and region changes avoid invalidating the whole tree on every scroll frame. Preserve that benefit when adding a status surface or interaction.
- `displayedRemaining` rebuilds grouped unread sets as state changes. Long-feed cost needs measurement before adding more event-driven animation; no runtime performance regression is claimed here ([FeedView:452](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:452)).
- The masthead has three repeating gradient motions, and each interpreting post can own a caret task. Visibility/scene policies need Instruments verification; source comments that motion runs on the render server are not a benchmark ([MastheadAtmosphere:68](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/MastheadAtmosphere.swift:68)).
- Old Posts loads mailboxes serially and sorts all accumulated posts after each successful pass. A later page from one mailbox can precede already displayed mail from another. Main-feed pagination has stronger ordering logic; history needs its own multi-mailbox continuity test ([OldPostsView:67](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/OldPostsView.swift:67)).
- Old Posts owns its local post list while actions mutate the shared store. Archive visibility, Undo timing and current-version updates need explicit history semantics. Keeping an archived email in a read-history view can be valid; the UI should not imply removal from that view if it will remain.

## Acceptance checks for an approved implementation

1. Tap React → select any visible reaction → clear/change it. Also long-press, drag away, interrupt with scrolling, open another post, use VoiceOver and use large text. Selection and cancellation must agree across input methods.
2. Archive A then B within one second; trigger an error while a receipt timer runs; Undo just before the deadline; leave and return. A cancelled timer never clears a newer receipt. The chosen latest/grouped/history reversal policy remains available for its stated window.
3. Cold empty sync and warm cached refresh with immediate offline, 10-second delay, 30-second workflow delay, one failed mailbox and another successful mailbox. Existing mail remains usable; freshness and failure do not disappear because another request succeeded.
4. Admit new mail from both pill and endpoint. Confirm viewport destination, focus, read tracking and pending counts have the same meaning. Re-tap Feed on every supported OS and verify actual behavior separately from the custom callback.
5. Test every CTA with a valid URL, missing URL, unavailable attachment and external-app refusal. An enabled visible action always has a defined consequence or useful recovery.
6. Recheck the existing session contract: forward scroll only, whole-post passage, no dwell requirement, stable geometry, midnight anchoring, pagination order, read failure rollback, app/tab reset and detail preservation.
7. Review smallest supported width, landscape, maximum Dynamic Type, long identities, high thread counts, Increase Contrast, Reduce Motion and keyboard/Switch Control. Verify effective targets and accessibility actions rather than inferring them from labels.
8. Profile a long feed with images and many interpreting cards on a supported device, including off-screen/background behavior. No decorative motion delays input, changes reading geometry, or implies unsupported progress.

Existing [native model checks](/Users/craigroberts/email-ai/apple/tests/README.md:33) explicitly exclude SwiftUI geometry, scroll detection, navigation and device performance. Passing those tests would not resolve the runtime questions in this audit. The intended next design decision is how much explicit task/recovery structure the feed needs while retaining its calm, stable reading surface.
