'use strict';

const TERMINAL = new Set(['done', 'failed', 'needs_you', 'no_link', 'still_sending', 'unknown']);

function safePageURL(value) {
  try {
    const url = new URL(value);
    return ['http:', 'https:'].includes(url.protocol) && !url.username && !url.password ? url.href : null;
  } catch { return null; }
}

function recordStatus(previous, data, now = Date.now()) {
  const previousAttempt = previous?.attemptId || previous?.runId;
  const currentAttempt = data.attemptId || data.runId;
  const sameAttempt = Boolean(previousAttempt && previousAttempt === currentAttempt);
  // Progress can arrive after its final receipt, including within one clock tick.
  if (sameAttempt && TERMINAL.has(previous.status) && previous.status !== 'unknown' && !TERMINAL.has(data.status)) return previous;
  const history = sameAttempt ? [...(previous?.history || [])] : [];
  const last = history.at(-1);
  if (!last || last.status !== data.status || last.message !== data.message) {
    history.push({ status: data.status, message: data.message || null, at: now });
  }
  return {
    ...data,
    updatedAt: now,
    sourceURL: safePageURL(data.sourceURL) || previous?.sourceURL || null,
    handoffURL: safePageURL(data.handoffURL) || (sameAttempt ? previous?.handoffURL : null) || null,
    outcome: data.outcome || (sameAttempt ? previous?.outcome : null) || null,
    history: history.slice(-40),
  };
}

// A process restart is not a completed unsubscribe. Expose the last evidence
// and require inspection; never automatically repeat an uncertain submission.
function reconciledStatus(run, hasLiveWorker) {
  if (!run || TERMINAL.has(run.status) || hasLiveWorker) return run;
  return { ...run, status: 'unknown', step: 'unknown', outcome: 'outcome_unknown',
    message: 'The previous attempt stopped reporting. Check the sender’s page before trying again.' };
}

function createUnsubscribeJournal({ query }) {
  return {
    async save(userId, payload) {
      await query(`INSERT INTO unsubscribe_tasks (user_id, message_id, payload, updated_at)
        VALUES ($1, $2, $3::jsonb, to_timestamp($4 / 1000.0))
        ON CONFLICT (user_id, message_id) DO UPDATE
          SET payload = EXCLUDED.payload, updated_at = EXCLUDED.updated_at
          WHERE unsubscribe_tasks.updated_at <= EXCLUDED.updated_at
            AND NOT (
              COALESCE(unsubscribe_tasks.payload->>'attemptId', unsubscribe_tasks.payload->>'runId', '') =
                COALESCE(EXCLUDED.payload->>'attemptId', EXCLUDED.payload->>'runId', '')
              AND unsubscribe_tasks.payload->>'status' IN ('done', 'failed', 'needs_you', 'no_link', 'still_sending')
              AND EXCLUDED.payload->>'status' NOT IN ('done', 'failed', 'needs_you', 'no_link', 'still_sending', 'unknown')
            )`,
      [userId, payload.messageId, JSON.stringify(payload), payload.updatedAt]);
    },
    async list(userId) {
      const result = await query('SELECT payload FROM unsubscribe_tasks WHERE user_id = $1 ORDER BY updated_at DESC', [userId]);
      return result.rows.map(row => row.payload);
    },
    async get(userId, messageId) {
      const result = await query('SELECT payload FROM unsubscribe_tasks WHERE user_id = $1 AND message_id = $2', [userId, messageId]);
      return result.rows[0]?.payload || null;
    },
    async remove(userId, messageId, expectedPayload) {
      // Receipt removal is not cancellation. An intervening attempt or new
      // observation owns a different payload and must survive this deletion.
      const result = expectedPayload === undefined
        ? await query('DELETE FROM unsubscribe_tasks WHERE user_id = $1 AND message_id = $2 RETURNING message_id', [userId, messageId])
        : await query(`DELETE FROM unsubscribe_tasks WHERE user_id = $1 AND message_id = $2
            AND payload = $3::jsonb RETURNING message_id`, [userId, messageId, JSON.stringify(expectedPayload)]);
      return result.rows.length > 0;
    },
    async clear(userId) { await query('DELETE FROM unsubscribe_tasks WHERE user_id = $1', [userId]); },
  };
}

module.exports = { TERMINAL, safePageURL, recordStatus, reconciledStatus, createUnsubscribeJournal };
