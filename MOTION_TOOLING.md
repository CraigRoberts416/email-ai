# Motion and creative tooling

Updated September 20, 2026. This is the setup and verification record for the user's motion-and-delight brief. The current product is SwiftUI; creative fixtures are deliberately isolated under `tools/motion-lab`. They are retained as reproducible checks and editable references, not shipped product features.

Read the [whole-app motion audit](/Users/craigroberts/email-ai/product_docs/whole-app-experience-audit-2026-09-19.md) for opportunities, and [motion system](/Users/craigroberts/email-ai/MOTION_AND_DELIGHT_SYSTEM.md) for future-agent rules. No production native/Expo dependency or production secret was changed by this setup.

## Installed, connected and tested are different claims

**Installed** means the executable/package is present. **Connected** means its service responds. **Tested** names the operation actually exercised. **Production-ready** would additionally require integration into the selected product feature, accessibility, lifecycle and device/performance checks. A web animation proves web behavior; it does not animate a SwiftUI view.

| Tool | Needed? | Installed / configuration | Purpose | Account / cost | Result / boundary |
|---|---|---|---|---|---|
| SwiftUI and existing Move/Haptics | Yes, native interface | Existing product; Xcode 26.6 build 17F113 | Native controls, gestures, spatial continuity | Included in existing Apple tooling | Native interactions implemented; Simulator build and model/service checks passed; see implementation record |
| Xcode MCP | Useful now | Project `.codex/config.toml`; `/usr/bin/xcrun mcpbridge`; user enabled external agents | Native diagnostics, previews, builds, Apple documentation | No new paid service | 21-tool handshake and Apple documentation reads passed via SDK; direct `XcodeListWindows` also passed September 20 |
| Motion | Useful for web studies | Isolated lab 13.4.0; React/DOM 19.3.0; Vite 8.3.0 | Springs, layout, ordinary web interaction | Open source | Spring execution/import and production bundle passed; browser checks recorded in lab README |
| Motion+ | Useful for premium studies | `motion-plus` alias to `@motionplus/core` 2.12.0; private registry auth succeeded | Premium components and patterns | Existing user entitlement | Package import/execution passed; separate from hosted MCP authentication |
| Motion AI Kit | Useful guidance | Official `motion-ai` 14.1.0 installed `.agents/skills/motion` and project HTTP servers | Best practices, docs/examples, transition/performance tools when reachable | Existing Motion+ account for premium service | Local skill and direct public documentation/example search work. Premium login remains blocked; no MotionScore/premium-source MCP pass |
| Rive CLI | Useful for authored stateful illustration | Official CLI 1.1.0 at `/Users/craigroberts/.rive/bin/rive` | Editable RML, state machines, `.riv` compilation, headless interaction/render checks | Local creation/checks required no sign-in or purchase | Ten fixture scenarios pass; idle/active/success, numeric input, pointer/semantic actions and reduced motion verified |
| Rive native runtime / desktop MCP | Conditional on chosen asset | Not added to app; desktop server not registered | SwiftUI asset playback / editor control | Editor/publishing entitlement separate | CLI authoring is available. Native mounting, memory lifecycle and device binding remain untested |
| GSAP | Useful for web choreography studies | Isolated lab 3.15.0 | Timeline, SVG and motion-path study | Official npm package; no purchase made | Timeline checks in lab; no native import or unnecessary production plugin |
| Spline | No concrete 3D use identified | Not installed | Selective dimensional experience | Native export entitlement may require paid plan | Deferred under the brief's “only if useful” rule; no scene test or account change claimed |
| dotLottie / Lottie | Conditional on a selected reusable asset | Not installed | Authored lightweight animation assets | Runtime/asset entitlement depends on selection | Deferred: no chosen native asset requires another playback dependency; no runtime test claimed |
| Higgsfield | Useful creative production | Existing connected account and CLI; deterministic Higgsedit in connector sandbox | Editable motion studies and art direction | Existing account; no purchase or generative-credit job in these smoke checks | Account and sandbox access verified; fixture evidence recorded under `tools/motion-lab/higgsfield` |
| Higgsfield use After Effects | Useful editable professional motion | Official `fnf-after-effects-mcp` 0.1.1 installed globally; server registered by official `install-codex`; Adobe AE 25.6.0 already installed | Editable compositions, layers and timing | Existing Adobe install; no purchase | Direct project/catalog reads, native editable construction, timing change, content edit, save and 120 frame renders passed September 20; earlier script conflict did not recur |
| Figma | Useful existing design context | Existing connector | Current design/token references | Existing connection | Real metadata read succeeded on one connected account; two other stale connections failed and were not needed |
| Mobbin | Useful existing interaction references | Existing connector | Inspect comparable real flows | Existing access | Real iOS email-send flow search returned screens; reference is inspiration, not a product contract |

