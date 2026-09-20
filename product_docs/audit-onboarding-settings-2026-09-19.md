# Onboarding, settings, consent and accessibility audit

Recorded September 19, 2026. Scope: the current SwiftUI app in `apple/DecisionInbox`. This is a source audit and proposal, not an implementation approval. No product code, accounts, permissions, mail or external services were changed. Live device behavior was not tested in this pass.

The relevant product contract is **control over automation, trust through evidence, a calm interface**, plus the September 19 native requirements for feed sessions, contact photos and recoverable loading. Settings should be a reliable control panel: each label describes the thing the switch actually controls, and each action ends with an outcome the app can establish.

## Grounding and evidence boundaries

- [Current product contract](</Users/craigroberts/email-ai/product_docs/Email App.md:19>): sections 11.12–11.12.2, 12.9 and 13.11.1 supersede older behavior descriptions. The older onboarding section lists Outlook and Yahoo; current code supports Gmail only and marks the others unavailable.
- [Native versus archived designs](/Users/craigroberts/email-ai/product_docs/figma-audit-2026-09-19.md:1): archived settings and onboarding concepts are not shipped functionality. Current Figma specimens are design references, not proof that an account operation succeeds.
- [Motion system](/Users/craigroberts/email-ai/MOTION_AND_DELIGHT_SYSTEM.md:1) and native `Move`/`Haptics` tokens: preserve monochrome DM Sans/DM Mono, native navigation, reduced-motion alternatives and sparse haptics. No additional animation runtime is necessary for the proposals here.
- [Operational copy exception](/Users/craigroberts/email-ai/product_docs/zero-shot-philosophy.md:18): literal navigation, consent and recovery labels must remain usable if generated copy is unavailable. Consent and deletion outcomes cannot depend on a model inventing the right wording.

**Confirmed** below means the source establishes the control, missing branch or contradictory claim. It does not mean a defect was reproduced on a device. **Needs runtime verification** means layout, focus, delivery or provider behavior cannot be established from this review. Severity reflects impact on user control: P1 for access/privacy or lost settings, P2 for recovery/accessibility and misleading state, P3 for smaller clarity defects. These are review priorities, not a user-approved implementation order.

## Route and state coverage

Every file in `Features/Onboarding` and `Features/Settings` was read, together with the relevant auth, push, contacts, storage and shared-control paths.

