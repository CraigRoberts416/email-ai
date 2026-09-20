# Six native motion directions for review

September 19, 2026 · **Unapproved product concepts; no app implementation**

The attached brief asks for an intentionally designed product: physical responses, understandable state changes, personality and a few memorable moments. These are creative directions for that brief, rather than another defect inventory. The source audits document the underlying behavior separately.

The existing identity gives the exploration a clear starting point: monochrome surfaces, DM Sans for human content, DM Mono for instrumentation, and native navigation ([current design reference](/Users/craigroberts/email-ai/product_docs/figma-audit-2026-09-19.md:3)). The useful creative territory is **reading, margins, annotation and the relief of a settled task**. That is an inference from this identity and the brief, not an approved brand expansion.

“Restrained,” “expressive,” and “signature” describe three amounts of expression, not a quality ranking. They can be mixed across moments. Six signature candidates are presented for comparison; selecting all six would contradict the brief’s limited signature budget.

## Shared boundaries and vocabulary

- **The app supplies truth; motion explains it.** A spring settling does not establish network success. Unknown totals, an unanswered request and an unconfirmed send remain unknown.
- **Current versus proposed:** each section names the source behavior, then proposes choreography and inputs. New states, persistence, cancellation or evidence relationships below are design requirements, not claims that those APIs exist.
- **Timings are study values.** The native system already separates press, commit, cancellation, layout and exit ([Move](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Tokens.swift:525)). Proposed ranges describe relative weight and purpose; they need comparison on device. Paragraphs remain still and readable while small controls can feel more responsive.
- **One state owner:** the interaction follows a stable request or message identity. A new input retargets from the current visible pose; an old completion cannot dismiss a newer operation. Closing a view means closing that view unless a separate action explicitly cancels work.
- **Accessibility is another composition:** no travel, fold, scrub or morph is required to understand or perform an action. Text/status, real buttons, focus order and accessible alternatives remain complete. Large text changes layout; it is not scaled down to preserve a composition.
- **Quiet is part of the personality.** Current haptics distinguish threshold, commit, announce and needs-attention, with detents for discrete selection. Routine send, Discuss, refresh success and feed completion are intentionally silent ([Haptics](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Haptics.swift:117)). None of these concepts silently adds a success buzz or sound. A future sound study would be a separate opt-in product decision.
- **Tool routing is platform-specific.** SwiftUI is the native interface layer. Motion and GSAP can make browser studies; they are not SwiftUI dependencies. Rive is a candidate for a bounded illustrated state machine when that expression earns an asset/runtime. A render or local CLI test does not prove native integration. Higgsfield/After Effects can supply editable timing/art-direction studies; flattened video cannot own these interactions.

## 1. Pull to refresh — “I asked; it responded”

**Current foundation:** the custom pull maps overscroll into an arming interval, provides threshold feedback, refreshes the session and resolves to freshness/failure text ([FeedView](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:541), [thresholds](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Tokens.swift:599)). The creative opportunity is continuity from the finger to the wait to the result, without moving the reading surface after release.

| Direction | Concrete choreography | Buys / costs |
| --- | --- | --- |
| **Restrained — a precise margin** · functional/tactile | Pull reveals the existing vertical rule and instruction one-to-one with distance. Crossing the threshold turns the rule solid. Release contracts only the indicator into a compact “Checking” line; known completion replaces that line with freshness text. The feed never waits for the final fade before becoming usable. | Familiar, quick and cheap to render. Distinctiveness comes from timing and typography rather than a new visual object. |
| **Expressive — a tensioned rule** · tactile/personality | The rule bends into a shallow arc as pull distance increases, then aligns with the text baseline at the threshold. Release gives the thin rule a brief 140–220 ms elastic recovery, while text stays still. The rule becomes the working caret; success resolves it into a short underline beneath the freshness stamp. | Makes gesture tension visible and gives the existing mark a recognizable behavior. Requires path interpolation and careful suppression of double rubber-banding. |
| **Signature — the freshness receipt** · signature | Pull exposes the edge of a small typographic receipt inside the overscroll space. At 0–35% only its edge appears; 35–85% reveals “Check mailbox”; 85–100% aligns the receipt on its baseline. Release feeds the small receipt into its resting slot over 240–360 ms, with velocity affecting settle only. The receipt contains a static checking label until the real result typesets a time or failure. No invented mail counts or moving content previews. | A tangible, repeatable ritual tied to asking for fresh mail. Adds more geometry, edge cases and visual weight to a frequent action. A Rive illustration could own the paper edge while native text owns status. |

