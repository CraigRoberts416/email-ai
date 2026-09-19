const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const express = require('express');
const { registerNotificationMessageRoute } = require('../notificationMessage');

async function fixture(t, { missing = false, deleted = false, offline = false } = {}) {
  const calls = [];
  const app = express();
  registerNotificationMessageRoute(app, {
    resolveUserId: async req => req.get('test-account') || null,
    messageStore: {
      getMessage: async (account, id) => { calls.push(['get', account, id]); return missing ? null : { messageId: id, labelIds: [], subject: account }; },
      upsertMessages: async (account, records) => calls.push(['save', account, records]),
    },
    gmailSync: { fetchSenderRecords: async (account, ids) => {
      calls.push(['provider', account, ids]);
      if (offline) throw Error('offline');
      return deleted ? [] : ids.map(messageId => ({ messageId, labelIds: [], subject: account }));
    } },
    cardsForMessages: async (_req, account, records, options) => {
      assert.deepEqual(options, { generateHeroes: false });
      calls.push(['serialize', account]); return records;
    },
    logger: { warn() {} },
  });
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  const get = (account, id = 'same') => fetch(`http://127.0.0.1:${server.address().port}/messages/${id}/card`, {
    headers: account ? { 'test-account': account } : {},
  });
  return { get, calls };
}

test('notification card resolves read/archive mail by authenticated account, independent of feed pages', async t => {
  const h = await fixture(t);
  const one = await h.get('one'), two = await h.get('two');
  assert.equal(one.headers.get('cache-control'), 'no-store');
  assert.equal((await one.json()).card.subject, 'one');
  assert.equal((await two.json()).card.subject, 'two');
  assert.ok(!h.calls.some(([kind]) => kind === 'provider'), 'Existing card does not require a Gmail fetch');
});

test('missing cached notification card fetches only its metadata in the authenticated mailbox', async t => {
  const h = await fixture(t, { missing: true });
  assert.equal((await (await h.get('one')).json()).card.messageId, 'same');
  assert.deepEqual(h.calls.map(call => call[0]), ['get', 'provider', 'save', 'serialize']);
  assert.deepEqual(h.calls[1], ['provider', 'one', ['same']]);
});

test('deleted or failed provider lookup returns actionable failure, never an empty successful card', async t => {
  for (const [options, status] of [[{ missing: true, deleted: true }, 404], [{ missing: true, offline: true }, 502]]) {
    const h = await fixture(t, options);
    assert.equal((await h.get('one')).status, status);
    assert.ok(!h.calls.some(([kind]) => kind === 'save' || kind === 'serialize'));
  }
});

test('unauthenticated and malformed requests never access mailbox records', async t => {
  const h = await fixture(t);
  assert.equal((await h.get(null)).status, 401);
  assert.equal((await h.get('one', 'bad%20id')).status, 400);
  assert.deepEqual(h.calls, []);
});