| Surface / route | Entry and states covered | Current useful behavior | Audit outcome |
|---|---|---|---|
| Onboarding premise | No authenticated mailbox; example; Connect a mailbox | Example is explicitly labeled rather than presented as the user's mail | Fixed non-scroll layout needs stress testing; sample narrative remains static |
| Provider picker | Gmail, disabled Outlook/Yahoo | Unsupported providers are visibly marked `not yet` | No Back action in this step; redundant choice for a Gmail-only product is a product decision |
| Permission primer | Gmail scope explanation; Continue; What we store | Explains read/send/label/photo access before OAuth | Broad mailbox permission is incompletely described; optional photos are bundled into the initial request |
| Connecting | System OAuth; app waiting state | Uses the system authentication session; app does not handle passwords | No app retry/cancel/long-wait state after the system sheet; startup failure path can hang |
| Cancelled / failed connection | Try again; choose different provider; error detail | Cancellation is treated differently from an exception | Fixed heading still treats all failures as an unfinished user action; distinct failure/consent outcomes need clarity |
| What we store before login | NavigationLink from primer, native Back | Privacy disclosure is reachable before consent | Same disclosure omissions and disconnect promise as signed-in route |
| Settings root / You tab | One–three mailbox rows; four-plus collapsed list; Add; all settings links | Groups by user decisions; derived values; native tab access | Notification summary can become stale; all unsubscribe runs counted as successes; add failure silent |
| Mailboxes list | Up to six flat rows; seven-plus search/status groups; empty search; Add | Search and attention grouping exist; long addresses preserve identifying ends | Per-account row still pushes through list/detail; busy/error feedback absent for add |
| Mailbox detail | Active/reconnect status; tag editor; include toggle; disconnect | Live mailbox status; collision feedback; consequence copy is visible | Access termination promise unsupported; tag save/validation issues; exclusions not persisted |
| Reconnect | Mailbox detail and Google-photo consent links | Reuses system OAuth and keeps other accounts available | Generic account chooser can return a different account; requested mailbox not validated |
| Feed settings | Mailbox toggles for two–five; chooser for six-plus; See old posts | Explains read-in-place; old-post preference is explicit | Inclusion resets on cold start; zero-selection policy differs across entry points |
| Mailbox filter sheet | Search; All; multi-select; no matches; Apply | Draft choice applied by the footer; at least one required here | No explicit Cancel/Close; gesture dismissal and keyboard/focus need verification |
| AI settings | Counts for current feed; pending; failure; disclosure link | Presents facts instead of unsupported AI switches; explains raw-mail fallback | Uninterpreted history is outside the displayed classification counts; scope can look more complete than it is |
| Notifications | Unknown, not asked, authorized, provisional/ephemeral, denied; system Settings roundtrip | Reads OS permission; detail refreshes on app return; explains badge scope | Unknown equals not-asked in copy; provisional equals ON; permission and delivery readiness conflated |
| Senders | Empty; running/terminal runs; Clear; inspect receipt sheet | Shows actual run status rows | Header/count/empty copy conflates attempts with completed unsubscribes; clear has no distinction from cancel |
| Privacy / Google photos | Global enabled; per-account missing scopes; fetch failure; Retry | Exact-address matching; read-only email/photo fields; server does not receive address book through this path | On/off differs from granted/revoked; partial access explanation and progress could be clearer |
| Privacy / phone contacts | Off; first permission; full/limited grant; denial; OS settings return | Separate optional device permission; initials fallback; requests photos locally | Denial link only appears after a toggle attempt; limited scope not explained in UI |
| Privacy / rich links | Off by default; enable; existing mounted cards | Disclosure describes direct destination fetch | Existing LinkCard state does not react fully to preference changes |
| Export posts / system share | Loaded-post count; serialization; file write; share | Correctly labels local subset and JSON format; native share sheet | Serialization/write failures silently return; no progress/result/error state |
| Clear local interpretations | Second-tap confirmation; clear caches | Distinguishes local copies from provider mail; invalidates in-flight cache work | Confirmation remains armed without cancel; actual scope includes more than the row names |
| What we store after login | Privacy and AI links | Shared disclosure content prevents route drift | Server storage and access lifecycle incomplete; model-provider practice unverified |
| About | Version/build; product explanation | Real bundle version/build shown | No functional issue found in this source pass |

Primary route sources: [OnboardingFlow](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Onboarding/OnboardingFlow.swift:12), [SettingsView](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsView.swift:13), [MailboxesView](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/MailboxesView.swift:12), [MailboxDetailView](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/MailboxDetailView.swift:15), [SettingsFeedView](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsFeedView.swift:15), [SettingsAIView](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsAIView.swift:14), [SettingsNotificationsView](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsNotificationsView.swift:12), [SettingsSendersView](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsSendersView.swift:12), [SettingsPrivacyView](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsPrivacyView.swift:11).

## Confirmed source-backed defects and gaps

### P1 — Disconnect does not end the server's access as promised

Mailbox detail says disconnect ends access. What we store says disconnect deletes tokens on the device and sync server. The actual action dismisses immediately while `FeedStore.remove` runs an asynchronous task: it attempts push-token removal, clears local content, disconnects local SSE and removes Keychain credentials. The server endpoint only clears `push_token`. No server credential deletion, provider-token revocation, worker shutdown or Gmail-watch stop exists in that path. Persisted users retain refresh tokens, and startup resumes workers for all users.

This is a concrete mismatch between the user-visible promise and the implementation. It is not proof that a particular disconnected account was subsequently processed; that would need an isolated integration test. Offline push deregistration is additionally swallowed with `try?`, so even notification removal is not confirmed before the local credential is discarded.

