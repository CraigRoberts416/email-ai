# September 26 feed recovery evidence

Synthetic mail captured by native XCTest on iPhone 17 Pro / iOS 26.5 from the combined recovery and robot-artwork implementation. The first two images follow real forward swipes and a Feed-tab retap to inspect the retained first card. The test asserted that its accessibility value became **Read** and that the **TODAY** count became smaller than its starting value.

- `read-and-count.png`: read card remains in the current session with the reduced count.
- `read-during-refresh.png`: the same checks pass while the robot refresh is held open.
- `completed-receipt.png`: the global completion banner was dismissed; reopening Activity retains the honest user-reported receipt.

The first test then switches Saved → Feed and asserts the read card is absent. The Activity test reports completion of a synthetic unsubscribe handoff, verifies the global banner disappears, then opens Activity and finds **Marked complete by you**. No real unsubscribe, send, archive or deletion is performed.

Final combined result bundle: `/tmp/di-260926-combined-ui-final.xcresult` — all seven native touch tests passed, zero failures, 111.6 seconds. The implementation matches release archive 2609261241; the test bundle is excluded from that archive. Two preceding combined attempts stalled before runner launch and are infrastructure failures, not passing app tests.

Earlier bundles: `/tmp/di-260926-recovery-ui.xcresult` (six passing checks); `/tmp/di-260926-count-banner-ui.xcresult` (three strengthened checks). `/tmp/di-260926-refresh-before.xcresult` reproduces the refresh-read failure against the older local binary.

These images do not establish physical-device frame pacing, haptic feel, or the live-account reconnection result.
