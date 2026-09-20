# Whole-app motion, interaction and delight audit

September 19, 2026 · **Audit and proposals for review. No production changes authorized or made by this work.**

This audit answers the attached motion-and-delight brief across the entire current native app. It examines interaction craft, tactile feedback, personality, meaningful rewards, and possible signature moments, then maps them to tested creative tools. Product changes remain proposals.

Decision Inbox's current native contract centers on clarity, protection and control. Its monochrome typography, stable reading sessions, native components, and restrained haptics already provide a coherent foundation. The creative opportunity is to make cause and effect feel precise and continuous, with a few distinctive moments around understanding mail and delegating work.

Think of an interaction as a handoff: **intent → acknowledgement → work → outcome → recovery**. Motion can explain each handoff. It cannot supply missing work or invent an outcome.

## What was inspected

This is an app-wide **source and interaction-contract audit**, not a completed device usability or performance study. It covers the current SwiftUI client and the server paths that determine its visible behavior. Findings below are supported by implementation evidence in the linked reports. Predicted layout, focus, timing and network behavior is explicitly marked for runtime verification there. No live email was sent, archived, deleted or unsubscribed for the audit.

The [current native contract](</Users/craigroberts/email-ai/product_docs/Email App.md:19>), [current versus archived Figma map](/Users/craigroberts/email-ai/product_docs/figma-audit-2026-09-19.md), and [zero-shot policy](/Users/craigroberts/email-ai/product_docs/zero-shot-philosophy.md) govern the review. Older Expo/design promises are not evidence of native features. The working tree also contains separate ongoing server/product work; this report describes the inspected snapshot, not all future changes.

| Journey | Coverage | Detailed evidence and proposals |
|---|---|---|
| Begin and connect | Onboarding, provider selection, disclosure, OAuth, account addition/reconnect | [Onboarding and Settings audit](/Users/craigroberts/email-ai/product_docs/audit-onboarding-settings-2026-09-19.md) |
| Read and process | Feed, new-mail admission, first sync, refresh, pagination, Old Posts, navigation, reactions, archive, receipts | [Feed and motion audit](/Users/craigroberts/email-ai/product_docs/audit-feed-motion-2026-09-19.md) |
| Understand and communicate | Original email, Discuss, compose, reply, forward, People list and conversation | [Communication and content audit](/Users/craigroberts/email-ai/product_docs/audit-communication-content-2026-09-19.md) |
| Retrieve and inspect | Search, Saved, sender profile, media/files, link cards, attachment preview | [Communication and content audit](/Users/craigroberts/email-ai/product_docs/audit-communication-content-2026-09-19.md) |
| Delegate unsubscribe | Entry points, compact tray, log sheet, batches, human handoff, status/evidence, receipts | [Unsubscribe audit](/Users/craigroberts/email-ai/product_docs/unsubscribe-experience-audit-2026-09-19.md) |
| Control the app | Mailboxes, tags, feed inclusion, AI, notifications, Senders, privacy, contact photos, rich links, export, clear, About | [Onboarding and Settings audit](/Users/craigroberts/email-ai/product_docs/audit-onboarding-settings-2026-09-19.md) |
| Shared craft | Typography, tokens, reduced motion, haptics, targets, focus, loading/empty/error states, performance constraints | All four reports and [motion system](/Users/craigroberts/email-ai/MOTION_AND_DELIGHT_SYSTEM.md) |

## Craft audit by experience

These judgments come from source and product/design documentation. “Present” means an implemented foundation, not a measured smoothness or accessibility pass. The visual identity is already intentional; personality need not mean more color, decoration or bounce.