Evidence: [disconnect copy/action](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/MailboxDetailView.swift:67), [token disclosure](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsPrivacyView.swift:198), [remove implementation](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:1109), [push removal route](/Users/craigroberts/email-ai/server/index.js:790), [retained credentials](/Users/craigroberts/email-ai/server/userStore.js:4), [worker restart](/Users/craigroberts/email-ai/server/index.js:2052).

The unresolved product choice is whether **Remove from this device**, **Stop server access**, and **Delete stored data** are separate operations or one explicit disconnect transaction. Those promises need an agreed backend contract before changing reassuring copy.

### P1 — Feed exclusions reset on a cold launch

`setIncluded` only changes the in-memory mailbox and restarts the feed session. Initial construction calls `syncMailboxes`, which creates every account with `includeInUnifiedFeed: true`; no inclusion preference is read or saved in these paths. Someone excluding work mail can therefore see it return when the process restarts. This is especially significant because the UI presents inclusion as a setting, not a temporary filter.

Evidence: [preference mutation](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:1143), [initial construction](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:419), [default restoration](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:1086). Verify with a synthetic multi-account cold-start test; no real account setting was changed here.

### P2 — Storage disclosure omits the server's retained mail data

The `YOUR MAIL` paragraph describes seven-day device caching. The server schema retains sender, subject, snippet, quote, summary and other message fields; source inspection also persists body text. The disclosure mentions server-held tokens but does not explain this retained message data, its retention period or how to remove it. Local cache clearing is correctly scoped in its action row, but it is not server erasure. The broad Settings footer, “Nothing leaves it without you pressing something,” is also ambiguous beside automatic background sync and server/model processing.

Evidence: [storage facts](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsPrivacyView.swift:188), [Settings footer](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsView.swift:57), [message schema](/Users/craigroberts/email-ai/server/schema.sql:23), [persisted source text](/Users/craigroberts/email-ai/server/messageStore.js:102). Hosting encryption, provider training/retention terms, backup handling and deployed retention policies were not verified; source alone cannot establish those claims.

### P2 — Consent names a narrower capability than the OAuth request

The primer promises to explain exactly what Google asks for, but describes read, send and change labels while requesting the broad `https://mail.google.com/` scope. The code's own primer comment recognizes that this includes deletion. The screen also states that photos are optional, while both contact scopes are included in every initial/reconnect request and Google photos default on after authorization. Granular refusal may still work through Google's consent UI; this pass did not test it. There is no app-level “Continue without photos” branch before OAuth.

Evidence: [primer](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Onboarding/OnboardingFlow.swift:113), [scope rationale](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Onboarding/OnboardingFlow.swift:8), [requested scopes](/Users/craigroberts/email-ai/apple/DecisionInbox/Services/AuthService.swift:36), [photo default](/Users/craigroberts/email-ai/apple/DecisionInbox/Services/SenderIdentityStore.swift:39). Product choice: one consolidated consent moment versus asking for optional enrichment when its benefit is visible. Do not infer permission revocation from turning local photo use off.

### P2 — Connection recovery loses the intended account and the error

Settings Add and Reconnect call async methods without rendering `auth.lastError`; only onboarding consumes that property. Add disables while connecting but provides no visible busy/result label. Reconnect has no matching disabled state. `reconnect(target)` accepts any non-nil result from a generic Google account chooser and then reloads the original target, ignoring the connected account's returned ID. Selecting another account can leave the requested mailbox broken and add an unintended one. “Reconnecting takes one tap” also overpromises a provider-controlled consent flow.

Evidence: [add/reconnect paths](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:1100), [target mismatch](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:1151), [generic account picker](/Users/craigroberts/email-ai/apple/DecisionInbox/Services/AuthService.swift:88), [reconnect control](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/MailboxDetailView.swift:59), [error consumer](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Onboarding/OnboardingFlow.swift:203).

