const { query } = require('./db');

function rowToRecord(row) {
  return {
    messageId:         row.message_id,
    threadId:          row.thread_id,
    labelIds:          row.label_ids ?? [],
    subject:           row.subject,
    fromName:          row.from_name,
    fromEmail:         row.from_email,
    snippet:           row.snippet,
    internalDate:      Number(row.internal_date),
    historyId:         row.history_id,
    syncedAt:          row.synced_at,
    aiStatus:          row.ai_status,
    postCutoff:        row.post_cutoff,
    quote:             row.quote ?? null,
    summary:           row.summary ?? null,
    action:            row.action ?? null,
    actionUrl:         row.action_url ?? null,
    requiresAttention: row.requires_attention ?? false,
    unsubscribeUrl:    row.unsubscribe_url ?? null,
    riskLevel:         row.risk_level ?? 'none',
    riskEvidence:      row.risk_evidence ?? [],
    imageUrl:          row.image_url ?? null,
    participants:      row.participants ?? [],
    attachments:       row.attachments ?? [],
  };
}

async function upsertMessages(userId, records) {
  if (!records.length) return;
  const CHUNK = 100;
  for (let i = 0; i < records.length; i += CHUNK) {
    const slice = records.slice(i, i + CHUNK);
    const values = [];
    const params = [];
    let p = 1;
    for (const r of slice) {
      values.push(`($${p},$${p+1},$${p+2},$${p+3},$${p+4},$${p+5},$${p+6},$${p+7},$${p+8},$${p+9},NOW(),$${p+10},$${p+11},$${p+12})`);
      params.push(
        userId, r.messageId, r.threadId ?? null, r.labelIds ?? [],
        r.subject ?? '', r.fromName ?? '', r.fromEmail ?? '',
        r.snippet ?? '', r.internalDate ?? 0, r.historyId ?? null,
        r.aiStatus ?? 'none', r.postCutoff ?? false,
        JSON.stringify(r.participants ?? []),
      );
      p += 13;
    }
    await query(`
      INSERT INTO messages (
        user_id, message_id, thread_id, label_ids, subject,
        from_name, from_email, snippet, internal_date, history_id, synced_at,
        ai_status, post_cutoff, participants
      ) VALUES ${values.join(',')}
      ON CONFLICT (user_id, message_id) DO UPDATE SET
        thread_id     = EXCLUDED.thread_id,
        label_ids     = EXCLUDED.label_ids,
        subject       = EXCLUDED.subject,
        from_name     = EXCLUDED.from_name,
        from_email    = EXCLUDED.from_email,
        snippet       = EXCLUDED.snippet,
        internal_date = EXCLUDED.internal_date,
        history_id    = EXCLUDED.history_id,
        -- Only when the new row actually carries them: a metadata refresh
        -- that predates this column must not blank what is already stored.
        participants  = COALESCE(EXCLUDED.participants, messages.participants),
        synced_at     = NOW()
    `, params);
  }
}

async function getMessage(userId, messageId) {
  const { rows } = await query(
    'SELECT * FROM messages WHERE user_id = $1 AND message_id = $2',
    [userId, messageId]
  );
  return rows[0] ? rowToRecord(rows[0]) : null;
}

// The feed is finite by design — it ends, and ending is the product. A real
// mailbox can hold twenty thousand unread messages, which is an archive, not
// a feed: unbounded, it is megabytes of JSON nobody can read to the end of.
// All Mail is where the rest lives.
const FEED_LIMIT = 200;

/// Gmail's own category tabs, because the volume in a real mailbox is not
/// distributed the way attention is.
///
/// This mailbox has 207 unread in Primary and 3,677 in Promotions and Updates.
/// Ordering the feed purely by date gave Primary 25 of its 200 slots: the
/// person's actual correspondence was 12% of their own feed, and everything
/// they recognised was buried under retailers. That is the entire "this
/// doesn't look like my inbox" complaint, and no amount of card design fixes
/// it — the wrong mail was being selected.
///
/// Slots are budgeted per tier and the result is still sorted by date, so the
/// feed stays chronological. Promotions are not excluded; they simply cannot
/// crowd out a reply from a human being.
const TIER_BUDGET = { 0: 130, 1: 45, 2: 35 };

const TIER_SQL = `CASE
  WHEN 'CATEGORY_PROMOTIONS' = ANY(label_ids)
    OR 'CATEGORY_SOCIAL' = ANY(label_ids)
    OR 'CATEGORY_FORUMS' = ANY(label_ids) THEN 2
  WHEN 'CATEGORY_UPDATES' = ANY(label_ids) THEN 1
  ELSE 0
END`;