| Experience | Present foundation | Where craft can deepen | What the movement must communicate |
|---|---|---|---|
| Onboarding | Strong typographic hierarchy, short crossfades, clear provider choices | Replace some explanation with a small, user-controlled demonstration of original → meaning → action; make connection handoff and recovery legible | What the app changes about reading email, and which account is connecting |
| Feed and masthead | Stable reading session, atmospheric motion, type/numeric transitions, explicit new-post admission | Reduce competing ambient movement; give pull/release/refresh one continuous response; keep optional recap work separate from mail readiness | My gesture was accepted; mail is being checked; these are new arrivals |
| Posts and actions | Consistent visual grammar, native symbols, generous main action targets | Complete tap/drag/retreat paths; give a small control and a whole card different physical weight; connect saved/archive result to the originating post | Press, selection, commitment and reversal are different states |
| Original email | Native navigation, cached content, readable source, explicit remote-image action | Preserve source identity and scroll position through expansion; let new interpretation arrive without shifting active reading | This is the original behind the summary; Back returns to my place |
| People and sending | Native conversation layout, inline composer, historical anchor preservation | Retain the authored words as they move through queued/sent/recovery; make files and links responsive to input | The message belongs to this conversation and has this actual delivery state |
| Discuss | Distinct question/answer typography and an existing caret language | Give response arrival a quiet rhythm, preserve input on failure, reveal source scope, and avoid surprise scrolling | The assistant is answering this question with this known context |
| Search and Saved | Reused post language and native routes | Give query/results stable transitions and an honest scope; make saving visibly connect to later retrieval | The result belongs to this query; the saved item will be here later |
| Sender profile | One identity across email, media and files; source-only content | Anchor identity while switching lanes; reveal media progressively without grid jumps; make file waits cancelable | Different views of the same sender, with a clear current selection |
| Unsubscribe | Persistent compact status, live step text, native log sheet | Bound the tray, give it a true close, separate background work from visibility, and reveal a usable human handoff | The app is working; it now needs me; this is the evidence of the result |
| Settings and recovery | Consistent rows, shared labels, explicit consequences in places | Favor immediate acknowledged changes, inline validation and native confirmation; reserve expressive motion for explanatory onboarding | What changed, whether it persisted, and whether the operation finished |

### Five levels across the app

- **Functional:** already the strongest layer—native navigation, counts and status. Gaps occur where states or action ownership are incomplete. Quality comes from clear transitions and stable reading position.
- **Tactile:** some threshold/haptic logic exists, but the row archive gesture is currently detached and a press state is dormant. Complete usable gestures and interruption behavior before treating the code inventory as a polished experience.
- **Personality:** DM Sans/DM Mono, the caret, calm language and the masthead provide ingredients. A coherent rhythm around “understand, decide, act” could be more recognizable than adding an unrelated mascot.
- **Reward:** verified arrival at a meaningful endpoint can earn a quiet resolution. Sent requests, failed batches and unknown outcomes cannot borrow that same completion treatment.
- **Signature candidates:** continuous pull-to-refresh, a useful original-to-understanding reveal, or a real agent-to-human handoff. Each communicates a product idea; none requires a rocket, confetti, or constant spectacle.

### Quality bar

The existing token system and native surfaces support the brief's **good** foundation. **Great** requires complete input, interruption and recovery paths with deliberate timing and stable spatial relationships. **World-class** remains a direction to validate: recognizable product-specific behavior that still feels immediate, accessible and quiet during ordinary reading. Source inspection alone cannot award that quality level or prove frame-rate smoothness.

## Three directions for the overall experience

These are concept families, not a ranking. All three require truthful state and usable actions.

| Direction | What the app feels like | What it buys | What it costs |
|---|---|---|---|
| **Restrained: clear local feedback** | Native controls, compact receipts, explicit recovery beside the action; little additional movement. | Low interruption and a calm reading surface. | Long-running work still needs a defined place to return to; local controls can become inconsistent without shared rules. |
| **Expressive: continuity across actions** | A draft stays identifiable as it becomes queued mail; a sender action becomes a status; attention appears where the work started. | The product feels responsive because cause and effect remain visible. | Requires stable identities and shared action state across routes; transitions must survive navigation and interruptions. |
| **Signature: inspectable delegated work** | A compact activity surface reveals what the app is doing, what it knows, and what needs the person; a selected handoff can continue into human control. | A memorable expression of the app's promise to make email easier to act on. | Durable task records, background reconciliation and, for true browser continuation, session infrastructure. This is a product capability with motion around it. |

The choice depends on how much ongoing work the product should own after someone leaves an email. Frequent, brief actions favor light feedback; deferred tasks and human handoffs make retained activity more valuable. Signature motion is an option for a few meaningful moments, not a new visual treatment for every screen.

## Twenty app-wide opportunities

Value, creative upside, complexity and risk are **qualitative design judgments**, not user-study results, measured performance or a priority order. Rows follow the user journey. The runtime is SwiftUI unless an authored illustration has a specific approved purpose; web tools are separate studies.

