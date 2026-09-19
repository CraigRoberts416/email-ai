const PAGE_SIZE = 200;

function badRequest(message) {
  return Object.assign(new Error(message), { statusCode: 400 });
}

function feedOptions(userId, { cursor, limit = PAGE_SIZE, timeZone = 'UTC', sectionDate, knownMessageIds } = {}, now = new Date()) {
  if (!/^\d+$/.test(String(limit)) || Number(limit) < 1 || Number(limit) > PAGE_SIZE) {
    throw badRequest('limit must be an integer from 1 to 200');
  }
  if (typeof timeZone !== 'string' || timeZone.length > 100 || timeZone.includes(':')) throw badRequest('invalid timeZone');
  try { timeZone = new Intl.DateTimeFormat('en', { timeZone }).resolvedOptions().timeZone; }
  catch { throw badRequest('invalid timeZone'); }
  if (knownMessageIds !== undefined && typeof knownMessageIds !== 'string') throw badRequest('invalid knownMessageIds');
  const knownIds = knownMessageIds ? knownMessageIds.split(',') : [];
  if (knownIds.length > 500 || knownIds.some(id => !/^[A-Za-z0-9_-]{1,256}$/.test(id))) {
    throw badRequest('knownMessageIds must contain at most 500 message IDs');
  }
  let snapshot = now.toISOString();
  if (sectionDate !== undefined && (typeof sectionDate !== 'string' || !Number.isFinite(Date.parse(sectionDate)))) {
    throw badRequest('invalid sectionDate');
  }
  sectionDate = sectionDate ? new Date(sectionDate).toISOString() : snapshot;
  let before = null;
  if (cursor !== undefined && cursor !== null) {
    try {
      if (typeof cursor !== 'string' || cursor.length > 2048 || !/^[A-Za-z0-9_-]+$/.test(cursor)) throw Error();
      const value = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8'));
      if (value.v !== 1 || value.account !== userId || !Array.isArray(value.before)
        || value.before.length !== 2 || !Number.isSafeInteger(value.before[0]) || value.before[0] < 0
        || typeof value.before[1] !== 'string' || !value.before[1] || value.before[1].length > 256
        || typeof value.snapshot !== 'string' || !Number.isFinite(Date.parse(value.snapshot))
        || typeof value.sectionDate !== 'string' || !Number.isFinite(Date.parse(value.sectionDate))
        || value.timeZone !== timeZone) throw Error();
      snapshot = new Date(value.snapshot).toISOString();
      sectionDate = new Date(value.sectionDate).toISOString();
      before = value.before;
    } catch { throw badRequest('invalid feed cursor'); }
  }
  return { limit: Number(limit), timeZone, sectionDate, snapshot, before, knownIds: [...new Set(knownIds)], now: now.toISOString() };
}

function nextCursor(userId, scope, records, limit) {
  if (records.length <= limit) return null;
  const last = records[limit - 1];
  return Buffer.from(JSON.stringify({
    v: 1, account: userId, snapshot: scope.snapshot, sectionDate: scope.sectionDate, timeZone: scope.timeZone,
    before: [Number(last.internal_date), last.message_id],
  })).toString('base64url');
}

