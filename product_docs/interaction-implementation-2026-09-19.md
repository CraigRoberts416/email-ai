# App interaction implementation

Updated September 20, 2026. The user approved the whole-app motion-and-delight audit with “ok do all of it,” then asked to keep going. Work begins from commit `9c31467` on `codex/app-interaction-craft`. The audits remain historical evidence; this record tracks implementation and verification.

The guiding idea is continuity: the same message, account and task remain recognizable while the interface explains what happened and what can happen next. The implementation uses the shared calm, expressive native direction. Mutually exclusive signature alternatives are not combined into a single control. SwiftUI remains the product animation layer; no extra production animation runtime was added.

## Scope clarification — September 20

The twenty rows below describe the native interaction, state and recovery implementation. They do **not** mean that every creative direction or every capability in the original motion brief was delivered. The original completion wording was too broad for that larger brief.

There are no production Rive assets or Rive runtime in the app. The Rive state-machine fixture, Motion/Motion+ web lab and After Effects receipt study verify authoring tools separately from shipping features. Illustrated loaders/empty states, a Rive freshness-receipt signature and other ambitious illustrated alternatives remain unbuilt. The app currently uses SwiftUI for the selected margin, control, navigation and typography motion. Premium Motion MCP access and the unverified device checks remain open as recorded below.

The user subsequently requested TestFlight distribution of the implemented work. Build 2609202041 combines this implementation with the later feed reliability and People badge fixes; its distribution result is tracked in `native-release-2609202041.md`.

## Coverage of the twenty opportunities

| Audited moment | Implemented result | Boundary / tradeoff |
|---|---|---|
| Onboarding source → interpretation | Tappable synthetic source/meaning comparison; selected state, reduced-motion transition and stacked maximum-text controls | An honest demonstration before personalization |
| Provider → account identity | Back, Cancel, connection stages, expected-account validation | Gmail/Workspace remain the actual supported providers |
| First sync | Distinct first-read, long-wait, failure/retry and no-selected-mailbox states | No invented progress percentages or false empty inbox |
| Pull refresh | Pull tension, armed state, reserved working space, 10/30-second status and persistent failure recovery | The margin metaphor uses native motion; no illustrative runtime |
| New-mail admission | Both entry points use the same batch admission and reading-position behavior | Incoming mail does not silently reorder the active reading session |
| Original-email continuity | Native post-to-source navigation, preserved Reply/Forward/Discuss intent and explicit return | Source view identifies one email rather than implying all correspondence |
| Reactions | Tap choices, hold/drag focus, outside cancellation, accessible menu and local-only explanation | Decorative movement reduces with Reduce Motion |
| Save | Durable mailbox-scoped snapshots with live saved state and symbol response | Local to this device; cache clearing preserves them |
| Archive | Immediate filing feedback with a real pre-submission Undo window and a receipt per action | Dormant custom swipe removed; visible/menu/accessibility actions remain |
| Rapid actions | Shared Activity home and separate task/receipt identities | Closing compact feedback hides presentation, not the work |
| Draft → send → result | Independent queued sends, visible outgoing words/status, durable drafts and recovery | Unknown outcomes require checking Sent; never automatic resend |
| Discuss | Prior-turn context, persistent draft/history, answer arrival and reader-controlled jump | One email plus bounded prior turns; attachment contents excluded |
| Search | Search loaded feed/saved sender, snippet and content with explicit scope | Whole-mail search is not promised |
| Sender lanes | Moving selected-lane marker with restrained content changes | Grid contents remain readable and stable |
| Files | Owned cancellable download, distinct temporary file, preview and persistent retry | Actual bytes, not an optimistic preview-only forwarding claim |
| Compact unsubscribe | Bounded-width card, Close/drag dismissal and persistent Activity return | Native sheet provides inspection without resetting jobs |
| Human handoff | Open a fresh sender page, return-unverified state and explicit user-reported completion | Does not preserve the remote browser session or imply provider confirmation |
| Mixed outcomes | Request sent, sender confirmed, needs you, not started and unknown are distinct | Confirmation requires affirmative visible sender evidence |
| Inbox completion | Quiet margin punctuation and stillness only on verified completion | Reaching the loaded endpoint is not proof that all mail or obligations are finished |
| Settings/privacy | Persistent inclusion, valid tags, cancellable dialogs, accurate permission/registration state, export feedback | Disconnect waits for confirmed server cleanup; retained server mail is disclosed |

Detailed native records: [feed](feed-interaction-implementation-2026-09-19.md), [communication](communication-implementation-2026-09-19.md), [onboarding/settings](onboarding-settings-implementation-2026-09-19.md).

## Unsubscribe and action lifetime

The backend now persists account-scoped unsubscribe records in `unsubscribe_tasks`. Structured records carry attempt identity, status, timestamp, recent history, source/handoff URLs and evidence. Client and SQL guards prevent older updates or delayed progress from replacing a completed attempt; a receipt deletion conditionally removes its exact stored version so a concurrent retry survives.

A direct acknowledgement can adopt an already-running server attempt. Interrupted local intent becomes unconfirmed, and stale empty refresh responses cannot erase newer acknowledgements. Initial journal failure publishes “not started” before any external work. A restarted server does not automatically repeat uncertain side effects.