**Inputs:** normalized pull distance, release velocity, armed/disarmed, request ID, checking/result/failure, last successful check. Pull percentage describes the gesture, never download progress. Sub-threshold release reverses to idle with no request; crossing back disarms. Repeated pulls during a request need one visible in-flight policy. Navigation/backgrounding stops decorative motion; re-entry shows the current operation, without replaying the release.

**Long wait and recovery:** at 10 seconds keep the latest known freshness and say the current check is still waiting; no “almost done.” At 30 seconds preserve usable cached mail and expose recovery appropriate to known connectivity. Failure leaves legible text and Retry; the receipt/rule settles, rather than drooping, shaking or staging a comic failure. A late result updates the matching request only.

**Reduced Motion / touch / cost:** use a static rule, explicit “Release to refresh,” checking/result text and short opacity changes. The accessible Refresh action reaches the same states without a gesture. Existing threshold cues apply on arm/disarm, with no second cue on release or success. Animate only the indicator while visible; profile the signature’s path/mask cost separately from feed scrolling.

**Decision:** how much identity belongs in a frequent gesture: nearly invisible precision, felt tension, or a small ritual?

## 2. Onboarding — “I understand what this app does”

**Current foundation:** a labeled sample post leads through provider selection and a permission primer into system OAuth; step changes crossfade ([OnboardingFlow](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Onboarding/OnboardingFlow.swift:25)). The brief creates room for an interactive explanation before connection. Permission disclosure remains readable, immediate and outside any theatrical sequence.

| Direction | Concrete choreography | Buys / costs |
| --- | --- | --- |
| **Restrained — continuity of the page** · functional | Keep the heading’s baseline and CTA zone consistent across steps. The departing step clears in about 120 ms; the next resolves over 180 ms with no per-line stagger. Back returns to the prior state and focus location. Provider selection visually persists into its primer. | Orientation and polish with low distraction. It explains the flow more than the product’s special value. |
| **Expressive — show the reading** · personality | The sample email and sample interpretation share a frame. A real “Show how it reads” control reveals one source phrase, then its corresponding interpretation in two short overlapping beats. Nothing auto-hides and all text is immediately available through accessible controls. The example resets only on explicit Replay. | Demonstrates value in context and gives typography a purposeful rhythm. Needs a carefully authored synthetic sample and factual correspondence. |
| **Signature — a source-to-reading lens** · signature | A draggable divider lets the user move continuously between the sample original and its interpreted view. Stable sender, date and source phrases stay registered; the interpretation appears through the moving boundary. Releasing preserves the chosen position rather than snapping them through a tour. Buttons offer “Original” and “App reading.” The user can connect at any point. | An inspectable explanation people can remember, with the user controlling the reveal. Adds gesture/accessibility complexity and could overpromise exact source correspondence unless the example and product truly support it. |

**Inputs:** step, chosen provider, explanation position (0…1), authentication outcome and first real feed readiness. The source lens is explicitly labeled **Example**; it never contains actual mailbox data before consent. Interrupting the lens keeps the selected position. Back reverses navigation, not consent already granted to a provider. The system authentication sheet owns its own movement.

**Long wait and recovery:** at 10 seconds distinguish “Complete connection in Google” from an app operation after the callback. At 30 seconds offer a real way out or restart only if that operation supports it. User cancellation returns to a recoverable step without a failure animation. Provider failure says what failed. First sync after successful connection is its own state; it does not replay the educational sequence to fill time.

**Reduced Motion / touch / cost:** a static Original/App reading switch replaces the lens; content remains accessible at maximum Dynamic Type. No haptic or sound pressures the permission decision. The small synthetic example can be preloaded, and animations stop behind OAuth. SwiftUI covers the first two directions; the lens can remain native, with Rive only if a separate illustrated explanation materially helps.

**Decision:** should onboarding’s personality come from a composed sequence, an optional demonstration, or a hands-on explanation? The cost of expressiveness is additional attention before the mailbox is connected.