The September 20 session refresh exposed direct Motion, Xcode and After Effects tools. Motion documentation search, Xcode workspace discovery and the AE fixture were exercised through those tools. Xcode reported unrelated open workspaces, which were left untouched; the product build used its explicit project path through `xcodebuild`. Future creative work must still inspect current AE project state before editing.

## Working configurations and authentication

### Motion and Motion+

The [web lab](/Users/craigroberts/email-ai/tools/motion-lab/web) has its own manifest/lockfile. Its `.npmrc` contains only an environment reference:

```ini
@motionplus:registry=https://api.motion.dev/npm/
//api.motion.dev/npm/:_authToken=${MOTION_TOKEN}
```

The supplied token was entered through hidden stdin and passed only to the install child's environment. Temporary npm cache/log locations were removed; no token was written to a project secret file. The install helper is retained for repeatable hidden-input installation. A later clean install needs the token again; ordinary local use of the installed packages does not. No production or CI secret was configured. If a future deployed web build installs Motion+, that build job would need a separately approved `MOTION_TOKEN` secret.

**Compatibility:** Motion+ 2.12.0 currently depends on Motion 12.x, resolving 12.43.0 underneath the lab's directly installed Motion 13.4.0. This transitive duplication is an upstream compatibility observation, not an intentional second top-level animation framework. No forced override was applied. The complete lab bundle measured approximately 578 kB JavaScript / 189 kB gzip and produced Vite dependency-directive warnings; it is a diagnostic page, not a production bundle budget. Future web adoption needs a compatible version decision and bundle measurement for only the components actually used.

Hosted servers are `https://mcp.motion.dev` and `https://mcp.motion.dev/plus`. `codex mcp login motion-plus` failed with **Protected resource metadata missing required resource field**, including a fresh September 20 retry. A read-only metadata probe then returned HTTP 403 / Cloudflare 1010. This does not invalidate the package token: private package installation succeeded. Direct `search_motion_docs` now succeeds for React layout/spring/reduced-motion guidance and public example metadata. Premium-source access, MotionScore, saved/shared transitions and transition editing remain unverified and unavailable in the refreshed tool catalog. Registry package authentication and public documentation access do not establish premium MCP authentication.

### Rive

The official installer verified its download and installed CLI 1.1.0. Local `doctor` passed the runtime checks; account authentication is absent and unnecessary for the local fixture. Publishing, signing or collaboration may need separate account access and are not claimed.

The [Rive fixture README](/Users/craigroberts/email-ai/tools/motion-lab/rive/README.md) documents exact build/render/test commands. `scene.rml` is editable source; `verify.py` drives state inputs and checks transitions. The unsigned compiled `.riv` is 60,181 bytes. Ten rendered scenarios include code-controlled state changes, pointer and semantic actions, interrupted/rapid transitions and reduced motion. This proves a real state-driven authoring workflow, not an embedded looping movie.

The official desktop MCP expects a running editor at `http://127.0.0.1:9791/mcp`. No editor was installed and no unavailable server was registered merely to fill a setup checklist. Adding the Apple runtime to production awaits a selected illustration and native lifecycle/performance review.

### Xcode

The user enabled **Settings → Intelligence → Allow external agents to use Xcode tools**. Project registration runs `/usr/bin/xcrun mcpbridge`. The external SDK successfully listed 21 tools and retrieved current Apple SwiftUI accessibility/animation documentation. Open workspace discovery also succeeded, including a direct callable-tool check on September 20. The native app builds with its exact project path via CLI; no build, preview or diagnostic was run against unrelated open projects.

