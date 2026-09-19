const { query } = require('./db');
const { CARD_COLUMNS, createFeedStorage } = require('./feedStorage');

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
      values.push(`($${p},$${p+1},$${p+2},$${p+3},$${p+4},$${p+5},$${p+6},$${p+7},$${p+8},$${p+9},NOW(),$${p+10},$${p+11},$${p+12},$${p+13})`);
      params.push(
        userId, r.messageId, r.threadId ?? null, r.labelIds ?? [],
        r.subject ?? '', r.fromName ?? '', r.fromEmail ?? '',
        r.snippet ?? '', r.internalDate ?? 0, r.historyId ?? null,
        r.aiStatus ?? 'none', r.postCutoff ?? false,
        JSON.stringify(r.participants ?? []),
        r.labelsObservedAt ?? new Date(),
      );
      p += 14;
    }
    await query(`
      INSERT INTO messages (
        user_id, message_id, thread_id, label_ids, subject,
        from_name, from_email, snippet, internal_date, history_id, synced_at,
        ai_status, post_cutoff, participants, labels_updated_at
      ) VALUES ${values.join(',')}
      ON CONFLICT (user_id, message_id) DO UPDATE SET
        thread_id     = EXCLUDED.thread_id,
        label_ids     = CASE WHEN EXCLUDED.labels_updated_at >= messages.labels_updated_at
          THEN EXCLUDED.label_ids ELSE messages.label_ids END,
        labels_updated_at = GREATEST(messages.labels_updated_at, EXCLUDED.labels_updated_at),
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
    `, params, { mailboxWriteUserId: userId });
  }
}

async function getMessage(userId, messageId) {
  const { rows } = await query(
    'SELECT * FROM messages WHERE user_id = $1 AND message_id = $2',
    [userId, messageId]
  );
  return rows[0] ? rowToRecord(rows[0]) : null;
}

const feedStorage = createFeedStorage({ query, toRecord: rowToRecord });
const getUnreadPage = feedStorage.page;
const getUnreadCounts = feedStorage.counts;
async function getMessagesByIds(userId, ids) {
  if (!ids.length) return [];
  const { rows } = await query(`SELECT ${CARD_COLUMNS.join(', ')} FROM messages
    WHERE user_id = $1 AND message_id = ANY($2::text[])`, [userId, ids]);
  return rows.map(rowToRecord);
}
async function getHistoryPageRecords(userId, ids) {
  if (!ids.length) return [];
  const { rows } = await query(`SELECT ${CARD_COLUMNS.join(', ')},
      (body_text IS NOT NULL AND attachments IS NOT NULL AND image_url IS NOT NULL AND source_version >= 2) AS source_inspected,
      CASE WHEN ai_status <> 'done' THEN LEFT(body_text, 8000) ELSE NULL END AS original_text
    FROM messages WHERE user_id = $1 AND message_id = ANY($2::text[])`, [userId, ids]);
  return rows.map(row => ({ ...rowToRecord(row), sourceInspected: row.source_inspected, originalText: row.original_text }));
}
async function saveProfileSource(userId, messageId, { bodyText, attachments, imageUrl = null }) {
  await query(`UPDATE messages SET body_text = COALESCE(body_text, $3),
    attachments = $4::jsonb, image_url = COALESCE($5, image_url), source_version = 2
    WHERE user_id = $1 AND message_id = $2`,
  [userId, messageId, bodyText, JSON.stringify(attachments), imageUrl]);
}
async function getUnread(userId, options) { return (await getUnreadPage(userId, options)).records; }

async function unreadMetadataNeeded(userId, ids) {
  if (!ids.length) return [];
  const { rows } = await query(`
    SELECT id FROM unnest($2::text[]) AS id WHERE NOT EXISTS (
      SELECT 1 FROM messages WHERE user_id = $1 AND message_id = id AND 'UNREAD' = ANY(label_ids)
    )
  `, [userId, ids]);
  return rows.map(row => row.id);
}

