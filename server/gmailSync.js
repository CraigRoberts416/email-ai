const userStore   = require('./userStore');
const messageStore = require('./messageStore');
const { createUnreadBacklog } = require('./unreadBacklog');
const { createGmailReadTransport, gmailReadError } = require('./gmailReadTransport');
const gmailRead = createGmailReadTransport();

function decodeHtmlEntities(text) {
  return text
    .replace(/&nbsp;/gi, ' ').replace(/&amp;/gi, '&').replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>').replace(/&quot;/gi, '"').replace(/&#39;/gi, "'")
    .replace(/\s+/g, ' ').trim();
}

function parseSender(from) {
  const match = from.match(/^(.*?)\s*<([^>]+)>$/);
  const email = match ? match[2].trim() : from.trim();
  const name  = match ? match[1].replace(/^"|"$/g, '').trim() : email;
  return { name, email };
}

function metadataToRecord(msg, postCutoff = false) {
  const headers   = msg.payload?.headers ?? [];
  const getHeader = (n) => headers.find(h => h.name.toLowerCase() === n.toLowerCase())?.value ?? '';
  const fromRaw   = getHeader('from');
  const { name: fromName, email: fromEmail } = parseSender(fromRaw);

  // Who else was on it. Without this a conversation cannot be identified at
  // all: the unit of a direct message is the set of people in it, and until
  // now the only address stored was the sender's.
  const participants = [];
  for (const header of ['to', 'cc']) {
    for (const part of getHeader(header).split(',')) {
      const { name, email } = parseSender(part.trim());
      if (email) participants.push({ name, email: email.toLowerCase() });
    }
  }

  return {
    messageId:    msg.id,
    threadId:     msg.threadId ?? null,
    labelIds:     msg.labelIds ?? [],
    subject:      getHeader('subject') || '(no subject)',
    fromName,
    fromEmail,
    snippet:      decodeHtmlEntities(msg.snippet ?? ''),
    internalDate: Number(msg.internalDate) || Date.now(),
    historyId:    msg.historyId ?? null,
    participants,
    postCutoff,
    labelsObservedAt: msg.labelsObservedAt,
  };
}

async function authedFetch(userId, url, accessToken, options) {
  return gmailRead(userId, url, accessToken, options);
}

async function fetchMailboxProfile(userId, accessToken) {
  const res = await authedFetch(userId, 'https://gmail.googleapis.com/gmail/v1/users/me/profile', accessToken, { units: 1 });
  if (!res.ok) {
    throw gmailReadError(res, 'fetchMailboxProfile');
  }
  return res.json();
}

// The native feed intentionally loads a bounded window. Its card count cannot
// stand in for the mailbox's unread count, especially during initial import.
async function getUnreadCount(userId, { signal } = {}) {
  const accessToken = await userStore.getValidAccessToken(userId, { signal });
  const res = await authedFetch(userId, 'https://gmail.googleapis.com/gmail/v1/users/me/labels/UNREAD', accessToken,
    { units: 1, priority: 3, signal: signal ?? AbortSignal.timeout(15000) });
  if (!res.ok) throw gmailReadError(res, 'unread label fetch');
  const { messagesUnread } = await res.json();
  if (!Number.isSafeInteger(messagesUnread) || messagesUnread < 0) {
    throw new Error('Gmail returned an invalid unread count');
  }
  return messagesUnread;
}

async function listMessagesPage(userId, accessToken, { pageToken = null, maxResults = 500, unread = false, folder = null } = {}) {
  const params = new URLSearchParams({ maxResults: String(maxResults) });
  if (pageToken) params.set('pageToken', pageToken);
  if (unread) {
    params.set('labelIds', 'UNREAD');
    params.set('includeSpamTrash', 'true');
    if (folder) params.append('labelIds', folder);
  }

  const res = await authedFetch(
    userId,
    `https://gmail.googleapis.com/gmail/v1/users/me/messages?${params.toString()}`,
    accessToken, { units: 5, priority: 0 }
  );
  if (!res.ok) {
    throw gmailReadError(res, 'listMessagesPage');
  }

  const data = await res.json();
  return {
    messageIds: (data.messages ?? []).map(m => m.id),
    nextPageToken: data.nextPageToken ?? null,
  };
}