## 3. Reading and original email — “I know where I am”

**Current foundation:** opening a post presents the sender’s original email in a native sheet. The body is seeded from cache, readable cached content survives refresh failure, and remote images require explicit loading ([ThreadView](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Thread/ThreadView.swift:27), [content states](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Thread/ThreadView.swift:237)). The active feed session must survive this round trip ([session contract](/Users/craigroberts/email-ai/product_docs/figma-audit-2026-09-19.md:46)).

| Direction | Concrete choreography | Buys / costs |
| --- | --- | --- |
| **Restrained — native arrival** · functional | Keep system presentation, with sender identity and subject visible on the first frame. Cached content appears immediately. A genuine loading placeholder waits briefly before appearing and only changes opacity on resolution. Back restores the previous reading location. | Fits the platform and minimizes reading latency. Spatial connection relies mainly on identity and preserved position. |
| **Expressive — the sender stays with you** · functional/personality | Preserve a shared sender/avatar anchor across entry, while the destination surface resolves around it. The shared identity settles first; the original text is readable as soon as ready, without a waterfall reveal. Dismissal tracks the system gesture and returns toward the source identity when it still exists. | Makes a large visual change feel connected. Requires a compatible native transition and fallback when the source is off-screen or no longer present. |
| **Signature — open the source margin** · signature | Where there is a verified exact-source excerpt, opening “Original” holds that excerpt’s margin steady while surrounding source context expands around it. The rest of the email arrives as one readable surface, not letter by letter. A small source label remains until the user scrolls. If exact correspondence is unavailable, use the ordinary route. | Turns “show me the original” into a clear, memorable act of verification. Needs reliable excerpt anchors, HTML layout coordination and a robust fallback; current code does not establish that mapping. |

**Inputs:** originating post identity and frame, route progress, cached/body-ready state, optional verified excerpt anchor, dismissal progress. Dragging back reverses presentation continuously; canceling dismissal resumes from the current pose. A missing source row must resolve to a normal dismiss rather than flying to guessed geometry. The transition never marks other feed cards read.

**Long wait and recovery:** at 10 seconds keep source metadata and any cached body/snippet readable. At 30 seconds expose retry and distinguish missing body from blocked remote images. An image-loading opt-in is not simulated by animation. Failure does not retract text already read or run the entrance again on retry.

**Reduced Motion / touch / cost:** use native reduced navigation behavior and an immediate shared identity, with no zoom or source expansion. Restore focus to the initiating post/action. No custom navigation haptic. Avoid animating or taking repeated snapshots of a large WebView; bind motion to the small identity/margin layer, reserve source geometry, and measure HTML hydration separately.

**Decision:** familiar navigation, stronger sender continuity, or explicit source verification? The signature option becomes credible only where the app can prove the excerpt-to-source relationship.

## 4. Sending — “My words are still under my control”

**Current foundation:** send queues a draft, waits eight seconds, then submits; its result distinguishes confirmation, refusal and uncertainty ([send lifecycle](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:1479), [window](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Tokens.swift:571)). The creative opportunity is to make the reversible interval feel deliberate. The separate communication audit documents state/receipt gaps that must be resolved for any of these concepts.

| Direction | Concrete choreography | Buys / costs |
| --- | --- | --- |
| **Restrained — a held message** · functional | The composer closes normally, and a receipt in the initiating context shows “Queued” with Undo. A thin time indicator represents only the known undo interval. At its deadline the receipt changes to “Sending”; only confirmation produces “Sent.” | Precise and light. The user’s actual words are less visible while waiting, so recovery needs a dependable draft destination. |
| **Expressive — draft becomes pending message** · tactile/personality | In a conversation, the submitted draft contracts into an outlined pending bubble in roughly 180–260 ms, preserving the first readable line. Undo expands those same words back into the editor. At submission the outline changes weight; confirmation adds a settled status mark without launching the bubble away. A standalone composer uses an equivalent pending card. | Strong ownership and visible reversal. Needs per-message pending state and consistent behavior across composer hosts. |
| **Signature — the outgoing fold** · signature | Only a small abstract paper edge beside the pending message folds during the reversible interval. It follows remaining undo time, with no implication of delivery. Undo unfolds it into the restored draft; submission aligns the edge; confirmed receipt makes it a quiet typographic rule. The words stay readable and still throughout. | A tactile metaphor for “held before it leaves,” with reversible form. More complex than a time indicator, and the metaphor needs testing so a folded paper is not mistaken for sent mail. |

