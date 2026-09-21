# Decision Inbox: motion and interaction system

Recorded September 19, 2026. The user first chose **audit and propose first**, expanded the scope to the whole app, then approved implementation with **“ok do all of it.”** The current implementation uses the shared calm, expressive native direction. See [implementation and verification](product_docs/interaction-implementation-2026-09-19.md); the earlier audits and concept alternatives remain design evidence.

## Start with the actual product

Read the current native contract in `product_docs/Email App.md`, the `product_docs/figma-audit-2026-09-19.md` distinction between current and archived designs, and `product_docs/zero-shot-philosophy.md`. The product prioritizes clarity, protection, control and a calm interface. The current implementation is SwiftUI in `apple/DecisionInbox`; the root Expo app is a separate, older implementation. README and CLAUDE still describe Expo and are insufficient to identify the shipping platform.

The older unsubscribe spec describes local hiding and future automation. The current native app performs external unsubscribe attempts. The new implementation stores durable unsubscribe receipts and offers a fresh browser-page handoff. It does not preserve a remote browser session, block senders locally, or monitor future mail. The [unsubscribe audit](product_docs/unsubscribe-experience-audit-2026-09-19.md) records the conflicts and decisions still open.

## September 20 illustrated implementation

The user explicitly requested completing the illustrated signature layer and TestFlight deployment. [Margin Studio](design/motion/margin-studio/README.md) adds three original production Rive artboards with app-state/gesture binding and native static fallback. SwiftUI still owns layout, controls, navigation and all copy. Rive Apple 6.24.0 is now a production dependency; the historical stack/tooling observations below describe the audit baseline. [Release 2609202100](product_docs/native-release-2609202100.md) tracks shipping evidence.

## Existing-stack audit

| Area | Observed state | Consequence |
|---|---|---|
| Current app | SwiftUI, UIKit integration, Xcode project, iOS deployment target 18.0, Swift language setting 5.0 | Animate native views with native APIs. Compiler and device OS versions are separate from these project settings. |
| Legacy client | Expo ~54.0.33, React 19.1.0, React Native 0.81.5, Expo Router ~6.0.23, React Native Web ~0.21.0 | Expo/Metro, not Next.js or Vite; iOS/Android/web targets. These are manifest versions/ranges. |
| Languages/package management | Swift native; TypeScript ~5.9.2 legacy client; JavaScript Node server; npm lockfiles | Do not confuse an npm install with an Xcode integration. |
| Styling/design | Native `Design/Tokens.swift`, reusable native components, monochrome Ink palette; DM Sans human content, DM Mono instrumentation | Preserve this visual vocabulary. Native system chrome owns navigation/sheet behavior. |
| Older styling | React Native StyleSheet, theme constants/hooks and custom components | A web-only component needs an explicit platform boundary. |
| Icons | Native SF Symbols; Expo vector icons/platform wrappers | Reuse the existing symbols; do not add an icon package for unsubscribe. |
| Animation libraries | SwiftUI `Move` tokens; legacy Reanimated ~4.1.1, Gesture Handler ~2.28.0, Worklets 0.5.1 | No Motion, GSAP, Rive, Spline or dotLottie production dependency was found in inspected manifests. |
| Canvas/3D | No production 3D/canvas runtime found in those manifests | No need identified for unsubscribe. |
| Accessibility | Native labels/actions, text styles, contrast handling and system navigation; unsubscribe tray uses a tap gesture and tight line limits | Presence of accessibility code does not prove VoiceOver, focus or large-text usability. |
| Reduced motion | `Move.resolved` replaces spatial motion with crossfade; several views read the native setting | Coverage is incomplete: some direct animations bypass the resolver. Audit call sites. |
| Haptics | Central native `Haptics.swift` vocabulary and independent preference; legacy Expo Haptics ~15.0.8 | No new haptic layer needed. Routine progress and ordinary success remain silent under the existing policy. |
| Sound | No dedicated product sound layer identified in the inspected design/app files | Do not add sound by default. Any future sound must be optional and earned by a specific interaction. |
| Loading | Existing placeholders, caret, pull-refresh states, cached display/reconciliation and unsubscribe step labels | Work on clarity and continuity; do not introduce simulated completion percentages. |
| Success | Receipts, saved-state transitions, feed endpoint and unsubscribe terminal state | Unsubscribe currently overstates some outcomes; truthful state precedes celebration. |
| Errors/empty states | Native recovery controls, unknown totals, verified empty/end states and retry patterns | An error is not an empty inbox; an unconfirmed unsubscribe is not success. |
| Navigation/layout | Native sheets, zoom transition, `Move.layout`, content/numeric transitions | Preserve platform behavior, interruption and scroll position. |
| Gestures | Pull refresh, reaction press/drag, receipt dismissal; dormant archive thresholds/settling remain in source | PostView deliberately does not attach its archive drag gesture; the new-post pill is not the dismissible receipt in the same file. Do not treat unused code as shipped behavior. |
| Performance | Large mail feeds, remote images, streamed updates and background reconciliation | Avoid animating every server event or relaying out the full feed. Profile real devices separately from a concept. |

