# Local Rive verification — 2026-09-19

This is an isolated synthetic motion fixture, not production app code or an approved unsubscribe design. It answers a tooling question: can editable, code-authored Rive state machines compile, react to inputs, render, and be checked locally without signing in? With Rive CLI 1.1.0, these checks pass.

The mental model is a small dashboard light. The app supplies the truth; the asset displays it. Selecting Success here supplies test data. It does not infer that an unsubscribe succeeded.

## Inputs and files

| View-model input | Meaning | Display |
| --- | --- | --- |
| `phase=0` | Idle | Ready dot, “Ready to check” |
| `phase=1` | Active | Pulsing caret, “Checking” |
| `phase=2` | Synthetic success | Check mark, “Check complete” |
| `reduceMotion=true` | Suppress ongoing motion | Active caret becomes static; entering/leaving that state has no blend |

- `scene.rml`: editable artboard, four animation states, view-model conditions, pointer and semantic listeners.
- `rive.yaml`: local project configuration.
- `verify.py`: repeatable checks using Python standard library only.
- `assets/DM-Sans-Regular.ttf`: copy of this repository’s `apple/DecisionInbox/Resources/Fonts/DMSans_400Regular.ttf`.
- `assets/OFL.txt`: DM Sans copyright notice and SIL Open Font License 1.1, copied from the locally installed `@expo-google-fonts/dm-sans/LICENSE_FONT`. The package's Regular font and this fixture font have identical SHA-256 hashes.
- `AGENTS.md` and `CLAUDE.md`: generated CLI guidance, read before authoring.
- `build/task-signal.riv`: locally built unsigned Rive asset, 60,181 bytes on this run.
- `build/verification.json`: actual command list, compiler/inspection results, input readbacks and PNG image-data hashes.
- `build/*.png` and `build/*.json`: rendered frames, view-model readbacks, semantics.

The CLI-generated local `.gitignore` excludes `build/`. Running the checks recreates evidence. No root repository ignore rules were changed.

## Reproduce

From the repository root:

```sh
python3 tools/motion-lab/rive/verify.py
```

The executable defaults to `~/.rive/bin/rive`; set `RIVE_BIN` to use another location. The harness verifies compilation, inspects the resolved structure, renders ten scenarios, and checks their data and image output. It raises an assertion or subprocess failure on a mismatch.

Individual commands:

```sh
~/.rive/bin/rive tools/motion-lab/rive --verify --format=json
~/.rive/bin/rive inspect tools/motion-lab/rive --summary
~/.rive/bin/rive tools/motion-lab/rive --screenshot=tools/motion-lab/rive/build/active.png --data=phase=1 --advance=30
~/.rive/bin/rive tools/motion-lab/rive --screenshot=tools/motion-lab/rive/build/reduced-motion.png --data=phase=1 --data=reduceMotion=true --advance=30
~/.rive/bin/rive tools/motion-lab/rive --data=phase=1 --bench=120
```

## Verified results

| Check | Observed result |
| --- | --- |
| CLI version | `rive 1.1.0` |
| Compile and resolved scene | Zero errors, zero warnings, zero inspection problems; one state machine, four animation states |
| Code-controlled `phase` | Readback reports 0, 1, 2; three distinct rendered outputs |
| Active motion | Captures at frames 30 and 60 have different image data |
| Reduced Motion | Active captures at frames 30 and 90 have identical image data |
| Pointer activation | Clicking Active changes `phase` to 1 |
| Semantic activation | `tap@Success` changes `phase` to 2 and produces the same settled image as a code-supplied success input |
| Interrupted transition | Active followed three frames later by Idle settles exactly to the Idle image |
| Rapid state change | Active followed three frames later by Success settles exactly to the Success image |
| Semantic controls | Idle, Active, Success expose button roles and 116×44 bounds |
| Visual inspection | Idle, active, success, reduced-motion, interrupted and rapid-success images inspected; labels and controls are legible without clipping at 440×252 |

The image comparison hashes decompressed PNG image data and the image header, excluding incidental metadata. These are focused smoke checks, not a visual regression baseline.

A separate 120-frame local active-state benchmark reported advance mean 0.003 ms / p95 0.012 ms; render mean 0.275 ms / p95 0.543 ms; zero reported WASM-page growth. Those are this tiny headless desktop fixture’s results, not iPhone performance evidence.

## What this does not verify

No login, paid action, cloud upload, publish, browser preview, native application edit, or mailbox action was performed. CLI local commands do not require a session, per its bundled help and docs. An unsigned local `.riv` was produced; signing, app-runtime loading and release distribution were not exercised.

The fixture has fixed geometry and test buttons. It does not implement Dynamic Type, localization, current-status announcements, automatic OS Reduced Motion wiring, remote state persistence, real progress, failure, cancellation, or a human-action handoff. Its rapid-return test demonstrates presentation state interruption, not cancellation of a server action. The exported semantic tree covers the three test controls; host accessibility integration needs its own design and runtime verification.

No `--test` success is claimed: there are no Rive Tests scripts. The Python harness checks actual compiled output, input readbacks, rendering and semantic actions.

Authoring used CLI 1.1.0’s bundled `rive docs` and `rive schema`, particularly format, state machines, data, drawing, text, easing and semantics. Primary reference: [Rive CLI getting started](https://rive.app/docs/cli/getting-started). Installed documentation is available with `rive docs --path`.