| Moment | Level | User value / why it moves | Creative upside | Complexity | Performance risk | Production tool |
|---|---|---|---|---|---|---|
| Original email → quote → implication example in onboarding | Personality | High: makes the product understandable through a tap | High | Medium | Low | SwiftUI; Rive only if illustration teaches more |
| Provider choice → connected mailbox identity | Functional | High: preserves which account is being connected | Medium | Medium | Low | Native navigation + SwiftUI |
| First sync with real stage and recovery | Functional | High: distinguishes waiting, retry and failure | Medium | Medium | Low | SwiftUI status/caret |
| Pull distance → armed state → live refresh → resolution | Tactile / Signature candidate | High: keeps input and actual work connected | High | High | Medium | SwiftUI gesture + existing haptics; optional Rive study |
| New-mail admission from either entry point | Functional | High: preserves reading position until deliberate admission | Medium | Medium | Medium | Native list identity/scroll + focus |
| Expand original email without losing the source post | Functional | High: spatial continuity and a clear return | Medium | Medium | Low–medium | Native navigation/transition |
| Reaction tap and press-drag agree | Tactile | Medium: choices respond to the finger and remain accessible | High | Medium | Low | SwiftUI buttons/gesture + haptics |
| Save acknowledges a durable bookmark | Functional | High: confirms retrievable work | Medium | Medium | Low | SwiftUI symbol transition + persistence |
| Archive commitment, retreat and valid Undo | Tactile | High: distinguishes intent from committed action | Medium | High | Medium | Native controls/gesture, Move tokens |
| Rapid action receipts preserve ownership | Functional | High: prevents one result hiding another | Medium | High | Low | Shared action model + SwiftUI |
| Draft stays visible through queued/sent/recovery | Functional / Tactile | High: preserves the user's work | High | High | Low–medium | SwiftUI stable message identity |
| Discuss answer arrives without stealing reading position | Functional / Personality | High: explains context and response arrival | Medium | Medium–high | Medium for long content | SwiftUI scroll/focus; bounded content transition |
| Search shows partial versus complete scope | Functional | High: makes absence of results meaningful | Medium | High for full search | Medium | SwiftUI results/status; search service |
| Sender profile lane switch preserves selection | Functional | Medium: maintains context among mail/media/files | Medium | Medium | Medium for grids | SwiftUI selected marker + lazy content |
| File selection → real download → preview/retry | Functional | High: ownership and cancellation during a wait | Medium | Medium | Medium for memory | Native file preview + request state |
| Unsubscribe compact acknowledgement and close | Functional / Tactile | High: accepts the task without taking over the feed | Medium | Medium | Low | SwiftUI inset, native sheet |
| Needs-you state reveals a usable next action | Functional | High: converts a blocker into agency | High | High for true continuation | Low UI; service cost separate | SwiftUI + structured handoff contract |
| Confirmed result becomes an inspectable receipt | Reward | High: makes the evidence and outcome legible | Medium | Medium–high | Low | SwiftUI content/symbol transition |
| Human handoff returns to honest recheck | Signature candidate | High: keeps the user and agent in one task | High | High | Low UI; session infrastructure cost | SwiftUI task reconciliation; Rive optional reference |
| Export creates a file or presents useful recovery | Functional | Medium: an accepted tap has an outcome | Low | Low–medium | Medium for large export | Native share sheet/status |

For every row, reduced motion keeps the same information and actions using stable placement, immediate state changes or bounded crossfade. Progress uses known work/bytes only. Existing haptics remain sparse; routine network events and successes remain silent. No sound layer or 3D dependency is required by the identified interactions.

The [six detailed motion directions](/Users/craigroberts/email-ai/product_docs/motion-concept-directions-2026-09-19.md) develop restrained, expressive and signature alternatives for onboarding, pull refresh, reading, sending, Discuss and meaningful completion. They specify input mapping, timing intent, interruption, long waits, failure and reduced motion. Unsubscribe has its own [presentation and handoff alternatives](/Users/craigroberts/email-ai/product_docs/unsubscribe-experience-audit-2026-09-19.md).

## Decisions to resolve before implementation

1. **Action lifetime:** brief latest-action feedback, grouped actions, or durable per-task history? This defines what survives leaving a screen and which Undo belongs to which action.
2. **Work preservation:** recoverable drafts/bookmarks and persistent settings, or explicitly temporary state? Labels and restart behavior need to agree.
3. **Feature scope:** loaded-feed filter versus complete-mail search; single-question analysis versus remembered discussion; first-account People versus unified People. Each broader promise adds data and recovery work.
4. **Delegation:** fresh sender page versus preserved remote-session handoff; request sent versus evidence of confirmation. These choices determine unsubscribe's real control surface.
5. **Access lifecycle:** remove from this device, stop server access and delete retained data are distinct effects. Decide which Disconnect promises and how incomplete operations recover.

