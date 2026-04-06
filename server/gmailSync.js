const userStore   = require('./userStore');
const messageStore = require('./messageStore');

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
    postCutoff,
  };
}

async function authedFetch(url, accessToken) {
  return fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });
}

async function fetchMailboxProfile(accessToken) {
  const res = await authedFetch('https://gmail.googleapis.com/gmail/v1/users/me/profile', accessToken);
  if (!res.ok) {
    throw new Error(`fetchMailboxProfile failed: ${res.status}`);
  }
  return res.json();
}

async function listMessagesPage(accessToken, { pageToken = null, maxResults = 500 } = {}) {
  const params = new URLSearchParams({ maxResults: String(maxResults) });
  if (pageToken) params.set('pageToken', pageToken);

  const res = await authedFetch(
    `https://gmail.googleapis.com/gmail/v1/users/me/messages?${params.toString()}`,
    accessToken
  );
  if (!res.ok) {
    throw new Error(`listMessagesPage failed: ${res.status}`);
  }

  const data = await res.json();
  return {
    messageIds: (data.messages ?? []).map(m => m.id),
    nextPageToken: data.nextPageToken ?? null,
  };
}

async function fetchMetadataBatch(messageIds, accessToken) {
  // Fetch in parallel groups of 20 to respect rate limits
  const results = [];
  const BATCH = 20;
  for (let i = 0; i < messageIds.length; i += BATCH) {
    const slice = messageIds.slice(i, i + BATCH);
    const msgs = await Promise.all(slice.map(async (id) => {
      const r = await authedFetch(
        `https://gmail.googleapis.com/gmail/v1/users/me/messages/${id}?format=metadata`,
        accessToken
      );
      return r.json();
    }));
    results.push(...msgs.filter(m => m.id));
    if (i + BATCH < messageIds.length) {
      await new Promise(r => setTimeout(r, 100)); // brief pause between batches
    }
  }
  return results;
}

async function syncMailboxHead(userId, { maxResults = 100 } = {}) {
  const accessToken = await userStore.getValidAccessToken(userId);
  const { messageIds } = await listMessagesPage(accessToken, { maxResults });
  if (!messageIds.length) return [];

  const msgs = await fetchMetadataBatch(messageIds, accessToken);
  const records = msgs.map(m => metadataToRecord(m, false));
  await messageStore.upsertMessages(userId, records);

  console.log(`[sync] mailbox head refreshed: ${records.length} messages`);
  return records;
}

/**
 * Full paginated sync — fetches all messages, stores with post_cutoff=false.
 * Non-blocking caller: fires and forgets after returning on first page.
 */
async function initialSync(userId) {
  console.log(`[sync] initial sync started for user ${userId.slice(0, 8)}…`);
  let pageToken   = null;
  let pageCount   = 0;
  let total       = 0;

  do {
    const accessToken = await userStore.getValidAccessToken(userId); // refresh between pages if needed
    let listPage;
    try {
      listPage = await listMessagesPage(accessToken, { pageToken, maxResults: 500 });
    } catch (err) {
      console.error(`[sync] list failed (page ${pageCount}): ${err.message}`);
      break;
    }
    const messageIds = listPage.messageIds;
    if (!messageIds.length) break;

    const msgs    = await fetchMetadataBatch(messageIds, accessToken);
    const records = msgs.map(m => metadataToRecord(m, false));
    await messageStore.upsertMessages(userId, records);

    total += records.length;
    pageCount++;
    pageToken = listPage.nextPageToken;
    console.log(`[sync] page ${pageCount}: ${records.length} messages (running total: ${total})`);
  } while (pageToken);

  console.log(`[sync] initial sync complete: ${total} messages`);
}

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
  const url = `https://gmail.googleapis.com/gmail/v1/users/me/history?startHistoryId=${user.history_id}&historyTypes=messageAdded&historyTypes=labelAdded&historyTypes=labelRemoved`;

  const res = await authedFetch(url, accessToken);
  if (!res.ok) {
    if (res.status === 404) {
      console.warn(`[sync] historyId expired for ${userId.slice(0, 8)}…, refreshing mailbox head and resetting historyId`);
      try {
        const profile = await fetchMailboxProfile(accessToken);
        if (profile.historyId) {
          await userStore.updateHistoryId(userId, profile.historyId);
        }
      } catch (profileErr) {
        console.error('[sync] profile refresh failed:', profileErr.message);
      }

      let headRecords = [];
      try {
        headRecords = await syncMailboxHead(userId, { maxResults: 100 });
      } catch (headErr) {
        console.error('[sync] mailbox head refresh failed:', headErr.message);
      }
      initialSync(userId).catch(err => console.error('[sync] re-sync error:', err.message));

      return {
        newUnreadIds: headRecords
          .filter(record => record.labelIds.includes('UNREAD'))
          .map(record => record.messageId),
      };
    } else {
      console.error(`[sync] history list failed: ${res.status}`);
    }
    return { newUnreadIds: [] };
  }

  const data    = await res.json();
  const history = data.history ?? [];

  const newMessageIds   = [];
  const labelChanges    = new Map(); // messageId → { added: [], removed: [] }

  for (const event of history) {
    for (const { message } of event.messagesAdded ?? []) {
      newMessageIds.push(message.id);
    }
    for (const { message, labelIds } of event.labelsAdded ?? []) {
      const e = labelChanges.get(message.id) ?? { added: [], removed: [] };
      e.added.push(...(labelIds ?? []));
      labelChanges.set(message.id, e);
    }
    for (const { message, labelIds } of event.labelsRemoved ?? []) {
      const e = labelChanges.get(message.id) ?? { added: [], removed: [] };
      e.removed.push(...(labelIds ?? []));
      labelChanges.set(message.id, e);
    }
  }

  const newUnreadIds = [];
  if (newMessageIds.length > 0) {
    const msgs    = await fetchMetadataBatch(newMessageIds, accessToken);
    const records = msgs.map(m => metadataToRecord(m, true)); // post-cutoff = true
    await messageStore.upsertMessages(userId, records);
    for (const r of records) {
      if (r.labelIds.includes('UNREAD')) newUnreadIds.push(r.messageId);
    }
    console.log(`[sync] incremental: ${records.length} new messages, ${newUnreadIds.length} unread`);
  }

  // Apply label changes to existing records
  for (const [messageId, { added, removed }] of labelChanges) {
    const existing = await messageStore.getMessage(userId, messageId);
    if (!existing) continue;
    const labelSet = new Set(existing.labelIds);
    added.forEach(l => labelSet.add(l));
    removed.forEach(l => labelSet.delete(l));
    await messageStore.updateLabelIds(userId, messageId, Array.from(labelSet));
  }

  if (data.historyId) {
    await userStore.updateHistoryId(userId, data.historyId);
  }

  return { newUnreadIds };
}

/**
 * Fetch full message content for AI processing.
 */
async function fetchFullMessage(userId, messageId) {
  const accessToken = await userStore.getValidAccessToken(userId);
  const res = await authedFetch(
    `https://gmail.googleapis.com/gmail/v1/users/me/messages/${messageId}?format=full`,
    accessToken
  );
  if (!res.ok) throw new Error(`fetchFullMessage failed: ${res.status}`);
  return res.json();
}

module.exports = { initialSync, incrementalSync, fetchFullMessage };