**Inputs:** stable draft ID, queued deadline, transmitting, confirmed, refused, unconfirmed, and draft-restored. Animation follows the actual clock, so backgrounding never extends the deadline. Undo is meaningful only before irreversible submission; a visual reversal cannot unsend provider mail. Another send has its own identity and cannot replace the first. Leaving the route keeps outcomes reachable under the selected persistence policy.

**Long wait and recovery:** at 10 seconds from the tap, an eight-second queue may only be two seconds into submission: label the actual phase. At 30 seconds, keep either honest “Sending” or the transport’s uncertainty outcome; elapsed time alone does not prove failure. A definite refusal offers preserved text and deliberate retry. An ambiguous result prompts checking Sent mail, never an automatic duplicate send. No celebratory motion before confirmation.

**Reduced Motion / touch / cost:** static pending card and textual remaining undo time; no fold, travel or morph. Undo returns focus and text to the editor. Current policy keeps Send and success silent; needs-attention may fire once for an actionable foreground outcome. Only visible pending items animate. SwiftUI can own receipts/bubbles; Rive is optional for the isolated edge, with native text and buttons.

**Decision:** does send confidence come from a compact receipt, the visible continuity of the user’s words, or an additional physical cue? The relevant cost is state ownership and draft recovery, not just animation code.

## 5. Discuss — “The app is working on my question”

**Current foundation:** the model appends a question, waits for one complete response, then supplies answer or failure. The answer is unboxed so it does not look like human mail ([DiscussModel](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Thread/Discuss.swift:24), [presentation](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Thread/Discuss.swift:44)). No streaming chunks or source-citation mapping are established by this UI.

| Direction | Concrete choreography | Buys / costs |
| --- | --- | --- |
| **Restrained — a named caret** · functional/personality | The question takes its place immediately. A caret with an explicit working label occupies the answer origin. On completion, the full answer replaces it in one short opacity change. No fake typewriter reveal. | Calm and truthful for the current request model. Less expressive than a conversational transition, but protects reading speed. |
| **Expressive — question and answer share a baseline** · tactile/personality | The field’s submitted text resolves into the question bubble as one 160–220 ms movement; the answer’s margin aligns below it. The working caret remains at that margin. A completed answer appears as a readable block while the margin quietly settles. | Makes the act of asking feel connected to its response. Requires keyboard/focus and scroll anchoring so the movement cannot steal the reader’s place. |
| **Signature — the annotation margin** · signature | For a future response with verified source references, a selected answer passage opens its cited email excerpt in a neighboring annotation surface. The shared margin extends between answer and source; choosing a different citation retargets the connection. During generation there is only a working label, never a fabricated scan across email text. | Makes explanation and evidence a distinctive interaction. Requires actual source references, responsive alternate layouts and meaningful citation selection; it cannot be fabricated from the present answer string. |

**Inputs:** question ID, submission, waiting, completed answer, failure and optional future source selection. The submitted question remains visible. If Stop is added, its contract must distinguish stopping presentation from canceling server work; the present UI does not establish cancellation. Leaving cancels view-owned animation. Re-entry behavior depends on an explicit discussion-retention decision, not a replayed entrance.

**Long wait and recovery:** at 10 seconds the label can say the answer is still being prepared, without claiming internal reasoning stages. At 30 seconds keep the question, show known error/timeout or continued waiting, and offer only real recovery. Retry preserves the question as the same logical attempt or clearly creates a new one. Errors replace the waiting mark with legible copy and an action, not a shrugging character.

**Reduced Motion / touch / cost:** static working label and complete answer; source references open through ordinary labeled controls. No per-token animation, haptics or sound. Scroll follows only when the user is already at the latest turn; otherwise offer a new-answer affordance. SwiftUI handles the first two options; the signature is primarily an information/interaction model, not a reason to add a canvas runtime.

**Decision:** how much does Discuss need to feel conversational versus editorial? The annotation direction is strongest when real evidence navigation is itself a product capability.

## 6. Meaningful completion — “There is room to stop”

