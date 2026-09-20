# Synthetic native UI checks — 2026-09-20

Device: `DecisionInbox-Craft-QA`, iOS 26.5, UDID `FDF42A48-895A-4D48-81D1-00C564D1A77D`.
App: `com.craigroberts.decisioninbox`. All launch and SDK screenshot commands target that exact device, never the generic `booted` selector.

These images contain bundled sample content. No live-mail content is retained here. The initial three Sky captures predate the final Feed return-control and large-text fixes; the device-specific captures described below show the later build.

## Interaction checks completed through Computer Use

- The compact Activity summary sits above the native tab bar; all tab controls are visible. See `feed-activity-tabs.png`.
- Tapping that summary opens the medium native Activity sheet with a grabber, Close button, actionable Needs you record, and separate Request sent record. See `activity-medium.png`.
- Close returns to Feed with the compact summary still present. Hide activity summary removes the summary from the feed without opening another screen.
- Tapping the first sample email's reaction icon opens the labeled reaction popover, with Done and the explanation that reactions stay in the app. See `reaction-picker.png`.
- Choosing Reading closes the popover and replaces the email's reaction icon with the selected eyes mark. The email does not unexpectedly navigate to its thread.

## Limits

Simulator window focus repeatedly changed to another device during the session. Further gestures were stopped. No send, archive, delete, unsubscribe, or external sender-page action was performed.

Scrolling/dragging, reaction Done/outside dismissal, hold-and-drag reaction selection, Activity reopening after hiding, navigation return, Reduce Motion, VoiceOver focus, and haptic behavior remain unverified. Tab controls being visible is not evidence that every tab was tapped successfully. These screenshots do not establish animation frame rate or physical-device performance.

## Device-specific render checks

After foreground interaction stopped, read-only screenshots came directly from the dedicated Simulator's SDK interface. Each launch used synthetic fixtures. The large-text fixture sets SwiftUI `dynamicTypeSize` to `accessibility5`; system preferences were not changed.

| Surface | Evidence | Actual finding |
| --- | --- | --- |
| Normal Feed | `feed-activity-control.png` | Activity return button is visible alongside the dateline without covering text. Compact summary remains above the visible native tabs. The new button's tap path has not been exercised. |
| Normal Activity sheet | `activity-final-normal.png` | Close, native grabber, sender, truthful needs-you copy, fresh-page explanation, Open sender page, Refresh status and Details fit in the medium sheet's first visible record. |
| Largest-text Feed | `feed-accessibility5.png` | The dateline and Activity control fit. The shortened “1 needs you” status fits on one line, Hide stays visible, and the tray leaves the native tabs visible. The previous excessive height is retained in `feed-accessibility5-before.png` for comparison. |
| Largest-text Activity sheet | `activity-accessibility5.png` | Sheet content actually receives the large-text setting. Close stays visible; heading, sender and status wrap naturally. Later content is below the scroll viewport; scrolling and those offscreen controls were not exercised. |
| Largest-text onboarding example | `onboarding-accessibility5.png` | Both comparison labels fit as whole single lines in stacked, full-width rows. No pill clipping remains in the inspected controls. The rest of the long example continues below the viewport. |

## Changes driven by these captures

- **Onboarding controls:** `onboarding-accessibility5-before.png` showed the horizontal comparison pills splitting “Original” into fragments. At accessibility sizes the choices now stack, align their labels left, and use rounded rectangles with padding. Normal-size pills remain. The final capture confirms the labels are legible.
- **Activity fixture:** `activity-large-fixture-before.png` showed large Feed text behind a normal-size sheet. The DEBUG fixture override now also applies inside presented Activity content. This is a test-fixture fix, not a claim that the earlier screenshot tested large Activity text.
- **Compact unsubscribe summary:** accessible-size presentation uses a shorter count/status and omits the secondary sender from the visible compact row. The full status and sender remain in its accessibility label, with task details available in Activity. The final large Feed capture confirms a single-line status; the final normal Feed capture confirms that the ordinary title and secondary sender remain unchanged.

The final native target rebuilt successfully after all three changes, using the same signed Simulator build command recorded in the implementation ledger. Build output is at `/tmp/decision-inbox-final-qa-build.log`; the only warning reported was skipped App Intents metadata extraction because the target has no AppIntents dependency. Install completion was awaited before every new build's launch. The dedicated device was left running normal `-sampleActivity` (PID 60894), without changing foreground window selection.

## Reproduction

Build with the project's normal native command, then install the produced app on the dedicated device. Launch combinations used:

```text
-sampleActivity
-sampleActivity -sampleActivityExpanded
-sampleActivity -sampleLargeText
-sampleActivity -sampleActivityExpanded -sampleLargeText
-sampleOnboarding -sampleLargeText
```

`-sampleLargeText` and `-sampleActivityExpanded` are DEBUG fixtures. There is no functioning `-sampleReduceMotion` fixture. Installed `simctl ui` supports appearance, contrast and content size, but does not expose a Reduce Motion switch; no reduced-motion runtime validation is claimed.
