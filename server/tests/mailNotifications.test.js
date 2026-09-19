const test = require('node:test');
const assert = require('node:assert/strict');
const { createMailNotifications, buildAPNsPayload } = require('../mailNotifications');

const token = 'ab'.repeat(32);
const record = {
  messageId: 'arrival', requiresAttention: true, aiStatus: 'done', labelIds: ['UNREAD'],
  fromName: 'Sender', fromEmail: 'sender@example.test', subject: 'Actual subject', snippet: 'Private body',
};

function harness({ counts = { a: 2, b: 3 }, fail = false, configured = true, loadCount, countCacheOptions } = {}) {
  const users = new Map(['a', 'b'].map(id => [id, { user_id: id, push_token: token }]));
  const records = new Map([[record.messageId, { ...record }]]);
  const pending = new Set();
  const claimed = new Set();
  const sent = new Set();
  const pushes = [];
  const countCalls = [];
  let failing = fail;
  const service = createMailNotifications({
    apns: {
      isConfigured: () => configured,
      send: async (_token, payload) => {
        if (failing) throw Object.assign(new Error('Unavailable'), { code: 'ServiceUnavailable' });
        pushes.push(payload);
      },
    },
    expo: { sendPushNotificationsAsync: async () => { throw new Error('native token reached Expo'); } },
    isExpoPushToken: value => typeof value === 'string' && value.startsWith('ExponentPushToken['),
    userStore: {
      getUser: async id => users.get(id),
      getUsersByPushToken: async value => [...users.values()].filter(user => user.push_token === value),
      updatePushToken: async (id, value) => { users.get(id).push_token = value; },
    },
    messageStore: {
      queueNotifications: async (_user, ids) => ids.forEach(id => pending.add(id)),
      getPendingNotifications: async () => [...pending].filter(id => !sent.has(id)).map(id => records.get(id)),
      claimNotification: async (_user, id) => {
        if (claimed.has(id) || sent.has(id)) return false;
        claimed.add(id);
        return true;
      },
      finishNotification: async (_user, id, delivered) => {
        claimed.delete(id);
        if (delivered) sent.add(id);
      },
    },
    gmailSync: { getUnreadCount: async (id, options) => {
      countCalls.push(id);
      if (loadCount) return loadCount(id, options);
      if (counts[id] instanceof Error) throw counts[id];
      return counts[id];
    } },
    countCacheOptions,
    logger: { warn() {} },
  });
  return { service, records, pushes, sent, claimed, users, counts, countCalls, recover: () => { failing = false; } };
}

test('native visible push contains source sender/subject and combined badge, not the email body', async () => {
  const h = harness();
  await h.service.notifyMailbox('a', ['arrival']);
  assert.equal(h.pushes.length, 1);
  assert.equal(h.pushes[0].aps.badge, 5);
  assert.deepEqual(h.pushes[0].aps.alert, { title: 'Sender', body: 'Actual subject' });
  assert.equal(h.pushes[0].messageId, 'arrival');
  assert.ok(!JSON.stringify(h.pushes[0]).includes('Private body'));
});

test('model-pending, unimportant, or already-read messages remain silent while badge updates', async () => {
  for (const change of [{ aiStatus: 'processing' }, { requiresAttention: false }, { labelIds: [] }]) {
    const h = harness();
    h.records.set('arrival', { ...record, ...change });
    await h.service.notifyMailbox('a', ['arrival']);
    assert.equal(h.pushes[0].aps.alert, undefined);
    assert.equal(h.pushes[0].aps.badge, 5);
    assert.equal(h.sent.size, 0);
  }
});

test('worker completion delivers an arrival queued before classification', async () => {
  const h = harness();
  h.records.set('arrival', { ...record, aiStatus: 'processing' });
  await h.service.notifyMailbox('a', ['arrival']);
  h.records.set('arrival', record);
  await h.service.notifyMailbox('a');
  assert.equal(h.pushes.filter(push => push.aps.alert).length, 1);
});

