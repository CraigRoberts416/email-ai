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

async function getUnread(userId) {
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
  `, [userId]);
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

async function setUnsubscribeUrl(userId, messageId, url) {
  await query(
    'UPDATE messages SET unsubscribe_url = $3 WHERE user_id = $1 AND message_id = $2',
    [userId, messageId, url]
  );
}

module.exports = {
  upsertMessages, getMessage, getUnread, getAll,
  getNextToProcess, setAiStatus, setAiField, setAiFields, updateLabelIds, setUnsubscribeUrl,
};
