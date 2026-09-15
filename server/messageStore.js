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
      values.push(`($${p},$${p+1},$${p+2},$${p+3},$${p+4},$${p+5},$${p+6},$${p+7},$${p+8},$${p+9},NOW(),$${p+10},$${p+11})`);
      params.push(
        userId, r.messageId, r.threadId ?? null, r.labelIds ?? [],
        r.subject ?? '', r.fromName ?? '', r.fromEmail ?? '',
        r.snippet ?? '', r.internalDate ?? 0, r.historyId ?? null,
        r.aiStatus ?? 'none', r.postCutoff ?? false,
      );
      p += 12;
    }
    await query(`
      INSERT INTO messages (
        user_id, message_id, thread_id, label_ids, subject,
        from_name, from_email, snippet, internal_date, history_id, synced_at,
        ai_status, post_cutoff
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

async function getUnread(userId, { limit = FEED_LIMIT } = {}) {
  const { rows } = await query(`
    SELECT * FROM messages
    WHERE user_id = $1 AND 'UNREAD' = ANY(label_ids)
    ORDER BY
      CASE
        WHEN 'UNREAD' = ANY(label_ids) AND post_cutoff = TRUE  THEN 1
        WHEN 'UNREAD' = ANY(label_ids) AND post_cutoff = FALSE THEN 2
        ELSE 3
      END,
      internal_date DESC
    LIMIT $2
  `, [userId, limit]);
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

module.exports = {
  upsertMessages, getMessage, getUnread, getAll,
  getNextToProcess, setAiStatus, failAttempt, setAiField, setAiFields, updateLabelIds,
  setUnsubscribeUrl, setImageUrl, getMessageIdsNeedingUnsubscribeBackfill,
  getMessageIdsNeedingImageBackfill, getMessageOwners,
  setRiskVerdict,
};