async function getUnread(userId, { limit = FEED_LIMIT } = {}) {
  const { rows } = await query(`
    WITH scoped AS (
      SELECT *, ${TIER_SQL} AS tier
      FROM messages
      WHERE user_id = $1 AND 'UNREAD' = ANY(label_ids)
    ),
    ranked AS (
      SELECT *, row_number() OVER (
        PARTITION BY tier
        ORDER BY post_cutoff DESC, internal_date DESC
      ) AS rn
      FROM scoped
    )
    SELECT * FROM ranked
    WHERE (tier = 0 AND rn <= $3)
       OR (tier = 1 AND rn <= $4)
       OR (tier = 2 AND rn <= $5)
    ORDER BY post_cutoff DESC, internal_date DESC
    LIMIT $2
  `, [userId, limit, TIER_BUDGET[0], TIER_BUDGET[1], TIER_BUDGET[2]]);
  return rows.map(rowToRecord);
}

async function getAll(userId, { limit = 50, cursor } = {}) {
  const params = [userId, limit + 1];
  let sql = 'SELECT * FROM messages WHERE user_id = $1';
  if (cursor) {
    sql += ' AND internal_date < $3';
    params.push(Number(cursor));
  }
  sql += ' ORDER BY internal_date DESC LIMIT $2';

  const { rows } = await query(sql, params);
  const hasMore = rows.length > limit;
  const records = rows.slice(0, limit).map(rowToRecord);
  return {
    records,
    nextCursor: hasMore ? records[records.length - 1].internalDate : null,
  };
}

async function getNextToProcess(userId) {
  const { rows } = await query(`
    SELECT message_id FROM messages
    WHERE user_id = $1
      AND ai_status IN ('none', 'queued')
      AND ('UNREAD' = ANY(label_ids) OR post_cutoff = TRUE)
    ORDER BY
      CASE
        WHEN 'UNREAD' = ANY(label_ids) AND post_cutoff = TRUE  THEN 1
        WHEN 'UNREAD' = ANY(label_ids) AND post_cutoff = FALSE THEN 2
        WHEN post_cutoff = TRUE                                THEN 3
      END,
      internal_date DESC
    LIMIT 1
  `, [userId]);
  return rows[0]?.message_id ?? null;
}

/// Marks a failure and counts it in one statement, so the two can never
/// disagree about how many times this message has been tried.
async function failAttempt(userId, messageId) {
  await query(
    `UPDATE messages SET ai_status = 'error', ai_attempts = ai_attempts + 1
     WHERE user_id = $1 AND message_id = $2`,
    [userId, messageId]
  );
}

async function setAiStatus(userId, messageId, status) {
  await query(
    'UPDATE messages SET ai_status = $3 WHERE user_id = $1 AND message_id = $2',
    [userId, messageId, status]
  );
}

async function setAiField(userId, messageId, field, value) {
  const col = {
    quote:             'quote',
    summary:           'summary',
    action:            'action',
    actionUrl:         'action_url',
    requiresAttention: 'requires_attention',
  }[field];
  if (!col) return;
  await query(
    `UPDATE messages SET ${col} = $3 WHERE user_id = $1 AND message_id = $2`,
    [userId, messageId, value]
  );
}

async function setAiFields(userId, messageId, { quote, summary, action, actionUrl, requiresAttention }) {
  await query(`
    UPDATE messages SET
      quote = $3, summary = $4, action = $5,
      action_url = $6, requires_attention = $7, ai_status = 'done'
    WHERE user_id = $1 AND message_id = $2
  `, [userId, messageId, quote ?? null, summary ?? null, action ?? null, actionUrl ?? null, requiresAttention ?? false]);
}

async function updateLabelIds(userId, messageId, labelIds) {
  await query(
    'UPDATE messages SET label_ids = $3 WHERE user_id = $1 AND message_id = $2',
    [userId, messageId, labelIds]
  );
}

/// The sender's own picture for this message, as found in the HTML. Stored
/// raw; it is only ever handed out through the proxy.
async function setImageUrl(userId, messageId, url) {
  await query(
    'UPDATE messages SET image_url = $3 WHERE user_id = $1 AND message_id = $2',
    [userId, messageId, url]
  );
}

/// The files this message carried, as Gmail described them. Written once
/// during interpretation; the bytes are never stored.
async function setAttachments(userId, messageId, attachments) {
  await query(
    'UPDATE messages SET attachments = $3 WHERE user_id = $1 AND message_id = $2',
    [userId, messageId, JSON.stringify(attachments ?? [])]
  );
}

async function setUnsubscribeUrl(userId, messageId, url) {
  await query(
    'UPDATE messages SET unsubscribe_url = $3 WHERE user_id = $1 AND message_id = $2',
    [userId, messageId, url]
  );
}

/// The fraud verdict and the evidence behind it, written together so a card
/// can never print POSSIBLE SCAM with nothing to show the user when they tap
/// through to ask why.
async function setRiskVerdict(userId, messageId, { level, evidence }) {
  await query(
    'UPDATE messages SET risk_level = $3, risk_evidence = $4 WHERE user_id = $1 AND message_id = $2',
    [userId, messageId, level ?? 'none', JSON.stringify(evidence ?? [])]
  );
}

