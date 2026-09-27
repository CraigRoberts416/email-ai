# Pull refresh: little mail robot

September 26, 2026. User-selected direction: the [supplied round-helmet robot](../design/motion/margin-studio/references/robot.png) bangs a long stick against the phone's top edge as if trying to unstick mail. The user removed the drawn ceiling and said mail should come from the cloud. The user explicitly required that **nothing comes out if there is no new mail**. This task covers the illustration and its state binding. Concurrent banner/read/network repairs are owned by the Main task.

## Drawing and performance

Ten pixel poses preserve the reference's large round helmet, navy face, two pale eyes, blue ear caps, compact armored body and pale waist belt. Planted feet, anticipation, contact, recoil and a harder second knock give the robot effort. There is no antenna, added mouth, drawn ceiling, trapped mail pile or falling debris. A few contact glints stay at the phone edge. Four staggered envelopes enter from above the screen and tumble toward the feed only in the arrival ending. Their number is illustrative, not a count of messages.

The 144 × 98 scene uses vector rectangles and Rive Solo, with 12 fps held keys. `build_mailroom.py` is the editable art source; the generated `scene.rml` remains editable in Rive's authoring pipeline. The supplied image is preserved unmodified as a reference. No new runtime, remote resource, sound or per-hit haptic is introduced.

The first contact is at 250 ms. A loop takes three seconds, with a pause after the double knock. The September 27 repair gives the checking presentation 1.6 seconds from renderer readiness, covering both knocks and recoil even when the network responds immediately. The arrival ending takes about 1.17 seconds; its native caption stays for 1.8 seconds and the mailroom player pauses after 1.3 seconds. All envelopes leave the drawing by 1.08 seconds. Fetched mail becomes usable immediately; only the nonblocking status presentation waits. Reduce Motion retains a shorter checking hold with static artwork.

## State contract

| Phase | Meaning | Art |
| --- | --- | --- |
| 0 | Actual pull distance, 0–100 | Watch / brace / wind up at 33 and 70 |
| 1 | Existing refresh is running | Two knocks, then rest; repeats |
| 2 | Successful refresh with arrivals | Final hit, falling envelopes, pleased robot |
| 3 | Existing refresh reports failure | Rest the stick; native Retry/dismiss actions |
| 4 | Successful refresh without arrivals | Lower the stick; all envelopes stay hidden |

`RefreshArrivalSnapshot` compares mailbox-qualified message identities before and after refresh, including waiting mail admitted by the explicit refresh. It never interprets a changed unread total as an arrival. The after-set contains eligible unread cards actually admitted to the session, so deselected or removed waiting mail does not trigger the ending. Refresh now admits newly fetched pending cards before it reports **N NEW EMAILS**; the quiet ending says **NO NEW EMAILS**. Any reported refresh failure takes precedence over arrival art. Background arrivals continue waiting for explicit bubble admission.

The drawing is 288 × 196 points at rest, with native status/actions over the empty lower part of the scene. The strip measures its actual screen origin and draws upward through the top safe area so the stick hits the physical screen edge. It reserves only the remaining content height. Dynamic Type can add room for native controls. During the pull the scene fits the available overscroll height; after release it opens to 2× its authored pixel size. The illustration cannot intercept touches. No feed/card gesture recognizer is added.

Reduce Motion and renderer failure use `MailroomStill.swift`, generated from the same pixel drawings with no Rive player. Existing visibility, app-background and route gates remain. Receipt, Reading and Closing art/timing are unchanged.

## Verification and handoff

- Debug iOS Simulator compilation passed. All four original `FeedGestures` native touch tests passed on iOS 26.5, including card-origin scrolling during active robot refresh, return to top, thread return and tab return. Result bundle: `/tmp/di-mailroom-edge-gestures.xcresult`.
- Seven arrival-identity checks passed: unchanged mail, removed/read mail, empty response, equal total with replacement identity, mailbox-qualified IDs, waiting arrivals, and removed/deselected waiting mail.
- Rive compile/inspection and 18 rendering/structure checks passed, including preserved original artboards, robot pull/working/quiet states, distinct endings and zero falling-envelope opacity outside the arrival animation.
- Actual Rive captures are available in the [interactive review](../tools/motion-lab/native-qa/mailroom/preview.html). Buttons were checked in the in-app browser.
- The native gallery passed **116 data-binding checks and release of 16 temporary Rive configurations**. The actual feed was visually inspected and recorded with contact at the phone's physical top edge, beside the Dynamic Island. The native static/no-arrivals composition was also inspected. The host still owns all status text and actions.
- The robot's headless 240-frame benchmark reported mean render 0.275 ms, p95 0.548 ms and no WASM-page growth. This is desktop evidence, not an iPhone battery/frame-pacing measurement. The asset is 203,169 bytes; SHA-256 `144d63f650f48438b469872c2efe82eaf406d1e4f58846fdab98543d563c1e4f`.
- An initial Simulator attempt stalled before launch. The Main task recovered CoreSimulator; running just the iOS 26.5 QA runtime then allowed installation and the successful suite above. The interrupted attempt is not counted as a test pass. All art/gesture checks use synthetic mail; no authenticated mailbox was used.

The Main task subsequently combined this artwork with the recovery fixes, passed all seven native touch checks, and uploaded **1.0 (2609261241)** at 12:47 EDT on September 26. See the [combined release record](native-release-2609261241.md) for archive validation, upload evidence and the distinction between upload and verified tester availability.

Reproduce the identity checks:

```sh
swiftc apple/DecisionInbox/Model/RefreshArrivalSnapshot.swift apple/tests/RefreshArrivalTests.swift -o /tmp/di-refresh-arrivals
/tmp/di-refresh-arrivals
```

Reproduce the art and preview:

```sh
python3 design/motion/margin-studio/build_art.py
python3 design/motion/margin-studio/verify.py
cp design/motion/margin-studio/build/margin-studio.riv apple/DecisionInbox/Resources/Motion/margin-studio.riv
python3 design/motion/margin-studio/render_mailroom_preview.py
```
