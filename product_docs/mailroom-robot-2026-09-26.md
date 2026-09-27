# Pull refresh: little mail robot

September 26, 2026. User-selected direction: the [supplied round-helmet robot](../design/motion/margin-studio/references/robot.png) bangs a long stick against the phone's top edge as if trying to unstick mail. The user removed the drawn ceiling and said mail should come from the cloud. The user explicitly required that **nothing comes out if there is no new mail**. This task covers the illustration and its state binding. Concurrent banner/read/network repairs are owned by the Main task.

## Drawing and performance

The September 27 revision follows the user's request for 16-bit styling, a recognizable wooden stick, a full head turn, feet/hip movement and a startled dodge when mail appears. The subsequent no-mail request adds two head-turn drawings, for fifteen pixel poses. These retain the reference's round helmet, navy face, pale eyes, blue ear caps, compact armor and pale waist belt. He starts facing the reader, turns through three-quarter and profile views to show the back of his helmet while knocking, then turns back. The follow-up fixes the disconnected head turn by drawing four complete body orientations: front, three-quarter, side and back. The rib cage narrows in profile; rear shoulder blades, spine, vents and hip plates replace the front chest panel and belt buckle. Arms overlap in depth and the boots pivot from toe caps to heels. His stance widens, knees bend and hips shift as he pushes into the harder strike. The slightly crooked stick has bark knots, a trimmed twig and a lighter cut end.

Only the arrival ending adds widened eyes, a sideways duck into the clear lane between the envelopes, a peek upward and a step back to rest. No-arrival refreshes lower the stick, give two small side-to-side "nope" head shakes and settle facing the reader, without falling mail. The quiet head shake now uses a small visor yaw inside the front-facing helmet with a slight shoulder/hip response; it no longer flips a three-quarter helmet across a stationary front-facing body. The quiet ending lasts 1.17 seconds, settles at 1 second and fits inside the existing 1.3-second player pause. Reduce Motion retains the static resting pose. There is no antenna, added mouth, drawn ceiling, trapped mail pile or falling debris. Contact glints stay at the phone edge. Four staggered envelopes enter from above the screen; their number is illustrative, not a count of messages.

The 144 × 98 artboard now contains a finer 288 × 196 pixel drawing with a 28-color palette, preserving its 288 × 196-point native footprint. Vector pixel contours and Rive Solo use 12 fps held keys. `build_mailroom.py` is the editable art source; the generated `scene.rml` remains editable in Rive's authoring pipeline. The supplied image is preserved unmodified as a reference. No new runtime, remote resource, sound or per-hit haptic is introduced.

The first contact is at 250 ms. A loop takes three seconds, with a pause after the double knock. The September 27 repair gives the checking presentation 1.6 seconds from renderer readiness, covering both knocks and recoil even when the network responds immediately. The arrival ending takes about 1.17 seconds; its native caption stays for 1.8 seconds and the mailroom player pauses after 1.3 seconds. All envelopes leave the drawing by 1.08 seconds. Fetched mail becomes usable immediately; only the nonblocking status presentation waits. Reduce Motion retains a shorter checking hold with static artwork.

A later September 27 native video review exposed a second issue: Metal can temporarily have no drawable while the pull overlay becomes an inset. Treating Rive's `noDrawable` callback as fatal replaced the whole sequence with static poses. The host now leaves that player alive for the next display tick; actual asset/device/renderer failures retain the native static fallback. A pixel-based native regression test reproduced the freeze with the old policy. The illustration still owns no controls or gestures.

## State contract

| Phase | Meaning | Art |
| --- | --- | --- |
| 0 | Actual pull distance, 0–100 | Face reader / turn and brace / profile wind-up at 33 and 70 |
| 1 | Existing refresh is running | Turn fully away, push from feet/hips into two knocks, turn back; repeats |
| 2 | Successful refresh with arrivals | Final hit, startled eyes, sideways duck, peek, return to rest |
| 3 | Existing refresh reports failure | Rest the stick; native Retry/dismiss actions |
| 4 | Successful refresh without arrivals | Lower stick, shake head "nope" twice, settle facing reader; all envelopes stay hidden |

