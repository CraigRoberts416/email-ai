const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { senderScope, matchesScope, createSenderHistory, registerSenderHistoryRoute } = require('../senderHistory');

function record(id, fromEmail = 'orders@amazon.com', labels = []) {
  return { messageId: String(id), fromEmail, fromName: 'Sender', internalDate: 1262304000000 + Number(id || 0),
    labelIds: labels, subject: `Message ${id}` };
}

function fixture({ records = [], pages = [], cached = [], listPage, fetchError, now } = {}) {
  const source = new Map(records.map(value => [value.messageId, value]));
  const cache = new Map(cached.map(value => [value.messageId, value]));
  const calls = { list: [], fetch: [], save: [] };
  const history = createSenderHistory({
    listPage: async (userId, options) => {
      calls.list.push({ userId, ...options });
      if (listPage) return listPage(userId, options);
      return pages[Number(options.pageToken ?? 0)] ?? { messageIds: [] };
    },
    getRecords: async (_userId, ids) => ids.map(id => cache.get(id)).filter(Boolean),
    fetchRecords: async (userId, ids) => {
      calls.fetch.push({ userId, ids });
      if (fetchError) throw fetchError;
      return ids.map(id => source.get(id)).filter(Boolean);
    },
    saveRecords: async (userId, rows) => { calls.save.push({ userId, rows }); rows.forEach(row => cache.set(row.messageId, row)); },
    logger: { warn() {} }, ...(now ? { now } : {}),
  });
  return { history, calls, cache };
}