async function fetchMetadataBatch(userId, messageIds, accessToken, { priority = 0 } = {}) {
  // Bound queued work; the shared mailbox transport controls actual pacing.
  const results = [];
  const BATCH = 20;
  for (let i = 0; i < messageIds.length; i += BATCH) {
    const slice = messageIds.slice(i, i + BATCH);
    const settled = await Promise.allSettled(slice.map(async (id) => {
      const labelsObservedAt = new Date();
      const r = await authedFetch(
        userId,
        `https://gmail.googleapis.com/gmail/v1/users/me/messages/${id}?format=metadata`,
        accessToken, { priority }
      );
      if (r.status === 404) return {}; // deleted between list and metadata
      if (!r.ok) throw gmailReadError(r, 'metadata fetch');
      return { ...await r.json(), labelsObservedAt };
    }));
    // Wait for the bounded group before permitting an import retry. Otherwise
    // failed Promise.all leaves sibling requests running behind a new import.
    const failed = settled.find(result => result.status === 'rejected');
    if (failed) throw failed.reason;
    results.push(...settled.map(result => result.value).filter(m => m.id));
  }
  return results;
}

async function syncMailboxHead(userId, { maxResults = 100 } = {}) {
  const accessToken = await userStore.getValidAccessToken(userId);
  const { messageIds } = await listMessagesPage(userId, accessToken, { maxResults });
  if (!messageIds.length) return [];

  const msgs = await fetchMetadataBatch(userId, messageIds, accessToken);
  const records = msgs.map(m => metadataToRecord(m, false));
  await messageStore.upsertMessages(userId, records);

  console.log(`[sync] mailbox head refreshed: ${records.length} messages`);
  return records;
}

/**
 * Full paginated sync — fetches all messages, stores with post_cutoff=false.
 * Non-blocking caller: fires and forgets after returning on first page.
 */
const initialSyncs = new Map();
const initialSyncFailures = new Map();
function initialSync(userId) {
  if (initialSyncs.has(userId)) return initialSyncs.get(userId);
  const failure = initialSyncFailures.get(userId);
  if (failure && Date.now() < failure.retryAt) return Promise.resolve();
  const job = runInitialSync(userId).then(() => initialSyncFailures.delete(userId)).catch(error => {
    initialSyncFailures.set(userId, { retryAt: Date.now() + Math.max(60_000, error.retryAfterMs ?? 0) });
    throw error;
  }).finally(() => initialSyncs.delete(userId));
  initialSyncs.set(userId, job);
  return job;
}
async function runInitialSync(userId) {
  for (;;) {
    const snapshot = await userStore.beginAllMailSync(userId);
    try {
      if (await importAllMail(userId, snapshot) === false) continue;
      await messageStore.reconcileAllMail(userId, snapshot.generation, snapshot.startedAt);
      if (await userStore.setAllMailSyncState(userId, 'complete', { generation: snapshot.generation })) return;
      // An expired-history recovery invalidated the snapshot while it ran.
      // The coalesced job owns the follow-up; no request is required to restart.
    } catch (error) {
      if (!await userStore.setAllMailSyncState(userId, 'failed', { generation: snapshot.generation })) continue;
      if (error.status === 400) await userStore.setAllMailSyncState(userId, 'pending', { generation: snapshot.generation });
      throw error;
    }
  }
}
async function importAllMail(userId, snapshot) {
  console.log(`[sync] initial sync ${snapshot.cursor ? 'resumed at saved page' : 'started'} for user ${userId.slice(0, 8)}…`);
  let pageToken   = snapshot.cursor ?? null;
  let pageCount   = 0;
  let total       = 0;

  do {
    const accessToken = await userStore.getValidAccessToken(userId); // refresh between pages if needed
    let listPage;
    try {
      listPage = await listMessagesPage(userId, accessToken, { pageToken, maxResults: 500 });
    } catch (err) {
      console.error(`[sync] list failed (page ${pageCount}): ${err.message}`);
      throw err;
    }
    const messageIds = listPage.messageIds;
    if (!messageIds.length) {
      pageToken = listPage.nextPageToken;
      if (!await userStore.setAllMailSyncCursor(userId, pageToken, snapshot.generation)) return false;
      continue;
    }

    const missing = snapshot.revalidate ? messageIds : await messageStore.archiveMetadataNeeded(userId, messageIds);
    const missingSet = new Set(missing);
    const known = messageIds.filter(id => !missingSet.has(id));
    if (known.length) await messageStore.markAllMailSeen(userId, known, snapshot.generation);
    let stored = known.length;
    // Inventory must visit every provider ID. Known immutable metadata can be
    // reused; current labels are maintained by history/unread reconciliation.
    // Persist smaller pieces so a later throttled request does not erase work.
    for (let offset = 0; offset < missing.length; offset += 20) {
      const ids = missing.slice(offset, offset + 20);
      const msgs = await fetchMetadataBatch(userId, ids, accessToken);
      const records = msgs.map(m => metadataToRecord(m, false));
      if (records.length) await messageStore.upsertMessages(userId, records);
      const retained = records.map(record => record.messageId);
      await messageStore.markAllMailSeen(userId, retained, snapshot.generation);
      stored += retained.length;
    }
    total += stored;
    pageCount++;
    pageToken = listPage.nextPageToken;
    if (!await userStore.setAllMailSyncCursor(userId, pageToken, snapshot.generation)) return false;
    console.log(`[sync] page ${pageCount}: ${stored} messages (running total: ${total})`);
  } while (pageToken);

  console.log(`[sync] initial sync complete: ${total} messages`);
}

