const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

function harness(respond) {
  const effects = { states: [], checkpoints: [], archiveCursors: [], inventory: [], reconciled: [], removed: [], writes: [], labels: [] };
  const user = { history_id: 'start', email: 'owner@gmail.com' };
  const users = {
    beginAllMailSync: async id => { effects.states.push([id, 'syncing']); return { generation: 'generation-a', startedAt: '2026-09-19T10:00:00Z', cursor: user.all_mail_sync_cursor }; },
    getUser: async () => user, getValidAccessToken: async () => 'fixture-token',
    updateHistoryId: async (id, value) => effects.checkpoints.push([id, value]),
    setAllMailSyncState: async (id, state) => effects.states.push([id, state]),
    setUnreadSyncState: async () => {},
    setAllMailSyncCursor: async (id, cursor) => { effects.archiveCursors.push([id, cursor]); user.all_mail_sync_cursor = cursor; },
  };
  const messages = {
    markAllMailSeen: async (id, ids, generation) => effects.inventory.push([id, ids, generation]),
    reconcileAllMail: async (id, generation, startedAt) => effects.reconciled.push([id, generation, startedAt]),
    upsertMessages: async (id, records) => effects.writes.push([id, records]),
    getMessage: async () => ({ labelIds: ['UNREAD', 'INBOX'] }),
    updateLabelIds: async (id, message, labels) => effects.labels.push([id, message, labels]),
    removeMessages: async (id, ids) => effects.removed.push([id, ids]),
  };
  const module = { exports: {} };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, 'gmailSync.js'), 'utf8'), {
    module, console: { log() {}, warn() {}, error() {} }, URLSearchParams, AbortSignal, setTimeout,
    fetch: async url => {
      const result = await respond(new URL(url));
      return { ok: result.status === undefined || result.status < 400, status: result.status ?? 200,
        json: async () => result.body ?? {} };
    },
    require: name => {
      if (name === './userStore') return users;
      if (name === './messageStore') return messages;
      if (name === './unreadBacklog') return { createUnreadBacklog: () => ({ ensure() {} }) };
      throw Error(`Unexpected dependency ${name}`);
    },
  });
  return { sync: module.exports, effects, user };
}
const plain = value => JSON.parse(JSON.stringify(value));

test('initial archive sync coalesces duplicate starts and completes only after every list page', async () => {
  let lists = 0;
  const { sync, effects } = harness(async url => {
    if (url.pathname.endsWith('/messages')) {
      lists++;
      return { body: url.searchParams.has('pageToken') ? { messages: [{ id: 'old' }] }
        : { messages: [{ id: 'new' }], nextPageToken: 'older' } };
    }
    return { body: { id: url.pathname.split('/').at(-1), internalDate: '100', payload: { headers: [] } } };
  });
  const one = sync.initialSync('a'); const two = sync.initialSync('a');
  assert.equal(one, two, 'One import per account on this process');
  await one;
  assert.equal(lists, 2);
  assert.deepEqual(plain(effects.inventory.map(([,ids]) => ids)), [['new'],['old']]);
  assert.deepEqual(plain(effects.reconciled), [['a','generation-a','2026-09-19T10:00:00Z']]);
  assert.deepEqual(plain(effects.states), [['a','syncing'],['a','complete']]);
  assert.deepEqual(plain(effects.writes.map(([, records]) => records.map(r => r.messageId))), [['new'],['old']]);
});

test('archive metadata failure stays failed and can retry, never declares complete', async () => {
  let failing = true;
  const { sync, effects } = harness(async url => {
    if (url.pathname.endsWith('/messages')) return { body: { messages: [{ id: 'mail' }] } };
    return failing ? { status: 429 } : { body: { id: 'mail', payload: { headers: [] } } };
  });
  await assert.rejects(sync.initialSync('a'), /429/);
  assert.deepEqual(plain(effects.states), [['a','syncing'],['a','failed']]);
  assert.equal(effects.reconciled.length, 0, 'A failed import cannot prune any mirror rows');
  failing = false;
  await sync.initialSync('a');
  assert.equal(effects.states.at(-1)[1], 'complete');
});

test('later history pages apply label order and provider deletions before final checkpoint', async () => {
  const requested = [];
  const { sync, effects } = harness(async url => {
    assert.ok(url.pathname.endsWith('/history'));
    assert.ok(url.searchParams.getAll('historyTypes').includes('messageDeleted'));
    requested.push(url.searchParams.get('pageToken'));
    return { body: url.searchParams.has('pageToken')
      ? { historyId: 'final', history: [{ labelsAdded: [{ message: { id: 'kept' }, labelIds: ['UNREAD'] }],
        messagesDeleted: [{ message: { id: 'deleted' } }] }] }
      : { historyId: 'early', nextPageToken: 'page2', history: [{
        labelsRemoved: [{ message: { id: 'kept' }, labelIds: ['UNREAD'] }],
        messagesAdded: [{ message: { id: 'deleted' } }] }] } };
  });
  await sync.incrementalSync('a');
  assert.deepEqual(requested, [null, 'page2']);
  assert.deepEqual(plain(effects.removed), [['a',['deleted']]]);
  assert.deepEqual(plain(effects.labels), [['a','kept',['UNREAD','INBOX']]]);
  assert.equal(effects.writes.length, 0, 'Deleted message is not fetched or resurrected');
  assert.deepEqual(plain(effects.checkpoints), [['a','final']]);
});

test('failed later history page cannot advance checkpoint or apply a partial update', async () => {
  const { sync, effects } = harness(async url => url.searchParams.has('pageToken')
    ? { status: 503 }
    : { body: { historyId: 'early', nextPageToken: 'page2', history: [{ messagesDeleted: [{ message: { id: 'deleted' } }] }] } });
  await assert.rejects(sync.incrementalSync('a'), /503/);
  assert.deepEqual(effects.checkpoints, []);
  assert.deepEqual(effects.removed, []);
  assert.deepEqual(effects.writes, []);
});


test('archive retry resumes after the last stored page instead of restarting a large mailbox', async () => {
  let fail = true; const pages = [];
  const { sync, effects } = harness(async url => {
    if (url.pathname.endsWith('/messages')) {
      const page = url.searchParams.get('pageToken'); pages.push(page);
      if (page === 'older' && fail) return { status: 503 };
      return { body: page ? { messages: [{ id: 'old' }] } : { messages: [{ id: 'new' }], nextPageToken: 'older' } };
    }
    return { body: { id: url.pathname.split('/').at(-1), payload: { headers: [] } } };
  });
  await assert.rejects(sync.initialSync('a'), /503/);
  assert.deepEqual(plain(effects.archiveCursors), [['a','older']]);
  fail = false;
  await sync.initialSync('a');
  assert.deepEqual(pages, [null, 'older', 'older']);
  assert.equal(effects.states.at(-1)[1], 'complete');
});