**Current foundation:** the feed distinguishes reaching the history endpoint from verified zero, and provisional count changes from provider confirmation ([completion predicates](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:72), [verified zero](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:209), [footer](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Feed/FeedView.swift:641)). Reading mail does not finish the real-world tasks inside it. The existing masthead expresses state through monochrome intensity and tempo ([atmosphere](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/MastheadAtmosphere.swift:21)).

| Direction | Concrete choreography | Buys / costs |
| --- | --- | --- |
| **Restrained — a clear endpoint** · functional | The last confirmed count settles and the endpoint label appears in place. “No more emails” stays available, with old-post access where allowed. No visual celebration of an optimistic zero or a failed load. | A dependable stopping point with almost no attention cost. Emotional reward comes from certainty and whitespace. |
| **Expressive — the page exhales** · personality/reward | On a genuine transition to verified zero, the masthead’s existing washes lose intensity and slow over roughly 600–900 ms. A single margin rule resolves; the reader’s scroll position and all controls stay fixed. Nothing repeats on ordinary re-entry. | Gives completion a bodily feeling of reduced activity without a trophy. The change is subtle and cannot carry the completion meaning without words. |
| **Signature — the closing mark** · reward/signature | At a defined rare milestone, an abstract pair of open margin marks meet into a final typographic full stop over 400–600 ms, followed by stillness. A factual, scoped line remains: for example, verified unread mail is clear, not “everything is done.” The next real arrival reopens the mark without replaying a celebration. | A distinctive ending tied to the product’s reading vocabulary. Requires a deliberate milestone policy and persistent replay guard; repeated zero events would make it tiring. |

**Inputs:** known versus unknown totals, provisional versus confirmed reads, endpoint verified, verified-zero transition, pending arrivals, visibility and an optional approved milestone identity. Never animate the document’s geometry to manufacture an empty screen. Read failure restores the count and current state without an accusatory reversal. Fresh arrivals stop a not-yet-finished completion sequence and restore the waiting state from the current pose.

**Long wait and recovery:** at 10 seconds of checking, keep “Checking” and the last known count; at 30 seconds expose the known failure or manual check path. Neither timer unlocks the closing mark. Offline/partial mailboxes cannot become verified completion through visual calm. The ordinary endpoint remains useful even when total unread is not zero.

**Reduced Motion / touch / cost:** use a static final mark and explicit completion copy; atmosphere becomes a still composition. Announce the meaningful state once and avoid taking focus from the reader. Existing policy forbids routine endpoint haptics; a milestone haptic would be a separate unapproved departure. Stop decorative activity off-screen or in the background. SwiftUI can handle the field/rule; a tiny Rive mark is an alternative asset workflow, not a required dependency.

**Decision:** whether reward is simply a reliable ending, a subtle sense of relief, or a rare visual punctuation. The unresolved product choice is what counts as a milestone without turning inbox use into a pressure-driven streak.

## Comparison and review criteria

| Question | What would make the decision clearer |
| --- | --- |
| Does the motion help? | Observe whether someone can explain what triggered it, what is now true, and what they can do next. A memorable effect that confuses state fails that test. |
| Where does personality belong? | Compare frequent refresh/reading with optional onboarding/rare completion. Frequency determines how much attention an effect can reasonably ask for. |
| Is the sequence interruptible? | Trigger Back, a second action, a changed result and backgrounding at several points, including halfway through a transition. No queued flourish gets to finish before the new state. |
| Does the quieter version feel complete? | Compare normal and Reduced Motion side by side. Both need equivalent orientation, controls, recovery and emotional coherence. |
| Is the claim supported? | Use synthetic immediate, 10-second, 30-second, offline, rejected and ambiguous outcomes. Source-backed navigation, progress, cancellation and success must exist before their visual metaphors imply them. |
| Does it fit the reading product? | Test at maximum Dynamic Type and on the smallest supported width, with long sender names, long answers and active scrolling. Typography remains still, readable and in order. |
| Is the cost justified? | Measure input response and frame time on a supported lower-powered phone; compare off-screen/background behavior. No extra WebView snapshots, per-frame full-feed work or always-on asset loop is accepted by visual inspection alone. |

These directions are deliberately unranked. The next review can choose the amount of expression per moment and the limited signature budget, while keeping the existing truth, reading-session and accessibility contracts explicit.
