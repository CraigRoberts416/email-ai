# 16-bit robot acting — September 27, 2026

The user requested finer 16-bit styling, a wooden stick, a full front-to-back-to-front head turn, feet/hip movement and surprise when mail falls. These retained artifacts use synthetic inputs only.

- `preview.html`: self-contained review of actual Rive frames, with working, arrivals and no-arrivals controls. The endings loop here for review; the app plays an ending once.
- `working.gif`: widened stance, hip/knee loading, rear-toe push, full helmet turn and return.
- `arrivals.gif`: wide-eyed startle, sideways duck, upward peek and step back. Only phase 2 selects falling envelopes and the surprise sequence.
- `empty.gif`: calm return with no mail.
- `native-arrivals.png`, `native-no-mail.png`: actual native FeedGestures outcome captures.
- `native-reduced.png`: generated native static composition and the runtime probe's 116 passing bindings / 16 released hosts.
- `rive-verification.json`: 18 passing art/state checks.
- `robot-benchmark.txt`: final Mailroom desktop benchmark; not physical-device performance evidence.

Final native regression run: `/tmp/di-16bit-acting-native.xcresult`; four tests passed, no failures, 43.393 seconds. No feed gestures, provider operations or outcome logic changed. Asset SHA-256: `ff47052b5b7c47f0beff099cf6ef90e82230a640880fffb7ab951d7d7ef94ea9` (691,018 bytes).

This is the updated artwork/verification set, not a new TestFlight release.