function createFeedStorage({ query, toRecord }) {
  async function read(userId, options, now, includeCards) {
    const scope = feedOptions(userId, options, now);
    // Counts and cards share one PostgreSQL statement snapshot. Counts cover
    // the full current unread set; the cursor only limits the card page. Keep
    // the page separate from the aggregate so its chronological index can
    // stop after limit+1 instead of sorting a materialized unread backlog.
    // Never select m.*: cached message bodies are large and are not card data.
    const pageCTE = includeCards ? `, page_ids AS (
        SELECT message_id, internal_date FROM messages
        WHERE user_id = $1 AND 'UNREAD' = ANY(label_ids)
          AND NOT ('SPAM' = ANY(label_ids)) AND NOT ('TRASH' = ANY(label_ids))
          AND first_synced_at <= $5::timestamptz
          AND ($6::bigint IS NULL OR (internal_date, message_id COLLATE "C") < ($6::bigint, $7::text COLLATE "C"))
        ORDER BY internal_date DESC, message_id COLLATE "C" DESC LIMIT $8
      ), page AS (
        SELECT m.message_id, m.thread_id, m.label_ids, m.subject, m.from_name,
          m.from_email, m.snippet, m.internal_date, m.history_id, m.synced_at,
          m.ai_status, m.post_cutoff, m.quote, m.summary, m.action, m.action_url,
          m.requires_attention, m.unsubscribe_url, m.risk_level, m.risk_evidence,
          m.image_url, m.participants, m.attachments
        FROM page_ids p JOIN messages m ON m.user_id = $1 AND m.message_id = p.message_id
      )` : '';
    const pageColumn = includeCards
      ? ", COALESCE((SELECT json_agg(page ORDER BY internal_date DESC, message_id COLLATE \"C\" DESC) FROM page), '[]'::json) AS records"
      : '';
    const params = [userId, scope.timeZone, scope.sectionDate, scope.knownIds];
    if (includeCards) params.push(scope.snapshot, scope.before?.[0] ?? null, scope.before?.[1] ?? null, scope.limit + 1);
    const { rows } = await query(`
      WITH boundaries AS MATERIALIZED (
        SELECT
          (EXTRACT(EPOCH FROM ((($3::timestamptz AT TIME ZONE $2)::date)::timestamp AT TIME ZONE $2)) * 1000)::bigint AS today,
          (EXTRACT(EPOCH FROM ((($3::timestamptz AT TIME ZONE $2)::date - 1)::timestamp AT TIME ZONE $2)) * 1000)::bigint AS yesterday
      ), unread AS (
        SELECT internal_date,
          NOT ('SPAM' = ANY(label_ids)) AND NOT ('TRASH' = ANY(label_ids)) AS eligible
        FROM messages WHERE user_id = $1 AND 'UNREAD' = ANY(label_ids)
      ), totals AS (
        SELECT COUNT(*) AS all_unread_total,
          COUNT(*) FILTER (WHERE eligible) AS total,
          COUNT(*) FILTER (WHERE eligible AND internal_date >= boundaries.today) AS today,
          COUNT(*) FILTER (WHERE eligible AND internal_date >= boundaries.yesterday AND internal_date < boundaries.today) AS yesterday,
          COUNT(*) FILTER (WHERE eligible AND internal_date < boundaries.yesterday) AS earlier
        FROM unread CROSS JOIN boundaries
      )${pageCTE}
      SELECT totals.*${pageColumn},
        COALESCE((SELECT json_agg(message_id ORDER BY message_id COLLATE "C") FROM messages
          WHERE user_id = $1 AND message_id = ANY($4::text[]) AND NOT ('UNREAD' = ANY(label_ids))), '[]'::json) AS known_read_ids,
        u.unread_sync_state, u.unread_sync_completed_at
      FROM totals LEFT JOIN users u ON u.user_id = $1
    `, params);
    const row = rows[0];
    return {
      ...(includeCards ? {
        records: row.records.slice(0, scope.limit).map(toRecord),
        nextCursor: nextCursor(userId, scope, row.records, scope.limit),
      } : {}),
      sections: { today: Number(row.today), yesterday: Number(row.yesterday), earlier: Number(row.earlier) },
      syncedUnreadCount: Number(row.total),
      feedUnreadCount: Number(row.total),
      allSyncedUnreadCount: Number(row.all_unread_total),
      knownReadMessageIds: row.known_read_ids,
      syncState: row.unread_sync_state || 'pending',
      syncCompletedAt: row.unread_sync_completed_at ?? null,
      countsAsOf: scope.now, timeZone: scope.timeZone, sectionDate: scope.sectionDate,
    };
  }
  return {
    page: (userId, options = {}, now = new Date()) => read(userId, options, now, true),
    counts: (userId, options = {}, now = new Date()) => read(userId, options, now, false),
  };
}

function withCompleteness(page, unreadCount) {
  const countsComplete = page.syncState === 'complete' && page.syncCompletedAt !== null
    && Number.isSafeInteger(unreadCount) && unreadCount >= 0
    && page.allSyncedUnreadCount === unreadCount;
  return {
    ...page, unreadCount, countsComplete, knownStateComplete: countsComplete,
  };
}

module.exports = { createFeedStorage, feedOptions, nextCursor, withCompleteness };
