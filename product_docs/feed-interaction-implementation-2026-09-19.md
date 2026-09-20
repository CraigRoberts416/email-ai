# Feed interaction implementation — September 19, 2026

Implemented after the user approved the app-wide audit with “ok do all of it.” This selects a calm expressive native direction from the concept appendix; it does not combine the mutually exclusive signature alternatives. No new animation runtime, live mail action or account operation was used for this work.

## Changes

| Area | Implemented behavior | Reason / boundary |
| --- | --- | --- |
| Reactions | Tap opens a labeled native popover with select, change, remove and Done. Native outside dismissal and accessibility Escape are available. Hold-and-drag reveals the compact dock; stationary release opens the tappable choices; releasing outside the dock cancels. | The ordinary tap path now completes the interaction. The copy explicitly says reactions remain in this app and send nothing. |
| Reaction feel | The focused glyph and neighbors lift gently; Reduced Motion removes that spatial response. Gesture-state cleanup closes an interrupted dock. Discrete selection retains existing haptics. | Small controls can feel physical while the email text stays still. No new haptic vocabulary. |
| Action layout | `ViewThatFits` uses the labeled Actions menu when the row and dock cannot fit the available width. The accessibility-size menu remains. | Width and text size both matter; tap targets do not shrink to fit. |
| Press response | Primary and ghost buttons use the existing `TapStyle`. The post reading surface observes a simultaneous, long-duration hold with an eight-point movement tolerance for a fill-only touch response. | No row-level drag is added. The passive hold/scroll/context-menu interaction still needs Simulator verification; source parsing cannot prove gesture arbitration. |
| Filing | Save/Archive remain visible, in menus and in accessibility actions. Dormant custom archive-swipe code is removed. | The existing ScrollView previously failed with row drag recognizers. Native `swipeActions` would require a deliberate List migration and geometry/read-tracking retest. |
| Pull refresh | A thin margin follows pull tension and aligns when armed. After release, the same status moves into a real top safe-area inset, stays visible while working and resolves to freshness or a persistent Retry/Dismiss failure. | The working indicator cannot cover the mail while the user continues scrolling. Gesture progress is never network progress. |
| Refresh timing | The current refresh ID owns its settle timer; cancellation or a newer request cannot dismiss a newer status. Ten- and thirty-second labels acknowledge the wait without inventing percentages. Keyboard and accessibility refresh take the same path. | A known outcome owns the result; elapsed time does not establish failure. |
| First loading | An empty-feed failure is checked before first-sync loading. Initial/checking states get explicit 10/30-second copy with a named caret. Zero selected mailboxes gets a chooser, not a completion state. | Slow, failed, empty and deliberately filtered-out mail are different states. FeedStore corrections are owned by the integration task. |
| New mail | The footer and new-post pill call the same admission helper, including scroll-read suspension, viewport movement, one batch reveal and accessibility notification. | One action has one spatial consequence regardless of entry point. |
| Completion | A small margin punctuation settles only from the verified completion flag. The masthead uses clear atmosphere only for verified completion. Initial appearance does not stage a reward. | The feeling is relief and stillness; reaching a list endpoint does not finish tasks contained in emails. |
| Original routes | Feed and Old Posts preserve Reply, Forward and Discuss intent into the shared ThreadView initializer. Feed keeps native post-to-thread continuity with a Reduced Motion fallback. | The chosen action reaches its destination. ThreadView implementation is owned by the communication task. |
| CTA recovery | Missing or unsupported action URLs lead to a clearly labeled “Open original email” action. An OS-refused URL offers the same recovery. Accessibility link traits reflect whether the action actually opens a link. | No enabled action silently does nothing; opening source does not pretend to perform the missing sender action. |
| Targets and text | Unsubscribe and avatar targets meet the shared 44-point target; large-text promotional headers place Unsubscribe on another line. Names and metadata can wrap. Functional read/status text uses secondary rather than tertiary ink. | Readability and identity survive larger text without making all content smaller. |
| Accessibility actions | The combined post adds explicit reactions, reply/forward on promotions, primary action and each attachment. | Visual actions remain reachable even when children are combined into one reading element. Actual rotor presentation needs device inspection. |
| Lifecycle | Carets and masthead atmosphere respect scene phase, scroll visibility, Reduced Motion and an ancestor `motionIsActive` flag. Feed suspends decoration behind its destinations. | Background/off-screen state does not justify ongoing decorative work. Device energy/frame profiling remains separate. |
| Activity ownership | Feed and Old Posts no longer render independent unsubscribe/receipt hosts or timers. Old Posts exposes the shared `ActivityToolbarButton`. | Root’s global activity host owns receipts, undo windows and logs. This change relies on that concurrent integration. |

## Changed files and integration contracts

- `Features/Feed/FeedView.swift`, `OldPostsView.swift`
- `Design/Components/ActionRow.swift`, `ReactionPicker.swift`, `PostView.swift`, `Controls.swift`, `Caret.swift`, `MastheadAtmosphere.swift`
- New environment value: `EnvironmentValues.motionIsActive`, default `true`. Looping components additionally check their own visibility and scene phase.
- New optional action-row callback: `onInteractionChanged(Bool)`. Feed uses it to suspend read tracking/new-post entrances during reaction interaction.
- New optional CTA argument: `isLink`, default `true`, set false for original-email fallback.
- Shared dependencies: `ThreadView(message:initialComposeIntent:focusDiscussion:)` and `ActivityToolbarButton()` are supplied by the communication/root work.

No FeedStore, RootView, ThreadView, settings or server implementation was edited by this feed task.

## Checks performed and remaining

The Swift frontend successfully parsed all eight changed files together. `git diff --check` passed for these files. These are syntax/patch checks, not an integrated typecheck or runtime claim. Root owns the complete Xcode build and cross-agent test run.

Synthetic runtime checks required for integration:

1. Scroll a long synthetic feed starting on text, media, reaction and other controls. Verify the fill-only press returns on movement, taps open once, and long-press context menus remain available. No mailbox mutations are needed.
2. Tap React → select/change/remove; hold → release without travel; hold → drag across choices; release above/below/left/right; scroll or navigate during a hold; dismiss the popover outside and with Escape. Confirm no unintended reaction or email navigation.
3. Pull below threshold, arm then disarm, release to refresh, complete immediately, delay 10/30 seconds, fail, retry and leave/return. The working inset reserves real space, visible mail remains readable, and an old timer cannot clear a newer state.
4. Open Reply/Forward/Discuss from Feed and Old Posts. Verify the intended composer/input and preserved feed session. Check Activity from Old Posts and nested original-email sheets.
5. Test every action with maximum Dynamic Type and a narrow viewport. Inspect VoiceOver actions, focus return, keyboard refresh, Reduce Motion toggled mid-animation, high contrast and off-screen/background behavior.
6. Verify true zero, unknown totals, no selected mailboxes, a pending arrival, a read rollback and an endpoint with unread mail. Only the appropriate known state receives the completion treatment.
7. Profile a long synthetic feed on a supported physical device. The changes are designed to limit work, but no frame-rate, energy or leak result is claimed from source inspection.

The long-press feedback uses [Apple’s documented movement-failure behavior](https://developer.apple.com/documentation/swiftui/longpressgesture/maximumdistance); coexistence with this app’s scroll and context menu still requires the runtime check above.
