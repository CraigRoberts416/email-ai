const test = require('node:test');
const assert = require('node:assert/strict');
const { createUnreadCountCache } = require('../unreadCountCache');

function providerFixture(t, providerFetch) {
  const paths = ['../db', '../userStore', '../messageStore', '../gmailSync'].map(require.resolve);
  const previous = new Map(paths.map(path => [path, require.cache[path]]));
  const originalFetch = global.fetch;
  for (const path of paths) delete require.cache[path];
  require.cache[paths[0]] = { id: paths[0], filename: paths[0], loaded: true, exports: {
    query: async () => ({ rows: [{ access_token: 'test-old', refresh_token: 'test-refresh', token_expiry: new Date(0) }] }),
  } };
  require.cache[paths[2]] = { id: paths[2], filename: paths[2], loaded: true, exports: {} };
  global.fetch = providerFetch;
  const gmail = require('../gmailSync');
  t.after(() => {
    global.fetch = originalFetch;
    for (const [path, module] of previous) {
      if (module) require.cache[path] = module; else delete require.cache[path];
    }
  });
  return gmail;
}

test('actual count adapter preserves caller cancellation through OAuth and Gmail lifecycle-composed signals', async t => {
  const controller = new AbortController();
  const urls = [];
  const signals = [];
  const gmail = providerFixture(t, async (url, options) => {
    urls.push(url);
    signals.push(options.signal);
    assert.equal(options.signal.aborted, false);
    return { ok: true, json: async () => url.includes('oauth2')
      ? { access_token: 'test-new', expires_in: 3600 }
      : { messagesUnread: 42 } };
  });
  assert.equal(await gmail.getUnreadCount('isolated-account', { signal: controller.signal }), 42);
  assert.deepEqual(urls, ['https://oauth2.googleapis.com/token',
    'https://gmail.googleapis.com/gmail/v1/users/me/labels/UNREAD']);
  const reason = new Error('synthetic deadline');
  controller.abort(reason);
  assert.equal(signals.length, 2);
  for (const signal of signals) {
    assert.equal(signal.aborted, true);
    assert.equal(signal.reason, reason);
  }
});

test('overall count deadline aborts stalled OAuth before any Gmail request can start', async t => {
  let signal;
  let requests = 0;
  const gmail = providerFixture(t, (url, options) => {
    requests++;
    assert.equal(url, 'https://oauth2.googleapis.com/token');
    signal = options.signal;
    return new Promise((_, reject) => signal.addEventListener('abort', () => reject(signal.reason), { once: true }));
  });
  const cache = createUnreadCountCache({ load: gmail.getUnreadCount, timeoutMs: 15, logger: { warn() {} } });
  assert.equal(await cache.refresh('isolated-account'), null);
  assert.equal(signal.aborted, true);
  assert.equal(requests, 1);
  assert.equal(cache.snapshot('isolated-account').unreadCount, null);
});