test('duplicate and concurrent arrivals alert once; unchanged badge avoids repeated pushes', async () => {
  const h = harness();
  await Promise.all([h.service.notifyMailbox('a', ['arrival', 'arrival']), h.service.notifyMailbox('a', ['arrival'])]);
  await h.service.notifyMailbox('b');
  assert.equal(h.pushes.length, 1);
});

test('combined badge reaches zero after provider changes and has no sound or alert', async () => {
  const h = harness();
  await h.service.notifyMailbox('a');
  h.counts.a = 0;
  h.counts.b = 0;
  await h.service.notifyMailbox('b');
  assert.equal(h.pushes.at(-1).aps.badge, 0);
  assert.equal(h.pushes.at(-1).aps.sound, undefined);
  assert.equal(h.pushes.at(-1).aps.alert, undefined);
});

test('one unavailable account preserves previous badge rather than publishing partial sum', async () => {
  const h = harness({ counts: { a: 9, b: new Error('offline') } });
  assert.equal(await h.service.badgeCount(token), null);
  await h.service.notifyMailbox('a');
  assert.equal(h.pushes.length, 0);
  for (const count of [null, undefined, NaN, -1]) assert.equal(buildAPNsPayload('a', count).aps.badge, undefined);
});

test('failed provider request keeps notification pending and retry succeeds', async () => {
  const h = harness({ fail: true });
  await h.service.notifyMailbox('a', ['arrival']);
  assert.equal(h.sent.size, 0);
  assert.equal(h.claimed.size, 0);
  h.recover();
  await h.service.notifyMailbox('a');
  assert.equal(h.sent.size, 1);
  assert.equal(h.pushes.filter(push => push.aps.alert).length, 1);
});

test('missing APNs configuration leaves queue unclaimed for later configuration', async () => {
  const h = harness({ configured: false });
  await h.service.notifyMailbox('a', ['arrival']);
  assert.equal(h.claimed.size, 0);
  assert.equal(h.sent.size, 0);
  assert.equal(h.pushes.length, 0);
});

test('disconnect subtracts the removed mailbox and final disconnect clears badge', async () => {
  const h = harness();
  h.users.get('a').push_token = null;
  await h.service.refreshDetachedToken(token);
  assert.equal(h.pushes.at(-1).aps.badge, 3);
  h.users.get('b').push_token = null;
  await h.service.refreshDetachedToken(token);
  assert.equal(h.pushes.at(-1).aps.badge, 0);
});

test('mailbox changes invalidate feed verification even without a push token or configured APNs', async () => {
  for (const configured of [false, true]) {
    const h = harness({ configured });
    if (configured) h.users.get('a').push_token = null;
    assert.equal(await h.service.unreadCount('a'), 2);
    assert.equal(h.service.unreadCountSnapshot('a').unreadCount, 2);
    h.counts.a = 1;
    await h.service.notifyMailbox('a');
    assert.equal(h.service.unreadCountSnapshot('a').unreadCount, null);
    assert.equal(await h.service.unreadCount('a'), 1);
    assert.equal(h.pushes.length, 0);
  }
});

test('badge waits for a fresh combined count while feed stays immediate; read invalidation rejects partial old sums', async () => {
  let resolveB;
  const b = new Promise(resolve => { resolveB = resolve; });
  const h = harness({ loadCount: id => id === 'a' ? 2 : b });
  h.service.unreadCountSnapshot('b');
  const badge = h.service.badgeCount(token);
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(h.countCalls.sort(), ['a', 'b'], 'Feed and badge share b request');
  assert.equal(h.service.unreadCountSnapshot('b').unreadCount, null);
  h.service.invalidateUnreadCount('a');
  resolveB(3);
  assert.equal(await badge, null, 'A read during the other account request must invalidate the sum');
});

test('interpretation completion reuses verified counts instead of repeatedly invalidating mailbox state', async () => {
  const h = harness();
  await h.service.notifyMailbox('a');
  const initialCalls = h.countCalls.length;
  await h.service.notifyMailbox('a', [], { mailboxChanged: false });
  await h.service.notifyMailbox('a', [], { mailboxChanged: false });
  assert.equal(h.countCalls.length, initialCalls);
  assert.equal(h.service.unreadCountSnapshot('a').providerCountState, 'fresh');
});