A successful click, a saved-preferences message, a URL slug or a model's unsupported “done” verdict is insufficient confirmation. The agent retains an affirmative removal quote from visible sender text. Ambiguous wording and unsupported/non-English confirmations go to a human check. A mailto request accepted by Gmail remains “Request sent.” Opening a page or reporting completion remains explicitly user-reported.

Reopening an incomplete forward restores its reload action. Uncertain-send warnings hydrate from the saved record through both Activity and ordinary Reply routes. Send jobs persist before submission. Queued work becomes held after restart, interrupted transmission becomes unknown, and each send owns its Undo. Archives lose Undo at the submission boundary. Disconnect clears only the selected account's local work after server cleanup; late feed, People, stream and archive responses cannot restore removed content.

## Verification

Controlled transports and synthetic fixtures are used. No real email sends, unsubscribes, account disconnections, production deployment, purchases or paid infrastructure are used for verification.

| Check | Result | What it proves |
|---|---|---|
| Complete SwiftUI app build, arm64 + x86_64 Simulator | Passed | Integrated native typechecking/linking, including the shared Activity surface |
| FeedStore integration | 125 checks passed | Feed/read/count/session behavior plus disconnect failure, mailbox isolation and delayed People responses |
| Interaction lifecycle | 83 checks passed | Saved persistence, job ordering, acknowledgements, restart/uncertainty recovery, independent receipts and valid archive Undo |
| Send/draft/discussion lifecycle | 35 checks passed | Independent sends, recovery, no automatic resend, unknown-send guard across both draft entry routes, incomplete-forward recovery and discussion persistence |
| Native API client | 50 checks passed | Controlled HTTP payload/authentication/response contracts, including positive disconnect confirmation |
| Account connection policy | 13 checks passed | Scope opt-in, expected identity, tags and persistent feed inclusion |
| Actual WebKit remote-content boundary | Passed on macOS 26.5.1 / WebKit 21624.2.5.11.4 | Zero requests before consent; eight permitted image/style/font requests after consent; zero after revocation; forbidden resources/JavaScript/navigation blocked; deliberate links routed to a recorded external sink |
| Gmail MIME | Passed independent parser | Original text, exact binary attachments, Unicode fields, CC, genuine reply headers and injection/size boundaries |
| Combined server suite | 162 tests passed, zero failures | Existing server behavior plus real-SQL journal/restart/delete races, acknowledgement, disconnect and confirmation evidence |
| Patch hygiene | Passed | No whitespace errors in changed files |
| Setup-related credential scan | Passed within scan scope | No configured credential pattern in authored text/config; only an intentional example.invalid credential-URL test fixture matched |

The native build uses `xcodebuild -project apple/DecisionInbox.xcodeproj -scheme DecisionInbox -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/decision-inbox-craft-build CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build`. Native test runners are under `apple/tests`; the server run uses `node --test server/*.test.js server/tests/*.test.js`.

Simulator review uses a dedicated `DecisionInbox-Craft-QA` device and DEBUG-only `-sampleActivity`, `-sampleFeed`, `-sampleFeedZero`, and `-sampleOnboarding` routes. DEBUG-only `-sampleLargeText` supports repeatable maximum Dynamic Type checks, and `-sampleActivityExpanded` opens the inspection sheet. Reduce Motion is a read-only system environment setting; no debug override or system preference change was retained. Initial inspection confirmed the actionable native Activity sheet and revealed a tab-bar overlap; Activity's inset was moved inside each tab's content, with a single shared sheet presenter. The Feed masthead also now provides a direct Activity return control after compact feedback is hidden. At accessibility text sizes the compact unsubscribe summary uses a shorter status and puts sender details in Activity, preserving the full spoken label. The onboarding comparison switches from side-by-side pills to stacked full-width choices.

Actual [Simulator evidence and limits](../tools/motion-lab/native-qa/README.md): normal compact tray/tab-bar layout, summary → medium Activity, Close, Hide, tap reaction → Reading without unintended navigation, and largest-text Feed, Activity and onboarding renders. The first largest-text Activity capture revealed that presented content needed its own debug environment; corrected captures use the actual maximum size. Simulator focus repeatedly switched to another live-mail device, so further gesture testing stopped. Scroll/drag arbitration, hold-and-drag, return after navigation, VoiceOver and system Reduce Motion remain unverified; the screenshots do not prove those behaviors.

## Tooling and release boundaries

[MOTION_TOOLING.md](../MOTION_TOOLING.md) remains the detailed capability matrix. Motion/Motion+, GSAP, Rive authoring and Higgsedit have exercised isolated fixtures; Xcode and design-reference reads were verified. Direct Motion documentation search, Xcode workspace discovery and the After Effects editable save/render workflow passed after the September 20 tool refresh. Premium Motion MCP authentication remains unresolved; package access is separately verified. No paid upgrade is required for implemented native interactions. Spline/dotLottie remain conditional on a concrete useful asset.

These are local branch changes. The new server schema/routes and native client must be released together; deploying the server first allows the native app's new contracts to be available at rollout. No deployment or live-provider end-to-end result is claimed. The local lifecycle gate assumes a single serving backend process; several concurrent processes need shared cancellation coordination.

Physical-device haptics, energy/frame timing, VoiceOver and the complete narrow/iPad/maximum-text matrix remain distinct from passing model tests. Two Animation Hitches recording attempts could not attach to the Simulator process and produced no usable trace. No performance certification is implied. Preserved remote-browser sessions, complete-mail search, unified multi-account People, account-data erasure and illustrated signature alternatives are not silently introduced by visual polish.