These are independent decisions; choosing an expressive animation does not require choosing every broader capability.

## Supporting findings: contracts that affect craft

These are grouped by the kind of judgment required, not a proposed implementation order. “Source-confirmed” does not mean a live user incident was reproduced.

| Promise | Source-backed gap | What it means for the person | Evidence |
|---|---|---|---|
| My words survive sending | A second queued send cancels the first pending task. Draft text is cleared and has no recovery on Undo/rejection. | Fast consecutive sends can silently discard intended mail; interruption can lose writing. | Communication C1–C3 |
| Forward sends what I see | Original content/files are displayed but the MIME payload contains only newly typed text. | The preview overstates what the recipient receives. | Communication C4 |
| Undo is available while it is honest | Send feedback lives mainly in Feed; Undo is not removed when transport starts. A cancelled receipt timer can clear a newer receipt. | Recovery is absent at some entry points or can claim more than it can reverse. | Communication C2; Feed findings 2–3 |
| Disconnect ends access | Local removal deregisters push and deletes device credentials; it does not delete server credentials or stop server workers. | The product's stronger access-ending promise is unsupported by that operation. | Settings first finding |
| Settings and saved work persist | Feed inclusion and Saved flags are in memory. | A cold start can restore excluded accounts and lose saved choices. | Settings feed-exclusion finding; Communication C6 |
| Search means my mail | Search filters only loaded Feed fields. | Known emails in history, bodies, files or other unloaded content are missing. | Communication C8 |
| Discuss is a conversation about a thread | Requests contain one question and one message's bounded context, with no prior turns or attachment content. | Follow-up questions can lose their referent; reopening loses the discussion. | Communication C9 |
| A visible control does something | Tappable reaction choices lack handlers; default standalone link cards are inert; some Reply/Forward callbacks do nothing or lose intent. | Matching-looking controls behave differently by route. | Feed findings 1,9; Communication C5,C7 |
| Waiting explains what is happening | Offline state can be overwritten; cached refresh loses its explicit acknowledgement; first-sync errors sit behind loading. | Silence can look like freshness, and failure can look like ongoing work. | Feed findings 4–6 |
| “Needs you” gives me something to do | Unsubscribe has no structured human action; the agent closes the browser session on a blocker. | The person cannot finish the delegated task from its status. | Unsubscribe findings |
| Closing a surface preserves my task | Log Done clears the transient status dictionary; later events can bring the tray back. | Dismissal, record deletion and work lifecycle are entangled. | Unsubscribe findings |
| Success means the same thing everywhere | Request transmission becomes sender confirmation; Settings counts unsuccessful attempts as unsubscribed. | Completion visuals and labels overstate evidence. | Unsubscribe findings; Settings Senders finding |
| Privacy controls describe real boundaries | Storage disclosure omits retained server message data; HTML remote-resource rewriting has coverage gaps. | The source does not support the full displayed promise. Actual resource requests require a controlled runtime recorder. | Settings storage/consent findings; Communication C10 |
| My account is unambiguous | People uses the first account without labeling it; reconnect does not validate the returned account against the target. | Scope and recovery are hard to predict. The normal People flow reads and sends from the same first account; no wrong-account send is claimed. | Communication C11; Settings reconnect finding |

The detail reports also cover notification authorization versus delivery, tag validation, persistent destructive confirmation, attachment races/cancellation, export failure, narrow layouts and accessible action coverage.

## Verification boundary

Each detailed report provides synthetic acceptance scenarios. Device validation still needs touch/gesture testing, largest Dynamic Type, VoiceOver and focus, reduced-motion changes while running, narrow/landscape layouts, offline/slow/mixed-account outcomes, repeated actions, navigation/backgrounding and restart. Native Instruments checks need a realistic long feed on a physical device. No frame-rate, battery, accessibility or live-provider pass is claimed here.

The separate [tooling record](/Users/craigroberts/email-ai/MOTION_TOOLING.md) records actual installed versions, successful smoke checks and blocked capabilities. Creative fixtures do not change the production app or prove its native runtime integration.