There is also a source-level stall path: the return value of `ASWebAuthenticationSession.start()` is ignored inside a checked continuation. If starting the session fails without a callback, Connecting has no resolution. The main onboarding has no back action on provider/primer, no long-wait recovery, and one cancellation heading for all exceptions. These source omissions are confirmed; device/provider reproduction remains pending. [Session start](/Users/craigroberts/email-ai/apple/DecisionInbox/Services/AuthService.swift:95), [step navigation](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Onboarding/OnboardingFlow.swift:25).

### P2 — Notification status states are too broad, and the first-permission CTA takes an indirect route

The detail maps `.provisional` and `.ephemeral` to ON, without separately inspecting alert, sound or badge settings. Unknown and not-asked share copy asserting that the user has not been asked. Both use “Turn notifications on” to open general app Settings instead of invoking `requestIfUndecided`. The app separately requests authorization after `store.start()` and on foreground return, so the Settings action does not own the operation its wording implies.

The root Settings summary only fetches permission in `.task`; the detail has an explicit scene-phase refresh. Returning from system Settings through the detail can leave the still-mounted root summary stale. Push submission errors are swallowed and APNs-registration failure is silent, so ON establishes OS authorization, not working remote delivery.

Evidence: [notification UI/state mapping](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsNotificationsView.swift:19), [root status fetch](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsView.swift:64), [request timing](/Users/craigroberts/email-ai/apple/DecisionInbox/App/RootView.swift:69), [permission and submission](/Users/craigroberts/email-ai/apple/DecisionInbox/Services/PushService.swift:25), [silent registration failure](/Users/craigroberts/email-ai/apple/DecisionInbox/Services/PushService.swift:119).

The “receipts, promotions and newsletters stay silent” sentence is more categorical than the current contract's conditional attention rule. Local permission, server registration, alert eligibility and actual delivery need separate language; Focus/Summary and physical APNs delivery remain runtime checks, not inferred failures.

### P2 — Destructive confirmation has no explicit way to back out

`ConsequenceRow` changes its button to “Tap again…” and retains `confirming` until another tap executes the action or the view is destroyed. There is no Cancel affordance or explicit disarm on changing focus. A later tap can commit an old decision. The consequence is included in the accessibility hint, which is useful, but the interaction lacks a clear exit state.

This affects disconnect and local cache clearing. Disconnect also dismisses before its asynchronous cleanup completes. Clear removes conversations, identities, images, unsubscribe records and receipts in addition to the named cached posts/opened messages; the description could state the broader local-cache scope.

Evidence: [ConsequenceRow](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsChrome.swift:168), [clear action](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsPrivacyView.swift:106), [clear scope](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:466). Native confirmation dialog versus inline confirmation with explicit Cancel is a choice about clarity versus interruption, not an invitation to add another arbitrary tap.

### P2 — Zero-mailbox selection works differently at different account counts

The small-list toggles and mailbox detail allow every mailbox to be excluded. The six-plus filter sheet refuses an empty selection. Its comment says empty selection falls back to all mail; current `feedingIDs` actually returns an empty set. This is a confirmed inconsistent policy and stale rationale. Whether an all-hidden feed renders as a misleading completed inbox requires runtime verification.

Evidence: [small-list toggles](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsFeedView.swift:39), [sheet refusal](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsFeedView.swift:150), [current filter](/Users/craigroberts/email-ai/apple/DecisionInbox/Model/FeedStore.swift:518). Decide whether no selected mailboxes is permitted; if permitted it needs “No mailboxes selected,” not an inbox-completion claim.

### P2 — Sender settings report attempts as completed unsubscribes

The root displays `store.unsubscribes.count` as UNSUBSCRIBED. The Senders page uses the same heading for queued, failed, needs-you and completed records. Its caption promises later-mail monitoring, and its empty copy implies durable history, while the store is an in-memory run dictionary. Clear removes that dictionary without distinguishing clearing local records from stopping an agent. The inspected receipt is a snapshot of the selected status, rather than a live lookup.

Evidence: [root count](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsView.swift:129), [Senders collection, copy and clear](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsSendersView.swift:25), [receipt presentation](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsSendersView.swift:86). The [dedicated unsubscribe audit](/Users/craigroberts/email-ai/product_docs/unsubscribe-experience-audit-2026-09-19.md:1) owns the full proposed state/action model; this is the settings entry-point dependency.