Existing Instruments includes SwiftUI, Animation Hitches, Time Profiler, Allocations/Leaks and app-launch profiling; no extra monitoring service is needed to begin native measurement. Two attempts to attach Animation Hitches to the isolated Simulator app failed with “Cannot find process for provided pid,” although the app remained running. No usable trace or native performance pass is claimed.

### Higgsfield and After Effects

The existing Higgsfield account responded to a real account read. The connector's deterministic `higgsedit` renderer is usable (`@fable/headless` 0.14.0, Node 22.22.1, ffmpeg 5.1.9). Use the motion-craft/video-editing skills for authored studies. Reserve durable media outputs before rendering in an ephemeral connector sandbox. No arbitrary cinematic generation is needed to test product motion.

Higgsfield's official installation and verification preset was read before installing `fnf-after-effects-mcp` 0.1.1. Its doctor passed package/skill integrity and detected Adobe After Effects 2025. Official `install-codex` registered `higgsfield-use-after-effects` in the global Codex configuration with absolute executable/module paths. Live `ae_project_info` returned a clean empty project; `ae_catalog` returned 197 operations. The first attempt timed out during AE startup; the retry after the app had opened succeeded. Every future creative operation must first inspect current project state and preserve existing work.

The bridge supports editable layers and keyframes. Use its actual catalog schemas and bounded operations, keep arbitrary evaluation disabled, and save creative fixtures separately from user projects. September 19 reads encountered a second-script conflict; no override or reset was used. On September 20 a fresh direct read succeeded with a clean empty project. After saving a separate backup, the native five-layer receipt fixture, 240 ms → 720 ms timing edit and separate real text edit succeeded. Fonts were present, the editable `.aep` saved, and all 120 native frames rendered successfully. The [AE fixture README](/Users/craigroberts/email-ai/tools/motion-lab/after-effects/README.md) records the source, visual/timing checks and preview. This is an isolated authoring proof, not a new app dependency. Higgsedit also independently passed editable timing and render verification.

## Capability verification matrix

“Study” means verified only in the isolated fixture, never production-ready by implication. The approved native implementation now builds and passes model/service checks. See [implementation verification](product_docs/interaction-implementation-2026-09-19.md) for actual UI/device coverage.

| Capability | Tool | Installed | Connected | Tested | Production-ready | Notes |
|---|---|---|---|---|---|---|
| UI springs | SwiftUI / Motion | Yes / lab | Local | Motion spring study; native build and source review | Native changes implemented; device motion/performance pending | Different parameter systems; match intent, not raw numbers |
| Layout animation | SwiftUI / Motion | Yes / lab | Local | Web fixture; native changes compile | Native build; runtime coverage in implementation record | Preserve identity and reading position |
| Gesture animation | SwiftUI / Rive | Native / CLI | Local | Rive pointer fixture; native tap/reaction/Activity checks | Native build; runtime coverage in implementation record | Dormant archive gesture removed; visible filing controls remain |
| Drag physics | SwiftUI / Motion | Yes / lab | Local | Not comprehensively tested | No | Release velocity, cancellation and nested scrolling require runtime checks |
| Shared-element transitions | Native navigation / Motion | Yes / lab | Local | Not separately verified | No | Avoid claiming a layout sample proves all shared-element cases |
| Scroll animation | SwiftUI / Motion | Yes / lab | Local | Source audit only for product | No | No new scrolling choreography shipped |
| Interactive state machines | Rive | CLI yes | Local | Ten state/input/render scenarios | Study only | Native mount/unmount and app-state binding pending |
| Character/illustration animation | Rive / Higgsfield | Authoring available | Yes | Simple abstract fixture | No character approved | Manual art direction still required |
| SVG choreography | GSAP | Lab | Local | Package files present; plugins not imported/tested | Study only | No production plugin bundle |
| Advanced timelines | GSAP / Higgsedit / AE | Yes | Yes | Bounded timeline studies | Study only | Complex production sequences need separate validation |
| Motion paths | GSAP | Lab | Local | Package file present; no dedicated path study | No | Capability not confused with a completed feature |
| Lightweight animation assets | Rive; dotLottie deferred | Rive CLI | Local | `.riv` compilation/render | Study only | dotLottie was not installed or tested |
| Interactive 3D | Spline | No | No | No | No | No user-value case selected |
| Motion concept creation | Higgsfield / Rive | Yes | Yes | Synthetic authored study | Reference only | A rendered study is not runtime interaction |
| Editable professional graphics | Higgsfield use After Effects / Higgsedit | Yes | Yes | AE native construction, retiming, text edit, save and render; Higgsedit timing/render | Study only | Editable AE source and native previews retained |
| Reduced motion | SwiftUI / web / Rive | Yes | Local | Rive and web static controls passed; native source audit | Coverage incomplete | Changed native settings use reduced-motion resolution; full runtime matrix remains pending |
| Animation performance audit | Instruments / MotionScore | Instruments yes | Local / premium MCP blocked | Instruments attach failed; no native trace or MotionScore pass | No performance certification | Tools available and tests completed are separate |
| AI documentation/examples | Apple docs, Motion skill/search, Figma/Mobbin | Yes | Apple/Motion/design tools pass | Real reads/searches | Useful now | Hosted Motion premium examples remain blocked |