async function reconcileUnreadLabels(userId, ids, startedAt, excluded = {}) {
  await query(`
    UPDATE messages SET
      label_ids = CASE WHEN message_id = ANY($2::text[]) THEN
        array_remove(array_remove(array_remove(label_ids, 'UNREAD'), 'SPAM'), 'TRASH')
        || ARRAY['UNREAD']::text[]
        || CASE WHEN message_id = ANY($4::text[]) THEN ARRAY['SPAM']::text[] ELSE '{}'::text[] END
        || CASE WHEN message_id = ANY($5::text[]) THEN ARRAY['TRASH']::text[] ELSE '{}'::text[] END
        ELSE array_remove(label_ids, 'UNREAD') END,
      labels_updated_at = $3::timestamptz
    WHERE user_id = $1 AND labels_updated_at <= $3::timestamptz
      AND ('UNREAD' = ANY(label_ids) OR message_id = ANY($2::text[]))
  `, [userId, ids, startedAt, excluded.SPAM ?? [], excluded.TRASH ?? []], { mailboxWriteUserId: userId });
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
    'UPDATE messages SET label_ids = $3, labels_updated_at = NOW() WHERE user_id = $1 AND message_id = $2',
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
    // Source inspection may have found more files than a bounded card preview.
    // A later worker/People preview must not discard those immutable Gmail IDs.
    // Merge in one statement so parallel inspections cannot lose each other's
    // metadata; fresh metadata wins for an ID present in both arrays.
    `UPDATE messages m SET attachments = (
      SELECT COALESCE(jsonb_agg(value ORDER BY source, ordinality), '[]'::jsonb) FROM (
        SELECT DISTINCT ON (value->>'id') value, source, ordinality FROM (
          SELECT value, ordinality, 0 AS source FROM jsonb_array_elements($3::jsonb) WITH ORDINALITY
          UNION ALL
          SELECT value, ordinality, 1 AS source
            FROM jsonb_array_elements(COALESCE(m.attachments, '[]'::jsonb)) WITH ORDINALITY
        ) entries ORDER BY value->>'id', source, ordinality
      ) merged
    ) WHERE user_id = $1 AND message_id = $2`,
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
  `, [userId, messageIds], { mailboxWriteUserId: userId });
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
  upsertMessages, getMessage, getMessagesByIds, getHistoryPageRecords, saveProfileSource,
  getUnread, getUnreadPage, getUnreadCounts, getAll, unreconciled,
  unreadMetadataNeeded, reconcileUnreadLabels,
  getNextToProcess, setAiStatus, failAttempt, setAiField, setAiFields, updateLabelIds,
  setUnsubscribeUrl, setImageUrl, setAttachments, getMessageIdsNeedingUnsubscribeBackfill,
  getMessageIdsNeedingImageBackfill, getMessageOwners,
  setRiskVerdict,
  queueNotifications, getPendingNotifications, claimNotification, finishNotification,
};

// Only called for Gmail messageDeleted history events; this removes the local
// mirror, never the provider message. The account scope is mandatory.
async function removeMessages(userId, ids) {
  if (ids.length) await query('DELETE FROM messages WHERE user_id = $1 AND message_id = ANY($2::text[])',
    [userId, ids], { mailboxWriteUserId: userId });
}
module.exports.removeMessages = removeMessages;


async function markAllMailSeen(userId, ids, generation) {
  if (ids.length) await query(`UPDATE messages SET all_mail_sync_generation = $3
    WHERE user_id = $1 AND message_id = ANY($2::text[])`, [userId, ids, generation], { mailboxWriteUserId: userId });
}

// Pruning runs only after every provider page has been imported successfully.
// Gmail's default inventory omits Spam/Trash, so keep those rows for unread
// accounting. Concurrent arrivals or label changes also survive this snapshot.
async function reconcileAllMail(userId, generation, startedAt) {
  await query(`DELETE FROM messages WHERE user_id = $1
    AND all_mail_sync_generation IS DISTINCT FROM $2
    AND first_synced_at < $3 AND labels_updated_at < $3
    AND NOT (COALESCE(label_ids, '{}') && ARRAY['SPAM', 'TRASH']::text[])`,
  [userId, generation, startedAt], { mailboxWriteUserId: userId });
}
module.exports.markAllMailSeen = markAllMailSeen;
module.exports.reconcileAllMail = reconcileAllMail;