const unreadBacklog = createUnreadBacklog({
  userStore, messageStore, toRecord: metadataToRecord,
  listPage: async (userId, pageToken, folder) => listMessagesPage(userId, await userStore.getValidAccessToken(userId), {
    pageToken, unread: true, folder,
  }),
  metadata: async (userId, ids) => fetchMetadataBatch(userId, ids, await userStore.getValidAccessToken(userId)),
});

const ensureUnreadSync = unreadBacklog.ensure;

/**
 * Incremental sync using Gmail History API.
 * Returns { newUnreadIds } — message IDs of newly arrived UNREAD post-cutoff messages.
 */
async function incrementalSync(userId) {
  const user = await userStore.getUser(userId);
  if (!user?.history_id) {
    console.log(`[sync] no historyId for ${userId.slice(0, 8)}…, skipping incremental`);
    return { newUnreadIds: [] };
  }

  const accessToken = await userStore.getValidAccessToken(userId);
  let pageToken = null;
  let finalHistoryId = null;
  const newMessageIds = new Set();
  const deletedMessageIds = new Set();
  const labelChanges = new Map();
  do {
    const params = new URLSearchParams({ startHistoryId: user.history_id });
    for (const kind of ['messageAdded', 'messageDeleted', 'labelAdded', 'labelRemoved']) params.append('historyTypes', kind);
    if (pageToken) params.set('pageToken', pageToken);
    const res = await authedFetch(userId, `https://gmail.googleapis.com/gmail/v1/users/me/history?${params}`, accessToken, { units: 2 });
    if (!res.ok) {
      if (res.status === 404) {
        await userStore.setUnreadSyncState(userId, 'pending');
        await userStore.setAllMailSyncState(userId, 'pending', { revalidate: true });
        const profile = await fetchMailboxProfile(userId, accessToken);
        if (profile.historyId) await userStore.updateHistoryId(userId, profile.historyId);
        const headRecords = await syncMailboxHead(userId, { maxResults: 100 });
        initialSync(userId).catch(err => console.error('[sync] re-sync error:', err.message));
        return { newUnreadIds: headRecords.filter(record => record.labelIds.includes('UNREAD')).map(record => record.messageId) };
      }
      throw gmailReadError(res, 'history list');
    }
    const data = await res.json();
    for (const event of data.history ?? []) {
      for (const { message } of event.messagesAdded ?? []) newMessageIds.add(message.id);
      for (const { message } of event.messagesDeleted ?? []) deletedMessageIds.add(message.id);
      for (const [field, adding] of [['labelsAdded', true], ['labelsRemoved', false]]) {
        for (const { message, labelIds } of event[field] ?? []) {
          const changes = labelChanges.get(message.id) ?? new Map();
          for (const label of labelIds ?? []) changes.set(label, adding);
          labelChanges.set(message.id, changes);
        }
      }
    }
    finalHistoryId = data.historyId ?? finalHistoryId;
    pageToken = data.nextPageToken ?? null;
  } while (pageToken);
  // All pages must succeed before any checkpoint advances. Replaying writes
  // after a partial failure is safe; skipping the next history page is not.
  for (const id of deletedMessageIds) { newMessageIds.delete(id); labelChanges.delete(id); }

  const newUnreadIds = [];
  if (newMessageIds.size > 0) {
    const msgs    = await fetchMetadataBatch(userId, [...newMessageIds], accessToken, { priority: 1 });
    const records = msgs.map(m => metadataToRecord(m, true)); // post-cutoff = true
    await messageStore.upsertMessages(userId, records);
    for (const r of records) {
      if (r.labelIds.includes('UNREAD')) newUnreadIds.push(r.messageId);
    }
    console.log(`[sync] incremental: ${records.length} new messages, ${newUnreadIds.length} unread`);
  }

  // Apply label changes to existing records
  for (const [messageId, changes] of labelChanges) {
    const existing = await messageStore.getMessage(userId, messageId);
    if (!existing) continue;
    const labelSet = new Set(existing.labelIds);
    for (const [label, adding] of changes) { if (adding) labelSet.add(label); else labelSet.delete(label); }
    await messageStore.updateLabelIds(userId, messageId, Array.from(labelSet));
  }

  if (deletedMessageIds.size) await messageStore.removeMessages(userId, [...deletedMessageIds]);
  if (finalHistoryId) await userStore.updateHistoryId(userId, finalHistoryId);

  return { newUnreadIds };
}