`RefreshArrivalSnapshot` compares mailbox-qualified message identities before and after refresh, including waiting mail admitted by the explicit refresh. It never interprets a changed unread total as an arrival. The after-set contains eligible unread cards actually admitted to the session, so deselected or removed waiting mail does not trigger the ending. Refresh now admits newly fetched pending cards before it reports **N NEW EMAILS**; the quiet ending says **NO NEW EMAILS**. Any reported refresh failure takes precedence over arrival art. Background arrivals continue waiting for explicit bubble admission.

The drawing is 288 × 196 points at rest, with native status/actions over the empty lower part of the scene. The strip measures its actual screen origin and draws upward through the top safe area so the stick hits the physical screen edge. It reserves only the remaining content height. Dynamic Type can add room for native controls. During the pull the scene fits the available overscroll height; after release it opens to 2× its authored pixel size. The illustration cannot intercept touches. No feed/card gesture recognizer is added.

Reduce Motion and renderer failure use `MailroomStill.swift`, generated from the same pixel drawings with no Rive player. Existing visibility, app-background and route gates remain. Receipt, Reading and Closing art/timing are unchanged.

## September 27 revised-art verification

The body-turn correction keeps fifteen poses and coordinates their orientation across helmet, torso, shoulders, hips and boots. The bundled asset is **762,312 bytes**, SHA-256 `ae690c2f817d3df4a4efce5eaeea8711aea78c5cd9e1695a3202cf7ff89d08a7`. All 18 Rive checks passed on this correction; compilation reports zero errors or warnings. The generated native resting drawings also pick up the outward-facing boots. Receipt, Reading and Closing remain unchanged. The three focused native tests passed with zero failures in 33.023 seconds: fast arrivals, fast no-arrivals and continued pixel animation after a transient drawable miss (`/tmp/di-robot-body-native.xcresult`). Both outcomes and the generated static composition were visually inspected; the native gallery again passed 116 bindings and release of 16 hosts. Preceding records below refer to earlier artwork.

The no-mail follow-up expands the asset to fifteen poses and **779,221 bytes**, SHA-256 `bdfbb23e25af2868a5990875fabe298296772ea2552bd18a57301157fbf9cc55`. All **18 Rive checks passed again** on this asset. Its focused native fast-no-arrival test passed in 10.702 seconds with zero failures: `/tmp/di-robot-nope-native.xcresult`. The native outcome capture and the left/right head poses were inspected. The native static drawing is byte-for-byte unchanged; no native code, caption timing or other artboard changed. The no-mail desktop benchmark reports mean render 0.369 ms, p95 0.931 ms and zero reported WASM-page growth. The notes below retain the preceding head/body/surprise revision's broader native run.

- All **18 Rive rendering/structure checks passed** on the final thirteen-pose asset. Compile/inspection report zero errors or warnings. Receipt, Reading and Closing artboard XML matches the prior revision exactly.
- The **four focused native FeedGestures tests passed**, zero failures, in 43.393 seconds on iPhone 17 Pro / iOS 26.5: fast arrivals, fast no-arrivals, continued pixel animation after a transient drawable miss, and free scrolling while the illustration is active. Result: `/tmp/di-16bit-acting-native.xcresult`. This is the final head-turn/body/surprise revision; the earlier four-test run covered an intermediate drawing.
- Native arrival and no-arrival captures were visually inspected. The generated Reduce Motion composition was inspected in the native gallery, whose probe passed **116 bindings and release of 16 hosts**. The app's controls, gesture code, refresh data/arrival rules, hold durations and lifetime gates were not changed.
- The final Mailroom 240-frame headless benchmark reports mean render **0.410 ms**, p95 **0.928 ms**, and zero reported WASM-page growth. This is desktop evidence, not an iPhone performance claim. The bundled script-free asset is **691,018 bytes**, SHA-256 `ff47052b5b7c47f0beff099cf6ef90e82230a640880fffb7ab951d7d7ef94ea9`.
- [Updated portable preview and synthetic native evidence](../tools/motion-lab/native-qa/mailroom-16bit/README.md). Both outcome buttons were checked in the browser. The completed 16-bit/body-turn artwork was uploaded as **1.0 (2609271718)** at 17:20 Eastern on September 27. Apple processing and tester availability still require verification; see [the release record](native-release-2609271718.md). The prior release records describe earlier artwork.

## September 26 verification and handoff

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
