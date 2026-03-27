// ─── Feed Store ───────────────────────────────────────────────────────────
//
// Card shape (flat — no `data` wrapper):
//   Static fields  — set at addPending time, never change
//   AI fields      — null until resolved, updated incrementally via updateAiField
//   status         — 'pending' | 'ready'
//
// Secondary index: userEmailIndex maps Gmail emailId → cardId so that
// All Mail can look up whether a given message has been AI-interpreted
// without scanning every card.
//
// TEMPORARY: Storage is in-memory. State is lost on server restart/redeploy.
// Replace Map operations with DB queries (Postgres/Redis) in Step 2.

const userCards      = new Map(); // userId → Map<cardId, FeedCard>
const userRecaps     = new Map(); // userId → recap
const userEmailIndex = new Map(); // userId → Map<emailId, cardId>

function _cards(userId) {
  if (!userCards.has(userId)) userCards.set(userId, new Map());
  return userCards.get(userId);
}

function _emailIndex(userId) {
  if (!userEmailIndex.has(userId)) userEmailIndex.set(userId, new Map());
  return userEmailIndex.get(userId);
}

/**
 * Add a new email card in the pending state for a user.
 * Populates the email index so All Mail can resolve interpretations by emailId.
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
    id,
    status: 'pending',
    createdAt: Date.now(),
    emailDate: Number.isFinite(emailMs) ? emailMs : Date.now(),
    emailId:            staticFields.emailId            ?? null,
    senderName:         staticFields.senderName         ?? '',
    senderEmail:        staticFields.senderEmail        ?? '',
    subject:            staticFields.subject            ?? '',
    date:               staticFields.date               ?? String(Date.now()),
    threadId:           staticFields.threadId           ?? null,
    threadMessageCount: staticFields.threadMessageCount ?? 1,
    avatarUri:          staticFields.avatarUri          ?? null,
    avatarFallbackText: staticFields.avatarFallbackText ?? '',
    quote:              null,
    summary:            null,
    action:             null,
    actionUrl:          null,
    requiresAttention:  false,
  });

  // Index by Gmail emailId so All Mail can look up interpretations
  if (staticFields.emailId) {
    _emailIndex(userId).set(staticFields.emailId, id);
  }
}

/**
 * Update a single AI field on a card as it streams in.
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
 */
function setRecap(userId, recap) {
  userRecaps.set(userId, recap);
}

/**
 * Return the full feed snapshot for a user, newest first.
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

/**
 * Look up whether a Gmail message has been AI-interpreted for a user.
 * Used by All Mail to decide whether to show the enriched or raw card.
 *
 * Returns the AI fields if the card is ready, null otherwise.
 * A pending card (still processing) returns null — All Mail shows raw until done.
 *
 * @param {string} userId
 * @param {string} emailId  Gmail message ID
 * @returns {{ quote, summary, action, actionUrl, requiresAttention } | null}
 */
function getInterpretation(userId, emailId) {
  if (!emailId) return null;
  const cardId = _emailIndex(userId)?.get(emailId);
  if (!cardId) return null;
  const card = _cards(userId).get(cardId);
  if (!card || card.status !== 'ready') return null;
  return {
    quote:             card.quote,
    summary:           card.summary,
    action:            card.action,
    actionUrl:         card.actionUrl,
    requiresAttention: card.requiresAttention,
  };
}

module.exports = { addPending, updateAiField, markReady, setRecap, getFeed, getInterpretation };
