// ─── Feed Store ───────────────────────────────────────────────────────────
//
// SLICE: Step 1 — Render-backed, user-scoped feed + skeleton-to-ready flow.
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
 * @param {string} userId  Stable Google sub claim
 * @param {string} id      Unique card ID
 */
function addPending(userId, id) {
  _cards(userId).set(id, { id, status: 'pending', data: null, createdAt: Date.now() });
}

/**
 * Transition a card from pending to ready with its interpreted data.
 * Called once async AI processing completes.
 * @param {string} userId
 * @param {string} id
 * @param {object} data  Interpreted card payload (same shape as /interpret-single response)
 */
function markReady(userId, id, data) {
  const map = _cards(userId);
  const existing = map.get(id);
  if (!existing) return;
  map.set(id, { ...existing, status: 'ready', data });
}

/**
 * Store the current session recap for a user.
 * Recap is a session intro — computed once per ingestion batch, not live-updated.
 * @param {string} userId
 * @param {object} recap
 */
function setRecap(userId, recap) {
  userRecaps.set(userId, recap);
}

/**
 * Return the full feed snapshot for a user, newest first.
 * Includes all cards regardless of seen state (seen filtering added in Step 3).
 * @param {string} userId
 * @returns {{ cards: FeedCard[], recap: object|null }}
 */
function getFeed(userId) {
  const sorted = Array.from(_cards(userId).values())
    .sort((a, b) => b.createdAt - a.createdAt);
  return { cards: sorted, recap: userRecaps.get(userId) ?? null };
}

module.exports = { addPending, markReady, setRecap, getFeed };