## What this enables, and what still needs judgment

- **Newly exercised:** premium web components, reproducible UI/timeline studies, editable Rive state machines driven by code, Apple documentation through Xcode, and a live local After Effects bridge. Higgsfield's authored fixture adds editable timing studies rather than an unrelated generated clip.
- **Manual creative judgment remains:** which metaphor fits the product, which moments deserve emphasis, illustration/character art, scene composition, timing critique and the decision to ship a concept. A tool can execute a direction without deciding whether that direction belongs in this app.
- **Most direct coding support:** Xcode/Apple documentation and native Instruments; the Motion skill and lab support web studies. Figma and Mobbin supply design/reference context.
- **Creative support:** Rive for interactive authored behavior; Higgsedit/After Effects for editable temporal studies. Spline becomes relevant only if a useful 3D concept emerges; dotLottie only for a selected asset/runtime need.
- **No paid upgrade required for the verified work.** No subscription, trial, credits or infrastructure was purchased. A desktop Rive MCP or Spline native export may add account/plan requirements later, but neither unlocks a missing requirement in the current native proposals by itself.
- **Risk boundaries:** Motion+ version duplication and the web lab's bundle size require a future web compatibility decision. Native feed performance, Rive native memory/lifecycle, large text, VoiceOver, cancellation and focus remain product validation work. No setup credential was stored in source or production settings; the install helper checked the actual credential, and final review scanned authored source/config plus registry URLs without printing values.

## Official sources and fixture evidence

- [Motion installation](https://motion.dev/docs/react-installation), [Motion+ installation](https://motion.dev/docs/motion-plus-installation), [AI Kit](https://motion.dev/docs/ai-kit-install).
- [GSAP installation](https://gsap.com/docs/v3/Installation/).
- [Rive CLI](https://rive.app/docs/cli/overview), [CLI getting started](https://rive.app/docs/cli/getting-started), [Apple runtime](https://rive.app/docs/runtimes/apple/apple), [desktop MCP](https://rive.app/docs/editor/ai/mcp).
- [Apple external-agent access](https://developer.apple.com/documentation/xcode/giving-external-agents-access-to-xcode).
- [Official Higgsfield After Effects bridge](https://github.com/higgsfield-ai/fnf-local-pluging-bridge-mcp), [After Effects integration](https://higgsfield.ai/plugins/after-effects).
- [Spline Apple export](https://docs.spline.design/exporting-your-scene/apple-platform/i-os-app-generation), [LottieFiles runtime documentation](https://developers.lottiefiles.com/docs/).
- [Mobbin iOS send-flow reference](https://mobbin.com/flows/bebefa25-db23-4a6a-8567-46ebbddfdc9d).

## September 20: production illustrated layer

The native runtime is no longer deferred: Rive Apple **6.24.0** is pinned through Swift Package Manager. Three original script-free artboards ship in `margin-studio.riv` (16,675 bytes), distinct from the tooling fixture. Real iOS loading, numeric/boolean bindings, interrupted state changes and configuration lifetime checks pass. Native static drawing handles Reduce Motion and failure. See [Margin Studio](design/motion/margin-studio/README.md) and [release 2609202100](product_docs/native-release-2609202100.md). The earlier “study only” entries are historical setup results.
