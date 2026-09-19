const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const express = require('express');
const { createMarkReadHandler } = require('../messageRead');

async function fixture(t, { labels = ['UNREAD', 'INBOX'], readFailure = false, modifyFailure = false } = {}) {
  const requests = [];
  const stored = [];
  const events = [];
  const invalidations = [];
  let current = labels;
  const app = express();
  app.patch('/messages/:messageId/read', createMarkReadHandler({
    resolveUserId: async req => req.get('test-auth') === 'yes' ? 'account-a' : null,
    userStore: { getValidAccessToken: async () => 'isolated-test-token' },
    messageStore: { updateLabelIds: async (userId, id, next) => stored.push({ userId, id, labels: next }) },
    emitSSE: (_id, event) => events.push(event),
    notifyMailbox: async () => {},
    invalidateUnreadCount: userId => invalidations.push({ userId, requests: requests.length, stored: stored.length }),
    fetch: async (url, options) => {
      assert.ok(url.startsWith('https://gmail.googleapis.com/gmail/v1/users/me/messages/'));
      requests.push(options.method ?? 'GET');
      if (options.method === 'POST') {
        if (modifyFailure) return { ok: false };
        assert.deepEqual(JSON.parse(options.body), { removeLabelIds: ['UNREAD'] });
        current = current.filter(label => label !== 'UNREAD');
      } else if (readFailure) { return { ok: false }; }
      return { ok: true, json: async () => ({ id: 'message-a', labelIds: [...current] }) };
    },
    logger: { error() {}, warn() {} },
  }));
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  const url = `http://127.0.0.1:${server.address().port}/messages/message-a/read`;
  const request = (authorized = true) => fetch(url, { method: 'PATCH', headers: authorized ? { 'test-auth': 'yes' } : {} });
  return { request, requests, stored, events, invalidations };
}

test('read API confirms provider wasUnread in HTTP and SSE and saves the provider label set', async t => {
  const h = await fixture(t);
  const response = await h.request();
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { success: true, wasUnread: true, readChanged: true });
  assert.deepEqual(h.requests, ['GET', 'POST']);
  assert.deepEqual(h.stored, [{ userId: 'account-a', id: 'message-a', labels: ['INBOX'] }]);
  assert.deepEqual(h.events, [{ type: 'message-read', messageId: 'message-a', wasUnread: true, readChanged: true }]);
  assert.deepEqual(h.invalidations, [
    { userId: 'account-a', requests: 0, stored: 0 },
    { userId: 'account-a', requests: 2, stored: 1 },
  ], 'Invalidate before provider work and after committed labels, before a successful response');
});

test('already-read external mail reconciles the database without a second unread decrement or modify request', async t => {
  const h = await fixture(t, { labels: ['STARRED'] });
  assert.deepEqual(await (await h.request()).json(), { success: true, wasUnread: false, readChanged: false });
  assert.deepEqual(h.requests, ['GET']);
  assert.deepEqual(h.stored[0].labels, ['STARRED']);
  assert.equal(h.events[0].wasUnread, false);
  assert.equal(h.invalidations.length, 2, 'External reads invalidate counts even without a modify request');
});

test('concurrent read retries serialize, with only one confirmed unread transition', async t => {
  const h = await fixture(t);
  const responses = await Promise.all([h.request(), h.request()]);
  const results = await Promise.all(responses.map(response => response.json()));
  assert.equal(results.filter(result => result.wasUnread).length, 1);
  assert.equal(h.requests.filter(method => method === 'POST').length, 1);
  assert.equal(h.events.filter(event => event.wasUnread).length, 1);
});

test('lookup or write failures never publish success, change the mirror, or emit a read event', async t => {
  for (const options of [{ readFailure: true }, { modifyFailure: true }]) {
    const h = await fixture(t, options);
    assert.equal((await h.request()).status, 502);
    assert.equal(h.stored.length, 0);
    assert.equal(h.events.length, 0);
    assert.equal(h.invalidations.length, 2, 'Failure cannot leave a count fetched during the read trusted');
  }
});

test('unauthorized read requests do not contact Gmail', async t => {
  const h = await fixture(t);
  assert.equal((await h.request(false)).status, 401);
  assert.equal(h.requests.length, 0);
  assert.equal(h.invalidations.length, 0);
});