### P2 — Shared settings motion bypasses the reduced-motion resolver

Toggle changes, filter selection, confirmation changes, clear and sender-history clear directly invoke spring tokens without reading `accessibilityReduceMotion`. The existing `Move.resolved` policy replaces travel/springs with crossfade, but these paths do not use it. Onboarding's short crossfade already avoids spatial motion. `TapStyle` elsewhere correctly gates scale.

Evidence: [SettingsToggle and confirmation](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsChrome.swift:102), [filter selection](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsFeedView.swift:189), [native resolver](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Tokens.swift:626), [accessible press style](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/Controls.swift:48). Actual discomfort or animation duration was not measured. Preserving immediate state feedback does not require a spring translation.

### P3 — Tag editing can suggest an impossible correction and silently discard short input

Collision suggestions include `normalised + "2"` without enforcing four characters. A four-character collision can offer a five-character suggestion; selecting it is immediately truncated back to the colliding four characters. Inputs shorter than two characters silently fail to commit on blur, submit or leaving the screen, with no visible validation explanation or saved state. The accessibility label says letters although digits are accepted.

Evidence: [suggestion generation](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/MailboxDetailView.swift:102), [commit guard](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/MailboxDetailView.swift:126), [input normalization](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/MailboxDetailView.swift:143).

### P3 — Export can do nothing, and rich-link preference changes can leave stale content

Export silently returns if JSON creation or file writing fails. A user sees the button accept a tap with no outcome or recovery. For link previews, `.task` runs once behind a `resolved` flag. Turning the preference off does not clear already-loaded metadata in a mounted LinkCard; turning it on does not restart that card's completed task. This is a source-level reactivity gap. It does not establish a new network fetch after opt-out, because that needs transport observation.

Evidence: [export](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsPrivacyView.swift:135), [LinkCard task and display](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Messages/LinkCard.swift:30).

## Accessibility and usability risks requiring runtime verification

These are hypotheses with specific mechanisms, not invented user-test findings:

- **Onboarding overflow:** `hero` uses a non-scroll VStack with fixed 80-point top padding, full-size fixed-height text and two controls on the permission screen. Large Dynamic Type, landscape, smaller windows and keyboard/VoiceOver navigation need validation. No inspected onboarding code gives overflowing content a scroll route. [Hero layout](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Onboarding/OnboardingFlow.swift:225), [padding token](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Tokens.swift:481).
- **Truncated critical labels:** `ListRow` forces title and subtitle to one line. Dynamic fonts scale, but row text cannot wrap; long privacy controls, addresses, consent requests and recovery subtitles may truncate. Confirm actual screen-reader labels separately rather than assuming visual truncation removes their full accessibility text. [ListRow](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/Controls.swift:224).
- **Sheet exit/discovery:** MailboxFilterSheet relies on system dismissal and a custom visual grabber, with no explicit Close/Cancel and no dedicated accessibility escape action. It is not marked nondismissable, so “cannot dismiss” would be an unsupported claim here. Verify swipe, VoiceOver escape, pointer and hardware keyboard behavior with the search keyboard open. [Filter presentation](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsFeedView.swift:64), [chrome](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Components/Controls.swift:367).
- **Focus and announcements:** status changes, collision errors, contact permission rejection and action completion have no explicit focus/announcement mechanism in the reviewed screens. SwiftUI's implicit behavior may suffice in some cases; test it. The combined header and whole-row toggle semantics are useful existing foundations. [Settings accessibility](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsChrome.swift:83).
- **Small targets:** the filter ALL button and tag suggestion chips do not declare a 44-point minimum target. Measure actual hit rectangles at default and accessibility text sizes. Whole-row toggles already improve the tiny custom-switch target.
- **Permission accuracy:** local contact denial recovery is stateful only after trying the switch; limited Contacts access is supported by the service but not explicitly surfaced. Google photos ON describes a local preference, not necessarily all-account authorization. A revoked source, a partial grant, an empty result and a fetch failure must remain distinguishable. [Device contacts](/Users/craigroberts/email-ai/apple/DecisionInbox/Services/ContactPhotoStore.swift:17), [Google controls](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsPrivacyView.swift:45).
- **Haptic preference reachability:** `haptics.enabled` exists and gates the central vocabulary, but no UI consumer was found in the current native app. This is not evidence that system haptic controls are ignored. Whether to expose a dedicated app control remains a product choice. [Haptics](/Users/craigroberts/email-ai/apple/DecisionInbox/Design/Haptics.swift:20).
- **AI count interpretation:** counts describe the current visible session, not the full mailbox. A retained uninterpreted older email can be neither “read by model,” “being read,” nor “couldn't read.” The UI should not imply those rows form an exhaustive processing report. [AI count predicates](/Users/craigroberts/email-ai/apple/DecisionInbox/Features/Settings/SettingsAIView.swift:53).

