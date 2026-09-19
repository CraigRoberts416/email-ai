const test = require('node:test');
const assert = require('node:assert/strict');
const { createFeedReader } = require('../feedReader');
const { createUnreadCountCache } = require('../unreadCountCache');

test('actual feed reader returns cards/counts while provider is unresolved, then certifies the next poll', async () => {
  let resolveProvider;
  const pending = new Promise(resolve => { resolveProvider = resolve; });
  const cache = createUnreadCountCache({ load: () => pending, logger: { warn() {} } });
  const page = { records: [{ messageId: 'cached' }], nextCursor: null,
    sections: { today: 1, yesterday: 0, earlier: 0 }, feedUnreadCount: 1,
    syncState: 'complete', syncCompletedAt: new Date(Date.now() - 1000).toISOString() };
  const repairs = [];
  const reader = createFeedReader({
    messageStore: { getUnreadPage: async () => page, getUnreadCounts: async () => {
      const { records, nextCursor, ...metadata } = page; return metadata;
    } },
    mailNotifications: { unreadCountSnapshot: cache.snapshot },
    gmailSync: { ensureUnreadSync: async (...args) => repairs.push(args) },
    processingWorker: { wakeWorker() {} },
  });
  // A deadline makes a regression that awaits Gmail fail promptly, instead
  // of letting the fake provider accidentally unblock the test.
  let timer;
  const first = await Promise.race([reader('a', {}), new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error('Feed waited for Gmail')), 100);
  })]).finally(() => clearTimeout(timer));
  assert.deepEqual(first.records, page.records);
  assert.equal(first.unreadCount, null);
  assert.equal(first.countsComplete, false);
  assert.equal(first.providerCountState, 'refreshing');
  const initialCounts = await reader('a', {}, true);
  assert.equal(initialCounts.records, undefined);
  assert.equal(initialCounts.countsComplete, false);
  assert.equal(repairs.length, 0, 'Unknown provider count cannot trigger a full import');
  resolveProvider(1);
  await cache.refresh('a');
  const verified = await reader('a', {}, true);
  assert.equal(verified.countsComplete, true);
  assert.equal(verified.knownStateComplete, true);
  assert.equal(verified.providerCountState, 'fresh');
  assert.equal(repairs.length, 0);
});

test('incomplete import and a known provider mismatch still schedule reconciliation', async () => {
  const repairs = [];
  let state = 'pending', count = null;
  const reader = createFeedReader({
    messageStore: { getUnreadPage: async () => ({ records: [], feedUnreadCount: 0,
      syncState: state, syncCompletedAt: '2026-01-01T00:00:00Z' }) },
    mailNotifications: { unreadCountSnapshot: () => ({ unreadCount: count }) },
    gmailSync: { ensureUnreadSync: async (_id, options) => repairs.push(options.force) },
    processingWorker: { wakeWorker() {} },
  });
  assert.equal((await reader('a', {})).countsComplete, false);
  state = 'complete'; count = 1;
  assert.equal((await reader('a', {})).countsComplete, false);
  assert.deepEqual(repairs, [false, true]);
});

test('database Date timestamps preserve milliseconds when rejecting a count sampled before sync completion', async () => {
  let now = 100001;
  const cache = createUnreadCountCache({ now: () => now, load: async () => 0 });
  await cache.refresh('a');
  now = 100003;
  const reader = createFeedReader({
    messageStore: { getUnreadPage: async () => ({ records: [], feedUnreadCount: 0,
      syncState: 'complete', syncCompletedAt: new Date(100002) }) },
    mailNotifications: { unreadCountSnapshot: cache.snapshot },
    gmailSync: { ensureUnreadSync: async () => assert.fail('Unknown count must not restart import') },
    processingWorker: { wakeWorker() {} },
  });
  assert.equal((await reader('a', {})).countsComplete, false);
  await cache.refresh('a');
  assert.equal((await reader('a', {})).countsComplete, true);
});