## Tool setup and verification record

The authoritative installed versions, authentication boundaries, fixture results and full capability matrix are in [MOTION_TOOLING.md](MOTION_TOOLING.md). Keep that record current rather than treating installation as readiness.

- **Motion/Motion+/GSAP:** actually installed and executed in an isolated web lab. Motion spring/layout, premium AnimateNumber and GSAP timeline passed browser checks. Motion+ brings a transitive Motion 12 dependency alongside Motion 13; do not force a version override or add this diagnostic bundle to production.
- **Motion AI Kit:** local skill and hosted server registrations installed. Direct public documentation/example search now works. Premium hosted OAuth/metadata remains blocked; premium-source tools and MotionScore remain unverified even though package-token installation succeeds.
- **Rive:** official CLI authoring, compilation and state-driven rendering/input checks passed. No native runtime or desktop editor MCP was added. A `.riv` fixture is not a native app integration.
- **Xcode:** user-enabled official MCP responds to direct workspace reads and SDK Apple documentation reads. Native builds pass via explicit project CLI; preview/performance checks remain distinct.
- **Higgsfield / Higgsfield use After Effects:** existing Higgsfield access and deterministic editable timing/render study work. The refreshed direct AE tools passed native editable construction, 240 ms → 720 ms retiming, real text editing, source save and rendering. The fixture record retains the earlier script conflict and the later successful verification; always inspect current state before new edits.
- **Figma / Mobbin:** existing connections were exercised with real metadata/reference reads.
- **Spline / dotLottie:** no selected native interaction or asset justifies these runtime additions yet. Keep them conditional instead of installing overlapping production players.

The Motion+ package credential was used transiently for the isolated registry install, not saved to project files or production settings. Future clean installs need a process-scoped credential; see the token-free registry configuration and helper in the web lab. A future deployed web build would require separately approved CI secret setup.

## Runtime routing for future work

- **SwiftUI is the existing native implementation layer.** Use its gestures, animation, content transitions and system sheets for current app controls. The user's preferred Motion layer applies to actual web interfaces, not native view trees.
- **Motion is the default web interface-animation layer.** Keep web prototypes separate from native runtime claims. Never install both Motion and Framer Motion as duplicates.
- **Rive:** interactive illustrations, characters and authored state-driven visual metaphors. Require a real input/state mapping, mount/unmount cleanup and reduced-motion fallback.
- **GSAP:** web choreography requiring timelines or advanced SVG/motion-path control. Import only used plugins.
- **Spline:** selective 3D with a concrete user benefit, lazy loading, visibility gating, capability fallback and measured rendering cost.
- **dotLottie:** reusable authored assets when their behavior and file format fit. Do not assume every Lottie asset is interactive, or that modern players cannot be.
- **Higgsfield:** concepting, art direction and asset authoring. A rendered video is a reference/asset; it does not implement a gesture or network-state transition.
- **Higgsfield + After Effects:** editable motion production. Prove editable layers and timing before claiming integration.
- **CSS:** simple web effects when a runtime is unnecessary.

## Motion personality and existing tokens

Calm, precise and responsive. Movement explains what changed, where an object went, and what the user can do next. In a reading app, text must settle quickly. Delight comes from reliable control and continuity before spectacle.

Retain `apple/DecisionInbox/Design/Tokens.swift` as the native source of truth:

| Token | Current value | Meaning |
|---|---|---|
| `pressIn` / `pressOut` | 90 / 120 ms | Immediate press/release feedback. |
| `crisp` | Spring response .30, damping .86 | Small, decisive state changes. |
| `layout` | Spring response .38, damping .82 | Related layout changes; don't disturb active reading. |
| `commit` | Spring response .26, damping .86 | An actual gesture commitment. |
| `settle` | Spring response .30, damping 1.0 | Returning from an uncommitted gesture. |
| `exit` | 140 ms | Decisive dismissal. |
| `crossfade` | 160 ms | Reduced spatial motion and quiet content changes. |
| `reveal` | 240 ms | Bounded disclosure. |

Spring response/damping are not interchangeable with web stiffness/damping values. Match intent and observed behavior across platforms, not raw numbers. Existing `enter`, `sheet`, generic `stagger` and loading-delay tokens include unused/limited-use comments; do not activate them just because they exist. System-presented sheets retain system motion.

