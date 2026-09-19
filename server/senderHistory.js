const crypto = require('node:crypto');
const { canonicalDomain, FREE_MAIL_DOMAINS } = require('./senderIdentity');

const MAX_PAGE = 100;
const FRESH_MS = 60_000;
const SNAPSHOT_MS = 15 * 60_000;
const MAX_SNAPSHOTS = 100;
const MORE_FREE_MAIL = new Set([
  'me.com', 'mac.com', 'fastmail.com', 'fastmail.fm', 'hey.com', 'mail.com',
  'gmx.com', 'gmx.net', 'gmx.de', 'web.de', 'yahoo.co.uk', 'yahoo.ca',
  'yahoo.com.au', 'yahoo.co.jp', 'yahoo.fr', 'yahoo.de', 'ymail.com',
  'hotmail.co.uk', 'hotmail.fr', 'hotmail.de', 'live.co.uk', 'live.fr',
  'outlook.fr', 'outlook.de', 'orange.fr', 'wanadoo.fr', 'qq.com', '163.com',
  '126.com', 'naver.com', 'daum.net', 'yandex.com', 'yandex.ru', 'mail.ru',
]);

function failure(message, statusCode = 400) { return Object.assign(new Error(message), { statusCode }); }

function senderScope(address, kind = 'person') {
  if (typeof address !== 'string' || address.length > 320 || !['person', 'brand', 'unknown'].includes(kind)) {
    throw failure('invalid sender identity');
  }
  address = address.trim().toLowerCase();
  const parts = address.split('@');
  // A narrow address grammar also prevents Gmail search operators entering q.
  if (parts.length !== 2 || !/^[a-z0-9.!#$%&'*+\/=?^_`{|}~-]+$/i.test(parts[0])) throw failure('invalid sender address');
  const root = canonicalDomain(parts[1]);
  if (!root) throw failure('invalid sender domain');
  const company = kind === 'brand' && !FREE_MAIL_DOMAINS.has(root) && !MORE_FREE_MAIL.has(root);
  return { address, scope: company ? 'domain' : 'address', scopeKey: company ? root : address };
}

function matchesScope(record, identity) {
  const address = String(record.fromEmail ?? '').trim().toLowerCase();
  if (identity.scope === 'address') return address === identity.scopeKey;
  const parts = address.split('@');
  return parts.length === 2 && canonicalDomain(parts[1]) === identity.scopeKey;
}

function excluded(record) { return (record.labelIds ?? []).some(label => label === 'SPAM' || label === 'TRASH'); }

function createSenderHistory({ listPage, getRecords, getPageRecords = getRecords, fetchRecords, saveRecords, hydratePage,
  now = () => Date.now(), logger = console }) {
  const latest = new Map();
  const snapshots = new Map();

  function prune() {
    for (const [id, job] of snapshots) {
      if (job.state !== 'syncing' && now() - job.touched > SNAPSHOT_MS) snapshots.delete(id);
    }
    for (const [key, id] of latest) if (!snapshots.has(id)) latest.delete(key);
  }

  async function gather(job) {
    const visitedTokens = new Set();
    const seenIds = new Set();
    let token = null;
    try {
      do {
        const page = await listPage(job.userId, {
          // Provider search narrows candidates; immutable From metadata below
          // verifies identity so a display-name match cannot inflate totals.
          q: `from:${job.scopeKey} -in:spam -in:trash`, pageToken: token,
        });
        if (!Array.isArray(page.messageIds)) throw Error('invalid history list');
        const ids = [...new Set(page.messageIds)].filter(id => !seenIds.has(id));
        ids.forEach(id => seenIds.add(id));
        // Make the first cards available before a cold 500-message page has
        // finished fetching metadata. No email body or AI call is needed.
        for (let offset = 0; offset < ids.length; offset += 50) {
          const chunk = ids.slice(offset, offset + 50);
          const cached = await getRecords(job.userId, chunk);
          const known = new Map(cached.map(record => [record.messageId, record]));
          const missing = chunk.filter(id => !known.get(id)?.fromEmail || excluded(known.get(id)));
          if (missing.length) {
            const fetched = await fetchRecords(job.userId, missing);
            await saveRecords(job.userId, fetched);
            fetched.forEach(record => known.set(record.messageId, record));
          }
          for (const id of chunk) {
            const record = known.get(id);
            // fetchRecords skips only provider 404s (deleted after listing).
            if (record && !excluded(record) && matchesScope(record, job)) {
              job.records.set(id, { messageId: id, internalDate: record.internalDate });
            }
          }
        }
        token = page.nextPageToken ?? null;
        if (token && visitedTokens.has(token)) throw Error('repeated history page token');
        if (token) visitedTokens.add(token);
      } while (token);
      job.sorted = sorted(job.records);
      job.state = 'complete';
      job.completedAt = now();
    } catch (error) {
      job.state = 'error';
      job.completedAt = now();
      logger.warn('[sender-history] enumeration failed:', error.message);
    }
  }

  function sorted(records) {
    return [...records.values()].sort((a, b) => Number(b.internalDate) - Number(a.internalDate)
      || (a.messageId < b.messageId ? 1 : a.messageId > b.messageId ? -1 : 0));
  }

  function start(userId, identity, key) {
    prune();
    if (snapshots.size >= MAX_SNAPSHOTS) {
      const oldest = [...snapshots.values()].filter(job => job.state !== 'syncing')
        .sort((a, b) => a.touched - b.touched)[0];
      if (oldest) snapshots.delete(oldest.id);
      else throw failure('sender history is busy; retry shortly', 503);
    }
    const job = { ...identity, id: crypto.randomUUID(), userId, records: new Map(),
      state: 'syncing', startedAt: now(), completedAt: null, touched: now() };
    snapshots.set(job.id, job);
    latest.set(key, job.id);
    job.task = gather(job);
    return job;
  }

  async function page(userId, { address, kind = 'person', cursor, limit = 50 } = {}) {
    const identity = senderScope(address, kind);
    if (!/^\d+$/.test(String(limit)) || Number(limit) < 1 || Number(limit) > MAX_PAGE) throw failure('invalid history limit');
    limit = Number(limit);
    const key = JSON.stringify([userId, identity.scope, identity.scopeKey]);
    let job, offset = 0;
    prune();
    if (cursor !== undefined && cursor !== null) {
      let value;
      try {
        if (typeof cursor !== 'string' || cursor.length > 2048 || !/^[A-Za-z0-9_-]+$/.test(cursor)) throw Error();
        value = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8'));
        if (value.v !== 1 || typeof value.id !== 'string' || !Number.isSafeInteger(value.offset) || value.offset < 0) throw Error();
      } catch { throw failure('invalid sender history cursor'); }
      job = snapshots.get(value.id);
      if (!job) throw failure('sender history cursor expired; refresh history', 410);
      if (job.userId !== userId || job.scope !== identity.scope || job.scopeKey !== identity.scopeKey || job.state !== 'complete') {
        throw failure('invalid sender history cursor');
      }
      offset = value.offset;
    } else {
      job = snapshots.get(latest.get(key));
      if (!job || (job.state === 'error' && job.errorDelivered)
        || (job.state !== 'syncing' && now() - job.completedAt >= FRESH_MS)) job = start(userId, identity, key);
    }
    job.touched = now();
    const records = job.sorted ?? sorted(job.records);
    const selected = records.slice(offset, offset + limit);
    // While enumeration is incomplete, only the head can be shown: clients
    // poll it and deduplicate. Stable offset cursors begin at full completion.
    const nextCursor = job.state === 'complete' && offset + limit < records.length
      ? Buffer.from(JSON.stringify({ v: 1, id: job.id, offset: offset + limit })).toString('base64url') : null;
    const metadata = {
      nextCursor,
      totalCount: job.state === 'complete' ? records.length : null,
      countComplete: job.state === 'complete', syncState: job.state,
      scope: job.scope, scopeKey: job.scopeKey,
      countsAsOf: new Date(job.completedAt ?? job.startedAt).toISOString(),
    };
    if (job.state === 'error') job.errorDelivered = true;
    const cards = selected.length ? await getPageRecords(userId, selected.map(record => record.messageId)) : [];
    const byId = new Map(cards.map(record => [record.messageId, record]));
    const ordered = selected.map(record => byId.get(record.messageId)).filter(Boolean);
    const sourcePendingCount = hydratePage ? ordered.filter(record => !record.sourceInspected).length : 0;
    if (sourcePendingCount) hydratePage(userId, ordered);
    return { records: ordered, ...metadata, sourcePendingCount };
  }

  return { page };
}

function registerSenderHistoryRoute(app, { resolveUserId, history, cardsForMessages, sanitize = value => value }) {
  app.get('/sender-history', async (req, res) => {
    try {
      const userId = await resolveUserId(req);
      if (!userId) return res.status(401).json({ error: 'unauthorized' });
      const { records, ...metadata } = await history.page(userId, req.query);
      const cards = await cardsForMessages(req, userId, records, { generateHeroes: false });
      res.setHeader('Cache-Control', 'no-store');
      res.json(sanitize({ cards, ...metadata }));
    } catch (error) {
      const status = [400, 410, 503].includes(error.statusCode) ? error.statusCode : 500;
      res.status(status).json({ error: status === 500 ? 'sender history unavailable' : error.message });
    }
  });
}

module.exports = { senderScope, matchesScope, createSenderHistory, registerSenderHistoryRoute };
