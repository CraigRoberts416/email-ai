# Feed recovery and robot refresh — 1.0 (2609261241)

September 26, 2026. One combined release includes the feed recovery fixes and the Animation task’s user-selected robot artwork. It supersedes 2609210445. Implementation tree: merge `e2a57fa`, identical to the tested combined branch `01d5135`; the merge preserves both tasks’ histories.

## Resulting behavior

- Real scroll passes reduce the section count even while a refresh is running. Confirmed-read cards stay in the current feed session and leave on the next app/tab/refresh boundary.
- Marking the final pending unsubscribe handoff complete dismisses its global summary; its honest **Marked complete by you** receipt stays in Activity. Replay/relaunch do not restore that completed banner. Other pending work stays visible.
- An expired Google refresh grant surfaces **Reconnect**, retains read intents, and sends them after successful reconnection. Temporary network errors still offer **Retry**. This repairs recovery rather than promising that Google consent never expires.
- The robot knocks at the phone edge. Falling envelopes are driven by newly arrived message identities; successful refresh without arrivals remains quiet. Native text/actions, reduced-motion static drawing and runtime lifetime gates are preserved.

Details: [recovery audit](feed-recovery-2026-09-26.md), [artwork contract](mailroom-robot-2026-09-26.md), and [Figma verification](https://www.figma.com/design/LlstGMGXZrDiY2Ee4dd3yl/Email-App-Component-Library?node-id=380-1879).

## Verification

- Production FeedStore integration: **168 checks passed**.
- AccountConnectionPolicy: **18 checks passed**.
- RefreshArrivalSnapshot: **7 checks passed**.
- Combined native **FeedGestures** suite: **7 tests passed, 0 failures**, 111.6 seconds, iPhone 17 Pro / iOS 26.5. Real gestures cover read/count updates, refresh-time reading, next-visit removal, banner/receipt state, thread return, tab return and returning to the feed top. Result bundle: `/tmp/di-260926-combined-ui-final.xcresult`.
- The refresh-read regression failed against the older local binary before passing against the correction. The banner regression also failed before the model fix. Initial combined attempts stalled before runner launch; restarting Simulator launch services recovered the final suite. Those attempts are not counted as app passes.
- The artwork task’s native checks verified 116 state bindings and release of 16 temporary Rive configurations; 18 art rendering/structure checks passed.
- Release archive succeeded. Bundle/version, code signature, bundled Rive license, absence of DEBUG fixture routes/UI-test bundles and production artwork hash were verified. Rive remains pinned to 6.24.0; the 203,169-byte asset SHA-256 is `144d63f650f48438b469872c2efe82eaf406d1e4f58846fdab98543d563c1e4f`.

The preserved real-account Simulator grant returned Google `invalid_grant`; the app’s cached feed and **Reconnect** state were inspected. Google sign-in is open in the fresh DecisionInbox-Recovery-QA Simulator, awaiting the user. Authenticated refresh, read delivery and a real arrival bubble remain unverified in this turn. Synthetic proofs are [retained here](../tools/motion-lab/native-qa/feed-recovery-260926/README.md). No real send, unsubscribe, archive, deletion or account disconnect was performed. No physical-device performance pass is claimed.

## Distribution

**Xcode Organizer uploaded 1.0 (2609261241) to Apple at 12:47 EDT on September 26.** Its completion screen and submission status both identify this build. [Upload confirmation](../tools/motion-lab/native-qa/feed-recovery-260926/upload-2609261241.jpg).

Archive: `~/Library/Developer/Xcode/Archives/2026-09-26/DecisionInbox 2026-09-26 12.41.xcarchive`.

**TestFlight availability verified at 18:33 EDT on September 26**, after the user signed in to App Store Connect. Apple lists the upload as **Complete**. The [build detail](https://appstoreconnect.apple.com/teams/69a6de7f-4205-47e3-e053-5b8c7c11a4d1/apps/6812023896/testflight/ios/54ede785-4a10-4e1c-ab48-49bb63e85c3f) includes the existing Internal group with one tester. The [Internal group](https://appstoreconnect.apple.com/teams/69a6de7f-4205-47e3-e053-5b8c7c11a4d1/apps/6812023896/testflight/groups/d9b7f44a-51be-426e-b1ec-9814e0085935) reports **Installed 1.0 (2609261241), Sep 26, 2026**, on iPhone 17 Pro Max / iOS 26.7. This confirms internal tester availability and Apple-reported installation; it is not a physical-device behavior or performance test.

No additional upload, group assignment or tester membership change was needed. The build list's **Ready to Submit** label does not negate the Internal group's reported installation; no external beta review or public App Store release was submitted. Native-only changes require no backend deployment; the previously live backend remains `a6e9043`.
