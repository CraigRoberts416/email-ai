# 16-bit robot acting — September 27, 2026

The user requested finer 16-bit styling, a wooden stick, a full front-to-back-to-front head turn, feet/hip movement and surprise when mail falls. The subsequent no-mail request adds two small "nope" head shakes. These retained artifacts use synthetic inputs only.

- `preview.html`: self-contained review of actual Rive frames, with working, arrivals and no-arrivals controls. The endings loop here for review; the app plays an ending once.
- `working.gif`: widened stance, hip/knee loading, rear-toe push, full helmet turn and return.
- `arrivals.gif`: wide-eyed startle, sideways duck, upward peek and step back. Only phase 2 selects falling envelopes and the surprise sequence.
- `empty.gif`: lower stick, shake head left/right twice, then settle; no mail falls.
- `native-arrivals.png`, `native-no-mail.png`: actual native FeedGestures outcome captures.
- `native-reduced.png`: generated native static composition and the runtime probe's 116 passing bindings / 16 released hosts.
- `native-nope.png`: actual native no-mail follow-up capture during the head shake.
- `rive-verification.json`: 18 passing art/state checks.
- `robot-benchmark.txt`: final Mailroom desktop benchmark; not physical-device performance evidence.
- `no-mail-benchmark.txt`: no-mail follow-up desktop benchmark; not physical-device performance evidence.

Head/body/surprise native regression run: `/tmp/di-16bit-acting-native.xcresult`; four tests passed, no failures, 43.393 seconds. The later head-shake revision passed the focused fast-no-arrival native test, zero failures, 10.702 seconds: `/tmp/di-robot-nope-native.xcresult`. No feed gestures, provider operations or outcome logic changed. Current fifteen-pose asset SHA-256: `bdfbb23e25af2868a5990875fabe298296772ea2552bd18a57301157fbf9cc55` (779,221 bytes). The static drawing and other three artboards are unchanged.

This is the updated artwork/verification set, not a new TestFlight release.
