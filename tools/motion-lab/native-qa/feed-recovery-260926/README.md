# September 26 feed recovery evidence

Synthetic mail captured by native XCTest on iPhone 17 Pro / iOS 26.5. Both images follow real forward swipes and a Feed-tab retap to inspect the retained first card. The test asserted that its accessibility value became **Read** and that the **TODAY** count became smaller than its starting value.

- `read-and-count.png`: read card remains in the current session with the reduced count.
- `read-during-refresh.png`: the same checks pass while the illustrated refresh is held open. This capture uses the pre-integration receipt artwork; the separately refined robot artwork needs its own combined check.

The first test then switches Saved → Feed and asserts the read card is absent. A separate native test reports completion of a synthetic unsubscribe handoff, verifies the global banner disappears, then opens Activity and finds **Marked complete by you**. No real unsubscribe, send, archive or deletion is performed.

Result bundles: `/tmp/di-260926-recovery-ui.xcresult` (six passing touch checks); `/tmp/di-260926-count-banner-ui.xcresult` (three strengthened passing checks). `/tmp/di-260926-refresh-before.xcresult` reproduces the refresh-read failure against the older binary.

These images do not establish physical-device frame pacing, haptic feel, or the live-account reconnection result.