/// Messages already interpreted before image extraction existed. Scoped to
/// what the feed actually draws on and capped, because each one costs a Gmail
/// round trip for the full body — the whole backlog would be tens of thousands
/// of fetches to decorate mail nobody will scroll to.
/// Every account holding a message with this id. Used to verify a signed
/// image URL without the id of the person it belongs to appearing in it.
/// Practically always one row.
async function getMessageOwners(messageId) {
  const { rows } = await query(
    'SELECT user_id FROM messages WHERE message_id = $1',
    [messageId]
  );
  return rows.map(r => r.user_id);
}

async function getMessageIdsNeedingImageBackfill(userId, limit = 1200) {
  const { rows } = await query(`
    SELECT message_id FROM messages
    WHERE user_id = $1 AND image_url IS NULL
      AND ai_status = 'done' AND post_cutoff = TRUE
    ORDER BY internal_date DESC
    LIMIT $2
  `, [userId, limit]);
  return rows.map(r => r.message_id);
}

async function getMessageIdsNeedingUnsubscribeBackfill(userId) {
  const { rows } = await query(
    'SELECT message_id FROM messages WHERE user_id = $1 AND unsubscribe_url IS NULL',
    [userId]
  );
  return rows.map(r => r.message_id);
}

/**
 * Which of these Gmail ids this mailbox cannot answer for.
 *
 * Two kinds, and the caller treats them the same because the remedy is the
 * same — fetch the metadata and upsert:
 *
 *   - never stored, because the history stream missed it
 *   - stored before `participants` existed, so nothing knows who else was on
 *     it. 126,000 rows are in that state, and a sent message with no
 *     recipients recorded cannot be placed in any conversation at all.
 */
async function unreconciled(userId, messageIds) {
  if (!messageIds.length) return [];
  const { rows } = await query(`
    SELECT id FROM unnest($2::text[]) AS id
    WHERE NOT EXISTS (
      SELECT 1 FROM messages m
      WHERE m.user_id = $1 AND m.message_id = id
        AND m.participants IS NOT NULL
    )
  `, [userId, messageIds]);
  return rows.map(r => r.id);
}

async function queueNotifications(userId, messageIds) {
  if (!messageIds.length) return;
  await query(`
    UPDATE messages m SET notification_pending = TRUE
    FROM users u
    WHERE m.user_id = $1 AND u.user_id = m.user_id
      AND m.message_id = ANY($2::text[]) AND m.post_cutoff = TRUE
      AND 'UNREAD' = ANY(m.label_ids) AND m.notification_sent_at IS NULL
      AND m.internal_date >= EXTRACT(EPOCH FROM u.notifications_started_at) * 1000
  `, [userId, messageIds]);
}

async function getPendingNotifications(userId) {
  const { rows } = await query(`
    SELECT m.* FROM messages m JOIN users u USING (user_id)
    WHERE m.user_id = $1 AND m.notification_pending = TRUE
      AND m.notification_sent_at IS NULL AND m.requires_attention = TRUE
      AND m.ai_status = 'done' AND 'UNREAD' = ANY(m.label_ids)
      AND m.internal_date >= EXTRACT(EPOCH FROM u.notifications_started_at) * 1000
      AND m.internal_date >= EXTRACT(EPOCH FROM NOW() - INTERVAL '24 hours') * 1000
    ORDER BY m.internal_date ASC LIMIT 50
  `, [userId]);
  return rows.map(rowToRecord);
}

async function claimNotification(userId, messageId) {
  const { rows } = await query(`
    UPDATE messages SET notification_claimed_at = NOW()
    WHERE user_id = $1 AND message_id = $2 AND notification_pending = TRUE
      AND notification_sent_at IS NULL AND requires_attention = TRUE
      AND 'UNREAD' = ANY(label_ids)
      AND (notification_claimed_at IS NULL OR notification_claimed_at < NOW() - INTERVAL '2 minutes')
    RETURNING message_id
  `, [userId, messageId]);
  return rows.length > 0;
}

async function finishNotification(userId, messageId, delivered) {
  await query(`
    UPDATE messages SET notification_claimed_at = NULL,
      notification_sent_at = CASE WHEN $3 THEN NOW() ELSE notification_sent_at END,
      notification_pending = CASE WHEN $3 THEN FALSE ELSE notification_pending END
    WHERE user_id = $1 AND message_id = $2
  `, [userId, messageId, delivered]);
}

module.exports = {
  upsertMessages, getMessage, getUnread, getAll, unreconciled,
  getNextToProcess, setAiStatus, failAttempt, setAiField, setAiFields, updateLabelIds,
  setUnsubscribeUrl, setImageUrl, setAttachments, getMessageIdsNeedingUnsubscribeBackfill,
  getMessageIdsNeedingImageBackfill, getMessageOwners,
  setRiskVerdict,
  queueNotifications, getPendingNotifications, claimNotification, finishNotification,
};
