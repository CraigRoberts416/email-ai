// ─── Feed Store ───────────────────────────────────────────────────────────
//
// SLICE: Step 1 — Render-backed, user-scoped feed + skeleton-to-ready flow.
//
// Card shape (flat — no `data` wrapper):
//   Static fields  — set at addPending time, never change
//   AI fields      — null until resolved, updated incrementally via updateAiField
//   status         — 'pending' | 'ready'
//
// TEMPORARY: Storage is in-memory. State is lost on server restart/redeploy.
// Replace Map operations with DB queries (Postgres/Redis) in Step 2.
// The public API is stable — callers do not change when storage is swapped.
//
// NOT YET IMPLEMENTED:
//   - Seen state (Step 3)
//   - Persistence across restarts (Step 2)
//   - Feed filtering to unseen-only (Step 3)

const userCards  = new Map(); // userId → Map<id, FeedCard>
const userRecaps = new Map(); // userId → recap

function _cards(userId) {
  if (!userCards.has(userId)) userCards.set(userId, new Map());
  return userCards.get(userId);
}

/**
 * Add a new email card in the pending state for a user.
 * Called immediately when an email notification arrives — before AI processing.
 * Static fields are stored directly on the card and sent to SSE clients so the
 * card can render a partially-populated state (sender, subject) before AI resolves.
 *
 * @param {string} userId       Stable Google sub claim
 * @param {string} id           Unique card ID
 * @param {object} staticFields Non-AI fields available immediately:
 *   emailDate, emailId, senderName, senderEmail, subject, date,
 *   threadId, threadMessageCount, avatarUri, avatarFallbackText
 */
function addPending(userId, id, staticFields) {
  const emailMs = Number(staticFields.emailDate);
  _cards(userId).set(id, {
    // Lifecycle
    id,
    status: 'pending',
    createdAt: Date.now(),
    emailDate: Number.isFinite(emailMs) ? emailMs : Date.now(),
    // Static fields
    emailId:            staticFields.emailId            ?? null,
    senderName:         staticFields.senderName         ?? '',
    senderEmail:        staticFields.senderEmail        ?? '',
    subject:            staticFields.subject            ?? '',
    date:               staticFields.date               ?? String(Date.now()),
    threadId:           staticFields.threadId           ?? null,
    threadMessageCount: staticFields.threadMessageCount ?? 1,
    avatarUri:          staticFields.avatarUri          ?? null,
    avatarFallbackText: staticFields.avatarFallbackText ?? '',
    // AI fields — null until streamed in
    quote:              null,
    summary:            null,
    action:             null,
    actionUrl:          null,
    requiresAttention:  false,
  });
}

/**
 * Update a single AI field on a card as it streams in.
 * Called for each field-complete event during streaming AI processing.
 * @param {string} userId
 * @param {string} id
 * @param {string} field  One of: quote, summary, action, actionUrl, requiresAttention
 * @param {*}      value  Parsed field value (string | null | boolean)
 */
function updateAiField(userId, id, field, value) {
  const map = _cards(userId);
  const existing = map.get(id);
  if (!existing) return;
  map.set(id, { ...existing, [field]: value });
}

/**
 * Transition a card from pending to ready.
 * Called once all AI fields have been streamed in.
 * @param {string} userId
 * @param {string} id
 */
function markReady(userId, id) {
  const map = _cards(userId);
  const existing = map.get(id);
  if (!existing) return;
  map.set(id, { ...existing, status: 'ready' });
}

/**
 * Store the current session recap for a user.
 * @param {string} userId
 * @param {object} recap
 */
function setRecap(userId, recap) {
  userRecaps.set(userId, recap);
}

/**
 * Return the full feed snapshot for a user, newest first.
 * @param {string} userId
 * @returns {{ cards: FeedCard[], recap: object|null }}
 */
function getFeed(userId) {
  const sorted = Array.from(_cards(userId).values())
    .sort((a, b) => {
      const diff = b.emailDate - a.emailDate;
      return diff !== 0 ? diff : b.createdAt - a.createdAt;
    });
  return { cards: sorted, recap: userRecaps.get(userId) ?? null };
}

module.exports = { addPending, updateAiField, markReady, setRecap, getFeed };