## Interaction and motion opportunities

The recurring opportunity is **show the boundary of an action**: requested, waiting for someone else, confirmed, unavailable, or still needs you. An animation should not turn an unconfirmed permission or network write into an apparent success.

| Moment | Restrained concept | Expressive / signature alternative | Tradeoff and reduced-motion form |
|---|---|---|---|
| Explain the product before consent | Keep one labeled example and reveal quote versus interpretation on tap | A tiny interactive original-email → quote → implication specimen, driven by the user's tap | Faster explanation versus more setup time. Stable text and immediate emphasis/crossfade in reduced motion; no invented personal mail |
| Connect mailbox | Button acknowledges the tap, then explicit “Continue in Google” / “Finishing connection” / recovery states | Preserve the mailbox tag as an anchor from provider row into connected-account status | Continuity versus custom navigation complexity. A static identity anchor and text changes retain all meaning without travel |
| Photo consent | Each source/account shows available, permission needed, refreshing or unavailable | Preview the same sender's initials → authorized photo after the real lookup succeeds | Makes the benefit concrete but risks implying every Gmail photo is available. Crossfade only; initials always remain valid |
| Feed inclusion | Selection updates and a scoped receipt: “Work hidden from Feed” | Small visual preview of which mailbox streams remain in the feed | More immediate understanding versus extra UI and possible sensitive preview content. Static counts/tags suffice in reduced motion |
| Tag editing | Clear two–four-character requirement; local validation and an acknowledged saved state | Tag preview updates beside a sample post attribution as the user types | Learnability versus density. Never bounce or shake an error; show the exact reason and a usable correction |
| Disconnect / clear | Named consequence, explicit confirm/cancel, pending status and confirmed result | Account tile settles into a removed state only after the chosen access contract completes | Emotional reassurance must follow evidence. No celebration; opacity or immediate state replacement in reduced motion |
| Notification opt-in | Explain which mail earns attention; request permission on a deliberate action | A clearly labeled sample notification showing attention alert versus silent badge | More informed consent versus another setup step. Sample never claims delivery; no sound preview unless explicitly requested |
| Export | Preparing → native share sheet, with retry on failure | A brief document preparation state tied to the actual export result | Useful feedback versus overproducing a rare utility action. Static status is enough; no simulated percent complete |

All concepts can use current SwiftUI primitives. Existing ordinary success silence and independent haptic preference remain intact. A Rive/3D/AE asset has no necessary role in account control, consent or settings recovery. An optional interactive onboarding illustration would first need a specific explanatory task and a text-equivalent experience.

## Product choices still open

1. **What does disconnect mean?** Removing the device relationship is simple and can work locally; stopping server access protects the stronger promise but needs a reliable server lifecycle and retry policy. Deleting stored history adds another consequence. The decision depends on what the user expects to stop and what can be confirmed offline.
2. **When are optional photo permissions requested?** Bundling with mailbox consent reduces trips through Google but makes the first request broader. Contextual consent makes the benefit and optionality clearer but introduces a later step. The deciding criterion is understanding at the moment of authorization, not number of screens alone.
3. **Are feed filters persistent settings or temporary viewing choices?** Persistence supports boundaries such as leaving work mail out. Session-only filtering supports temporary focus, but needs a visible expiry/reset rule. The current Settings wording implies persistence.
4. **How much status belongs in settings?** A short control panel optimizes speed; expandable processing/delivery/access details improve diagnosis and trust. Show simple confirmed states first, and expose technical details only where the user can act on them.