/**
 * What the history stream missed.
 *
 * Incremental sync is a diff keyed on a stored historyId, and every way that
 * can go wrong loses mail in silence. The id expires after about a week and
 * the recovery path above jumps it straight to the present, skipping whatever
 * arrived in between. A restart can land between advancing the id and writing
 * the messages. A failed fetch leaves the id already moved on. Nothing
 * anywhere notices, because a diff stream has no way to report what it did not
 * mention.
 *
 * On 15 September this mailbox had an eight-hour hole in it — 14:54 to 22:52 —
 * and the message that fell in was the one the reader actually cared about.
 *
 * So stop reasoning about causes: ask Gmail for the most recent ids and store
 * the ones this database cannot answer for. It does not matter why one was
 * missed; the next pass closes the gap. One list call, then metadata only for
 * the ids that came back unaccounted for, which on a healthy mailbox is none.
 */
async function reconcileRecent(userId, { window = 250 } = {}) {
  const accessToken = await userStore.getValidAccessToken(userId);
  const { messageIds } = await listMessagesPage(userId, accessToken, { maxResults: window });
  if (!messageIds.length) return { recovered: 0 };

  const missing = await messageStore.unreconciled(userId, messageIds);
  if (!missing.length) return { recovered: 0 };

  const user = await userStore.getUser(userId);
  // When they connected. Mail older than that was already in the mailbox and
  // belongs to the archive; mail newer arrived while we were watching and
  // belongs in the feed, whether or not we managed to notice it at the time.
  const connectedAt = user?.created_at ? new Date(user.created_at).getTime() : Infinity;

  const msgs    = await fetchMetadataBatch(userId, missing, accessToken);
  const records = msgs.map(m => {
    const record = metadataToRecord(m, false);
    record.postCutoff = record.internalDate >= connectedAt;
    return record;
  });
  await messageStore.upsertMessages(userId, records);

  const fresh = records.filter(r => r.postCutoff);
  console.log(`[reconcile] ${records.length} unaccounted for, ${fresh.length} post-cutoff`);

  return {
    recovered: records.length,
    newUnreadIds: fresh
      .filter(r => r.labelIds.includes('UNREAD'))
      .map(r => r.messageId),
  };
}

/**
 * Fetch full message content for AI processing.
 */
async function fetchFullMessage(userId, messageId, { priority = 2 } = {}) {
  const accessToken = await userStore.getValidAccessToken(userId);
  const res = await authedFetch(
    userId,
    `https://gmail.googleapis.com/gmail/v1/users/me/messages/${messageId}?format=full`,
    accessToken, { priority }
  );
  if (!res.ok) throw gmailReadError(res, 'fetchFullMessage');
  return res.json();
}

async function fetchMessageMetadata(userId, messageId, { priority = 0 } = {}) {
  const accessToken = await userStore.getValidAccessToken(userId);
  const response = await authedFetch(userId,
    `https://gmail.googleapis.com/gmail/v1/users/me/messages/${messageId}?format=metadata`, accessToken, { priority });
  if (!response.ok) throw gmailReadError(response, 'metadata fetch');
  return response.json();
}

async function listSenderMessagesPage(userId, { q, pageToken = null }) {
  const token = await userStore.getValidAccessToken(userId);
  const params = new URLSearchParams({ q, maxResults: '500', includeSpamTrash: 'false' });
  if (pageToken) params.set('pageToken', pageToken);
  const response = await authedFetch(userId, `https://gmail.googleapis.com/gmail/v1/users/me/messages?${params}`, token, { units: 5 });
  if (!response.ok) throw gmailReadError(response, 'sender history list');
  const data = await response.json();
  return { messageIds: (data.messages ?? []).map(message => message.id), nextPageToken: data.nextPageToken ?? null };
}

async function fetchSenderRecords(userId, ids) {
  const token = await userStore.getValidAccessToken(userId);
  return (await fetchMetadataBatch(userId, ids, token, { priority: 1 })).map(message => metadataToRecord(message, false));
}

module.exports = { initialSync, incrementalSync, reconcileRecent, fetchFullMessage, fetchMessageMetadata, getUnreadCount, ensureUnreadSync,
  listSenderMessagesPage, fetchSenderRecords };