## Five levels, with a reason to move

1. **Functional:** connect input, state and result. This includes honest working/needs-you/outcome transitions.
2. **Tactile:** the surface tracks the finger; an interrupted dismissal returns naturally.
3. **Personality:** typography and restrained motion express the same precise voice. Status prose remains readable.
4. **Reward:** acknowledge a meaningful, supported result. Request transmission alone is not sender confirmation. The existing haptic policy deliberately avoids routine success buzzes.
5. **Signature candidate:** a rare, memorable interaction whose metaphor improves understanding. It requires explicit concept review; no automatic mascots, rockets or confetti.

The unsubscribe concept space was:

- **Restrained:** a compact status card and native action sheet. It minimizes interruption; the task still needs a retrievable record.
- **Expressive:** the card changes into a clear handoff surface when attention is needed, preserving sender identity and presenting one useful action. It clarifies agency but must not repeatedly interrupt reading.
- **Signature candidate:** a continuous, inspectable transfer from the agent's browser work into human control and back. Its value is continuity; its cost is a real session-lifecycle and outcome-verification system. A visual morph alone cannot provide it.

The implementation combines the restrained compact surface with an actionable expressive handoff. The preserved-session signature alternative remains a separate infrastructure project. The [whole-app audit](product_docs/whole-app-experience-audit-2026-09-19.md) contains twenty opportunities across the app, and the [concept directions](product_docs/motion-concept-directions-2026-09-19.md) develop six important moments at restrained, expressive and signature levels. The unsubscribe report contains additional focused detail.

## Design an interaction before animating it

For each significant interaction specify: trigger; known system state; available user action; expected duration; 10-second and 30-second waits; network loss; success evidence; failure/unknown result; cancellation cutoff; interruption; reversal; focus; reduced-motion/static behavior; and off-screen lifecycle.

For unsubscribe, keep **job state**, **evidence**, and **presentation visibility** independent. Close hides a surface. Cancel requires a supported way to prevent unsubmitted work. Undo requires a real inverse operation. A human opening or returning from a page is not proof of completion. Batch progress must distinguish confirmed, needs-you, failed and unknown outcomes rather than filling them all as success.

Generated copy follows the zero-shot policy. Deterministic state/action identifiers drive controls; narration describes actual context. Never infer button destinations from a generated sentence. Synthetic copy in a review concept is not a new production prompt template.

## Accessibility and performance acceptance

Spatial motion must have a reduced-motion counterpart that preserves state and actions. Test VoiceOver semantics, focus return, keyboard/Switch Control, large text, long names, contrast and 44-point effective targets. No critical action is available only through a swipe. Do not repeatedly announce every streamed status line.

Use existing semantic haptics only at justified transitions; don't add a success buzz at request acceptance. Sound stays absent unless explicitly designed as optional. Stop off-screen loops, cancel animation tasks on unmount, and avoid large blur/filter or canvas effects for ordinary status UI.

Native performance requires native profiling and physical-device checks. Web studies can use browser profiling/MotionScore when connected. Test a long inbox, multiple simultaneous requests, slow responses, mixed outcomes, navigation away/back and repeated interruption. No animation may delay the next action or simulate progress the backend does not know.

## Source and verification references

- [Motion React installation](https://motion.dev/docs/react-installation), [HTML/SVG component model](https://motion.dev/docs/react-motion-component).
- [Motion+ registry installation](https://motion.dev/docs/motion-plus-installation), [AI Kit installation](https://motion.dev/docs/ai-kit-install), [published installer](https://github.com/motiondivision/ai-kit).
- [Rive Apple runtime](https://rive.app/docs/runtimes/apple/apple), [React Native runtime](https://rive.app/docs/runtimes/react-native/react-native), [official desktop MCP](https://rive.app/docs/editor/ai/mcp). Editor/MCP support is distinct from runtime installation.
- [GSAP installation](https://gsap.com/docs/v3/Installation/), [Spline Apple export](https://docs.spline.design/exporting-your-scene/apple-platform/i-os-app-generation), [dotLottie runtimes](https://developers.lottiefiles.com/docs/).
- [Higgsfield After Effects integration](https://higgsfield.ai/plugins/after-effects), [AI Motion Designer](https://higgsfield.ai/ai-motion-designer).

The initial audit changed no product behavior. The subsequent approved implementation changes native interactions and supporting task/data lifecycles, without adding a production animation runtime. The unsubscribe review concept uses synthetic sender content. Separate retained creative fixtures provide real Motion+, Rive and authored-motion checks; their success is not a native product-feature or device-performance pass.