const company = { address: 'orders@amazon.com', kind: 'brand' };
async function completed(history, userId = 'a', options = company) {
  for (let attempt = 0; attempt < 100; attempt++) {
    const page = await history.page(userId, options);
    if (page.syncState !== 'syncing') return page;
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.fail('History never completed');
}

test('company identity spans canonical domain/subdomains; people and free mail stay address-scoped', () => {
  const uk = senderScope('Shipping@MAIL.Amazon.co.uk', 'brand');
  assert.equal(uk.scope, 'domain');
  assert.equal(uk.scopeKey, 'amazon.co.uk');
  assert.equal(matchesScope(record(1, 'receipts@amazon.co.uk'), uk), true);
  assert.equal(matchesScope(record(1, 'deals@other.amazon.co.uk'), uk), true);
  assert.equal(matchesScope(record(1, 'spoof@notamazon.co.uk'), uk), false);
  assert.equal(matchesScope(record(1, 'user@amazon.co.uk.evil.com'), uk), false);
  assert.equal(senderScope('person@amazon.com', 'person').scope, 'address');
  assert.equal(senderScope('person@gmail.com', 'brand').scope, 'address');
  assert.equal(senderScope('person@yahoo.co.uk', 'brand').scope, 'address');
  assert.equal(matchesScope(record(1, 'different@gmail.com'), senderScope('person@gmail.com', 'brand')), false);
  for (const address of ['a@gmail.com OR from:other.com', 'a@co.uk', 'bad', 'a@127.0.0.1']) {
    assert.throws(() => senderScope(address, 'brand'), { statusCode: 400 });
  }
});

test('all provider pages determine exact count, ignoring estimates and preserving decade-old read/archived mail', async () => {
  const records = Array.from({ length: 551 }, (_, index) => record(index + 1,
    index % 2 ? 'receipts@mail.amazon.com' : 'orders@amazon.com', index % 3 ? [] : ['UNREAD']));
  records.push({ ...record(900, 'spoof@other.com'), fromName: 'amazon.com' });
  const f = fixture({ records, cached: records.slice(0, 100), pages: [
    { messageIds: records.slice(0, 500).map(row => row.messageId), nextPageToken: '1', resultSizeEstimate: 99999 },
    { messageIds: ['1', ...records.slice(500).map(row => row.messageId)], resultSizeEstimate: 1 },
  ] });
  const first = await completed(f.history);
  assert.equal(first.totalCount, 551);
  assert.equal(first.countComplete, true);
  assert.equal(first.records.length, 50);
  assert.equal(first.records[0].messageId, '551');
  assert.ok(first.records.some(row => row.labelIds.length === 0), 'Read archived mail belongs to profile history');
  assert.equal(f.calls.list.length, 2);
  assert.ok(f.calls.list.every(call => call.q === 'from:amazon.com -in:spam -in:trash'));
  assert.ok(f.calls.fetch.every(call => call.ids.length <= 50));
  assert.equal(f.calls.fetch.flatMap(call => call.ids).length, 452, 'Already cached From metadata is reused');
  const ids = first.records.map(row => row.messageId);
  let cursor = first.nextCursor;
  while (cursor) {
    const page = await f.history.page('a', { ...company, cursor, limit: 100 });
    ids.push(...page.records.map(row => row.messageId));
    cursor = page.nextCursor;
  }
  assert.equal(ids.length, 551);
  assert.equal(new Set(ids).size, 551);
  assert.equal(ids.at(-1), '1');
  assert.equal(f.calls.list.length, 2, 'Completed snapshot pagination never re-enumerates provider history');
});

test('pending enumeration is coalesced and exposes cards without inventing a total or end', async () => {
  let release;
  const waiting = new Promise(resolve => { release = resolve; });
  const f = fixture({ records: [record(1), record(2)], listPage: async (_user, options) =>
    options.pageToken ? await waiting : { messageIds: ['1'], nextPageToken: 'later' } });
  const pending = await f.history.page('a', company);
  assert.equal(pending.totalCount, null);
  assert.equal(pending.countComplete, false);
  assert.equal(pending.nextCursor, null);
  for (let attempt = 0; attempt < 20 && f.calls.list.length < 2; attempt++) await new Promise(resolve => setImmediate(resolve));
  const progress = await f.history.page('a', { address: 'receipts@news.amazon.com', kind: 'brand' });
  assert.equal(progress.records.length, 1);
  assert.equal(progress.syncState, 'syncing');
  assert.equal(progress.countComplete, false);
  assert.equal(f.calls.list.length, 2, 'Company address aliases share one in-flight scan');
  release({ messageIds: ['2'] });
  const complete = await completed(f.history);
  assert.equal(complete.totalCount, 2);
});

test('later-page or metadata failure never claims a partial total; deleted and newly excluded mail are skipped', async () => {
  const failure = fixture({ records: [record(1)], listPage: async (_user, options) => {
    if (options.pageToken) throw Error('provider unavailable');
    return { messageIds: ['1'], nextPageToken: 'later' };
  } });
  const page = await completed(failure.history);
  assert.equal(page.records.length, 1);
  assert.equal(page.syncState, 'error');
  assert.equal(page.totalCount, null);
  assert.equal(page.countComplete, false);
  assert.equal(page.nextCursor, null);
  const excluded = fixture({ records: [record(1), record(2, 'orders@amazon.com', ['SPAM']),
    record(3, 'orders@amazon.com', ['TRASH'])], pages: [{ messageIds: ['1', '2', '3', 'deleted'] }] });
  assert.equal((await completed(excluded.history)).totalCount, 1);
  const metadataFailure = fixture({ pages: [{ messageIds: ['1'] }], fetchError: Error('metadata failed') });
  const failedMetadata = await completed(metadataFailure.history);
  assert.equal(failedMetadata.syncState, 'error');
  assert.equal(failedMetadata.totalCount, null);
  const repeated = fixture({ records: [record(1)], listPage: async () => ({ messageIds: ['1'], nextPageToken: 'loop' }) });
  assert.equal((await completed(repeated.history)).syncState, 'error');
});

test('source hydration applies only to requested page and does not delay complete email totals', async () => {
  const records = Array.from({ length: 5 }, (_, n) => ({ ...record(n), sourceInspected: false }));
  const inspected = new Set(), jobs = [];
  const history = createSenderHistory({
    listPage: async () => ({ messageIds: records.map(record => record.messageId) }),
    getRecords: async (_id, ids) => records.filter(record => ids.includes(record.messageId)),
    getPageRecords: async (_id, ids) => records.filter(record => ids.includes(record.messageId))
      .map(record => ({ ...record, sourceInspected: inspected.has(record.messageId) })),
    fetchRecords: async () => assert.fail('Cached source addresses need no provider metadata'), saveRecords: async () => {},
    hydratePage: (_id, page) => jobs.push(page.map(record => record.messageId)),
  });
  const first = await completed(history, 'a', { ...company, limit: 2 });
  assert.equal(first.totalCount, 5);
  assert.equal(first.countComplete, true);
  assert.equal(first.sourcePendingCount, 2);
  assert.deepEqual(jobs.at(-1), ['4', '3']);
  inspected.add('4'); inspected.add('3');
  const samePage = await history.page('a', { ...company, limit: 2 });
  assert.equal(samePage.sourcePendingCount, 0);
  assert.ok(samePage.nextCursor);
  assert.ok(jobs.every(ids => ids.length <= 2));
});

test('opaque cursors remain stable, account/scope bound, and expire explicitly', async () => {
  let clock = Date.parse('2026-09-19T12:00:00Z');
  const f = fixture({ records: [record(1), record(2)], pages: [{ messageIds: ['1', '2'] }], now: () => clock });
  const first = await completed(f.history, 'a', { ...company, limit: 1 });
  await assert.rejects(f.history.page('b', { ...company, cursor: first.nextCursor }), { statusCode: 400 });
  await assert.rejects(f.history.page('a', { address: 'orders@other.com', kind: 'brand', cursor: first.nextCursor }), { statusCode: 400 });
  await assert.rejects(f.history.page('a', { ...company, cursor: '%' }), { statusCode: 400 });
  for (const limit of [0, 101, '1.5']) await assert.rejects(f.history.page('a', { ...company, limit }), { statusCode: 400 });
  const next = await f.history.page('a', { ...company, cursor: first.nextCursor });
  assert.deepEqual(next.records.map(row => row.messageId), ['1']);
  clock += 16 * 60_000;
  await assert.rejects(f.history.page('a', { ...company, cursor: first.nextCursor }), { statusCode: 410 });
});

test('HTTP endpoint authenticates, uses normal card serialization, and keeps pending/error counts honest', async t => {
  const app = express();
  let options;
  registerSenderHistoryRoute(app, {
    resolveUserId: async req => req.get('authorization') === 'fixture' ? 'a' : null,
    history: { page: async (_id, query) => {
      options = query;
      return { records: [record(1)], nextCursor: null, totalCount: null, countComplete: false,
        syncState: 'syncing', scope: 'domain', scopeKey: 'amazon.com', countsAsOf: '2026-09-19T12:00:00Z' };
    } },
    cardsForMessages: async (_req, id, rows, opts) => {
      assert.equal(id, 'a'); assert.equal(opts.generateHeroes, false);
      return rows.map(row => ({ ...row, avatarUri: 'fixture-avatar' }));
    },
  });
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const url = `http://127.0.0.1:${server.address().port}/sender-history?address=orders%40amazon.com&kind=brand`;
  assert.equal((await fetch(url)).status, 401);
  const response = await fetch(url, { headers: { authorization: 'fixture' } });
  const result = await response.json();
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal(result.cards[0].avatarUri, 'fixture-avatar');
  assert.equal(result.totalCount, null);
  assert.equal(result.countComplete, false);
  assert.equal(result.records, undefined);
  assert.equal(options.address, 'orders@amazon.com');
});
