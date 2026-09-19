const test = require('node:test');
const assert = require('node:assert/strict');
const { createUnreadCountCache } = require('../unreadCountCache');

const quiet = { warn() {} };
const flush = () => new Promise(resolve => setImmediate(resolve));
function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

test('cold snapshots return unknown immediately; feed batches and badges share one provider request', async () => {
  const provider = deferred();
  let calls = 0;
  let now = 100000;
  const cache = createUnreadCountCache({ now: () => now, logger: quiet,
    load: () => { calls++; return provider.promise; } });
  assert.deepEqual(cache.snapshot('a'), {
    unreadCount: null, providerCountAsOf: null, providerCountAgeMs: null, providerCountState: 'refreshing',
  });
  for (let i = 0; i < 20; i++) assert.equal(cache.snapshot('a').unreadCount, null);
  const badge = cache.refresh('a', { force: true });
  await flush();
  assert.equal(calls, 1);
  provider.resolve(23000);
  assert.equal(await badge, 23000);
  now += 1000;
  assert.deepEqual(cache.snapshot('a'), {
    unreadCount: 23000, providerCountAsOf: new Date(100000).toISOString(),
    providerCountAgeMs: 1000, providerCountState: 'fresh',
  });
  assert.equal(calls, 1);
});

test('30-second expiry and refresh failure never reuse stale zero; failures have a cooldown', async () => {
  let now = 100000;
  let calls = 0;
  const cache = createUnreadCountCache({ now: () => now, logger: quiet,
    load: async () => { if (++calls > 1) throw new Error('offline'); return 0; } });
  assert.equal(await cache.refresh('a'), 0);
  now += 29999;
  assert.equal(cache.snapshot('a').unreadCount, 0);
  now++;
  assert.equal(cache.snapshot('a').unreadCount, null);
  assert.equal(await cache.refresh('a'), null);
  assert.equal(cache.snapshot('a').providerCountState, 'unavailable');
  assert.equal(cache.snapshot('a').providerCountAgeMs, 30000);
  assert.equal(calls, 2);
  now += 5000;
  await cache.refresh('a');
  assert.equal(calls, 3);
});

test('read invalidation aborts the old request and late results cannot overwrite a newer generation', async () => {
  const old = deferred(), next = deferred();
  const signals = [];
  const cache = createUnreadCountCache({ logger: quiet, load: (_id, { signal }) => {
    signals.push(signal);
    return signals.length === 1 ? old.promise : next.promise;
  } });
  const beforeRead = cache.refresh('a');
  await flush();
  cache.invalidate('a');
  assert.equal(signals[0].aborted, true);
  const afterRead = cache.refresh('a');
  await flush();
  assert.equal(await beforeRead, null);
  next.resolve(4);
  assert.equal(await afterRead, 4);
  old.resolve(5); // Fake provider deliberately ignores abort.
  await flush();
  assert.equal(cache.snapshot('a').unreadCount, 4);
});

test('overall deadline bounds even token/database work that ignores abort and permits a later retry', async () => {
  let now = 100000;
  const stuck = deferred();
  let signal;
  let calls = 0;
  const cache = createUnreadCountCache({ now: () => now, timeoutMs: 15, retryMs: 50, logger: quiet,
    load: (_id, options) => { signal = options.signal; return ++calls === 1 ? stuck.promise : 7; } });
  assert.equal(await cache.refresh('a'), null);
  assert.equal(signal.aborted, true);
  assert.equal(cache.snapshot('a').providerCountState, 'unavailable');
  now += 50;
  assert.equal(await cache.refresh('a'), 7);
  stuck.resolve(0);
  await flush();
  assert.equal(cache.snapshot('a').unreadCount, 7);
});

test('account isolation and import watermark prevent a pre-import count from certifying newer data', async () => {
  let now = 100000;
  const counts = { a: 0, b: 12 };
  const cache = createUnreadCountCache({ now: () => now, logger: quiet, load: async id => counts[id] });
  await Promise.all([cache.refresh('a'), cache.refresh('b')]);
  now++;
  assert.equal(cache.snapshot('a', { notBefore: now }).unreadCount, null);
  assert.equal(cache.snapshot('b').unreadCount, 12);
  await cache.refresh('a');
  assert.equal(cache.snapshot('a', { notBefore: now }).unreadCount, 0);
  cache.invalidate('a');
  assert.equal(cache.isCurrent('a', 0), false);
  assert.equal(cache.isCurrent('b', 12), true);
});

test('invalid counts stay unknown rather than entering the cache as zero', async () => {
  for (const count of [null, undefined, NaN, -1, '0']) {
    const cache = createUnreadCountCache({ logger: quiet, load: async () => count });
    assert.equal(await cache.refresh('a'), null);
    assert.equal(cache.snapshot('a').unreadCount, null);
    assert.equal(cache.snapshot('a').providerCountState, 'unavailable');
  }
});