These choices do not require changing the app's visual identity. They define which promises the UI is allowed to make.

## Verification plan for a later authorized implementation

Use synthetic fixtures and test accounts. Real disconnect, consent revocation, mail operations and permission changes are outside this audit.

| Area | Scenario | Evidence needed to pass |
|---|---|---|
| Onboarding layout | Smallest supported size, landscape/window resize, default and largest Dynamic Type | All copy and controls reachable without clipping; Back/Cancel paths obvious; no content hidden below screen |
| Authentication | Success, user cancel, provider error, network failure after consent, failed session start, repeated taps | Each attempt resolves once, preserves intended mailbox identity, shows recoverable failure and never claims nothing was shared without evidence |
| Reconnect identity | Choose target account, another existing account, a new account; cancel | Target is validated; mismatch explained; no silent substitution or unintended account addition |
| Add mailbox | One, three, four, six, seven-plus accounts; duplicate account | Correct list shape; busy state; success/recovery is visible; unaffected mailboxes remain usable |
| Disconnect contract | Online, offline, expired access token, server 500, process exit mid-operation, repeat retry | Chosen device/server/provider lifecycle is idempotent; retained server access is never called revoked; badge and remaining accounts reconcile |
| Inclusion persistence | Exclude one account, restart process, reconnect it, add another, exclude all | Preference matches agreed lifetime; zero-selection behavior consistent; feed, profile and badge scopes remain distinct |
| Tag editing | Empty/one character, two/four valid characters, digits, duplicate four-character tag, suggestion choice, blur/back | Valid values persist; invalid changes explain why; every suggestion is valid after normalization; assistive label matches accepted input |
| Notifications | Not asked, denied, authorized with banners off, badges off, provisional, app/settings roundtrip | Permission label states known scope; unknown remains unknown; root/detail agree; permission CTA performs the stated operation |
| Push readiness | Submission failure/retry, token renewal, new mailbox, foreground/background and cold tap on a physical device | Do not infer delivery from permission; one correct mailbox opens; no historical/duplicate alerts; confirmed badge aggregate retained on partial failure |
| Photo controls | Full/partial/missing/revoked Google scopes; Contacts full/limited/denied; preference off during pending fetch | Only permitted sources render; initials remain usable; no stale result reappears after opt-out; source/account recovery is actionable |
| Privacy content | Trace each displayed promise to API/data behavior | Device/server/model/destination scopes accurate; local clear distinguished from server deletion and provider access revocation |
| Rich links | Toggle off/on with card mounted; slow fetch; known tracker; return to existing thread | Agreed opt-out behavior applies to in-flight/displayed metadata; network evidence confirms no unintended new fetch |
| Export and clear | Empty/local subset, write failure, share dismissal; clear while refresh is in flight | Scope is explicit; failure recoverable; stale in-flight work cannot silently repopulate cleared cache; confirmed outcome visible |
| Senders | Mixed running/failed/needs-you/done; inspect while status changes; clear during active run | Attempt/outcome counts accurate; inspection updates; clearing history is never confused with stopping external work |
| Accessibility | VoiceOver, Switch Control, hardware keyboard, Increase Contrast, Reduce Motion, larger text | Correct role/value/label, predictable focus, errors announced, every action and dismissal reachable, spatial springs replaced without losing state |
| Performance | Multiple mailboxes, long addresses, repeated permission changes, large export fixture | No main-thread stall, uncontrolled layout movement, repeating feedback or lost scroll position; measure real device separately |

No runtime pass is claimed. This document was checked for complete route coverage and source-link validity; product state, permissions, delivery and layout still require the explicit checks above.
