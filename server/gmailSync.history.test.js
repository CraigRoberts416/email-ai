const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

function harness(respond) {
  let clock = Date.now();
  class TestDate extends Date { static now() { return clock; } }
  const effects = { states: [], checkpoints: [], archiveCursors: [], inventory: [], reconciled: [], removed: [], writes: [], labels: [] };
  const user = { history_id: 'start', email: 'owner@gmail.com' };
  const users = {
    beginAllMailSync: async id => { effects.states.push([id, 'syncing']); return { generation: 'generation-a', startedAt: '2026-09-19T10:00:00Z', cursor: user.all_mail_sync_cursor, revalidate: user.all_mail_sync_revalidate }; },
    getUser: async () => user, getValidAccessToken: async () => 'fixture-token',
    updateHistoryId: async (id, value) => effects.checkpoints.push([id, value]),
    setAllMailSyncState: async (id, state, options = {}) => {
      effects.states.push([id, state]);
      if (options.revalidate) user.all_mail_sync_revalidate = true;
      if (state === 'complete') user.all_mail_sync_revalidate = false;
      return true;
    },
    setUnreadSyncState: async () => {},
    setAllMailSyncCursor: async (id, cursor) => { effects.archiveCursors.push([id, cursor]); user.all_mail_sync_cursor = cursor; return true; },
  };
  const messages = {
    archiveMetadataNeeded: async (id, ids) => ids,
    markAllMailSeen: async (id, ids, generation) => effects.inventory.push([id, ids, generation]),
    reconcileAllMail: async (id, generation, startedAt) => effects.reconciled.push([id, generation, startedAt]),
    upsertMessages: async (id, records) => effects.writes.push([id, records]),
    getMessage: async () => ({ labelIds: ['UNREAD', 'INBOX'] }),
    updateLabelIds: async (id, message, labels) => effects.labels.push([id, message, labels]),
    removeMessages: async (id, ids) => effects.removed.push([id, ids]),
  };
  const module = { exports: {} };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, 'gmailSync.js'), 'utf8'), {
    module, console: { log() {}, warn() {}, error() {} }, URLSearchParams, AbortSignal, setTimeout, Date: TestDate,
    fetch: async url => {
      const result = await respond(new URL(url));
      return { ok: result.status === undefined || result.status < 400, status: result.status ?? 200,
        json: async () => result.body ?? {} };
    },
    require: name => {
      if (name === './userStore') return users;
      if (name === './messageStore') return messages;
      if (name === './unreadBacklog') return { createUnreadBacklog: () => ({ ensure() {} }) };
      if (name === './gmailReadTransport') return {
        gmailReadError: (response, operation) => Object.assign(new Error(`${operation} failed: ${response.status}`), { status: response.status }),
        createGmailReadTransport: () => async (id, url) => {
          const result = await respond(new URL(url));
          return { ok: result.status === undefined || result.status < 400, status: result.status ?? 200,
            json: async () => result.body ?? {} };
        },
      };
      throw Error(`Unexpected dependency ${name}`);
    },
  });
  return { sync: module.exports, effects, user, users, messages, advance: ms => { clock += ms; } };
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
  const { sync, effects, advance } = harness(async url => {
    if (url.pathname.endsWith('/messages')) return { body: { messages: [{ id: 'mail' }] } };
    return failing ? { status: 429 } : { body: { id: 'mail', payload: { headers: [] } } };
  });
  await assert.rejects(sync.initialSync('a'), /429/);
  assert.deepEqual(plain(effects.states), [['a','syncing'],['a','failed']]);
  assert.equal(effects.reconciled.length, 0, 'A failed import cannot prune any mirror rows');
  failing = false;
  await sync.initialSync('a');
  assert.equal(effects.states.at(-1)[1], 'failed', 'Polling during cooldown cannot start another import');
  advance(60_000);
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
  const { sync, effects, advance } = harness(async url => {
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
  advance(60_000);
  await sync.initialSync('a');
  assert.deepEqual(pages, [null, 'older', 'older']);
  assert.equal(effects.states.at(-1)[1], 'complete');
});

test('archive inventory reuses known metadata but accounts for every provider ID and refreshes restored mail', async () => {
  const fetched = [];
  const { sync, effects, messages } = harness(async url => {
    if (url.pathname.endsWith('/messages')) return { body: { messages: ['known','restored','missing','deleted'].map(id => ({ id })) } };
    const id = url.pathname.split('/').at(-1); fetched.push(id);
    if (id === 'deleted') return { status: 404 };
    return { body: { id, labelIds: ['INBOX'], payload: { headers: [{ name: 'From', value: 'person@example.com' }] } } };
  });
  messages.archiveMetadataNeeded = async (account, ids) => {
    assert.equal(account, 'a');
    assert.deepEqual(plain(ids), ['known','restored','missing','deleted']);
    return ['restored','missing','deleted'];
  };
  await sync.initialSync('a');
  assert.deepEqual(fetched.sort(), ['deleted','missing','restored']);
  assert.deepEqual(plain(effects.inventory.flatMap(([,ids]) => ids)).sort(), ['known','missing','restored']);
  assert.equal(effects.reconciled.length, 1, 'Only the successful full enumeration may finish inventory');
  assert.deepEqual(plain(effects.writes[0][1][0].labelIds), ['INBOX'], 'Restored mail persists provider labels');
});

test('a failed later metadata group retains earlier writes and avoids re-fetching them on resume', async () => {
  const ids = Array.from({ length: 21 }, (_, index) => `m${index}`);
  const retained = new Set(); const fetched = [];
  let fail = true;
  const { sync, effects, messages, advance } = harness(async url => {
    if (url.pathname.endsWith('/messages')) return { body: { messages: ids.map(id => ({ id })) } };
    const id = url.pathname.split('/').at(-1); fetched.push(id);
    if (id === 'm20' && fail) return { status: 403 };
    return { body: { id, payload: { headers: [] } } };
  });
  messages.archiveMetadataNeeded = async (_account, listed) => listed.filter(id => !retained.has(id));
  const save = messages.upsertMessages;
  messages.upsertMessages = async (account, records) => {
    await save(account, records); records.forEach(record => retained.add(record.messageId));
  };
  await assert.rejects(sync.initialSync('a'), /403/);
  assert.equal(retained.size, 20);
  assert.deepEqual(effects.archiveCursors, [], 'The provider page checkpoint is not advanced on partial success');
  assert.equal(effects.reconciled.length, 0);
  fail = false; advance(60_000);
  await sync.initialSync('a');
  assert.equal(fetched.length, 22, 'Resume fetches only the failed group, not already saved metadata');
  assert.equal(retained.size, 21);
  assert.equal(effects.reconciled.length, 1);
});

test('expired history requests complete metadata revalidation even when cached immutable fields exist', async () => {
  let oldMetadataFetches = 0;
  const { sync, effects, messages } = harness(async url => {
    if (url.pathname.endsWith('/history')) return { status: 404 };
    if (url.pathname.endsWith('/profile')) return { body: { historyId: 'current' } };
    if (url.pathname.endsWith('/messages')) return { body: { messages: url.searchParams.get('maxResults') === '100'
      ? [{ id: 'head' }] : [{ id: 'old-known' }] } };
    const id = url.pathname.split('/').at(-1);
    if (id === 'old-known') oldMetadataFetches++;
    return { body: { id, labelIds: ['CATEGORY_PERSONAL'], payload: { headers: [] } } };
  });
  messages.archiveMetadataNeeded = async () => [];
  await sync.incrementalSync('a');
  await sync.initialSync('a');
  assert.equal(oldMetadataFetches, 1, 'An expired history gap cannot reuse potentially stale category labels');
  const old = effects.writes.flatMap(([, records]) => records).find(record => record.messageId === 'old-known');
  assert.deepEqual(plain(old.labelIds), ['CATEGORY_PERSONAL']);
  assert.equal(effects.states.at(-1)[1], 'complete');
});

test('history expiry during an active inventory runs a fresh revalidating generation before completion', async () => {
  let releaseOldPage, oldPageStarted;
  const waiting = new Promise(resolve => { oldPageStarted = resolve; });
  const paused = new Promise(resolve => { releaseOldPage = resolve; });
  let inventories = 0, oldMetadata = 0;
  const { sync, users, messages } = harness(async url => {
    if (url.pathname.endsWith('/history')) return { status: 404 };
    if (url.pathname.endsWith('/profile')) return { body: { historyId: 'now' } };
    if (url.pathname.endsWith('/messages')) {
      if (url.searchParams.get('maxResults') === '100') return { body: { messages: [] } };
      if (++inventories === 1) { oldPageStarted(); await paused; }
      return { body: { messages: [{ id: 'old-known' }] } };
    }
    oldMetadata++;
    return { body: { id: 'old-known', labelIds: ['CATEGORY_PERSONAL'], payload: { headers: [] } } };
  });
  let generation = null, generationNumber = 0, revalidate = false;
  const completed = [];
  users.beginAllMailSync = async () => {
    generation ??= `g${++generationNumber}`;
    return { generation, revalidate, cursor: null, startedAt: new Date(0) };
  };
  users.setAllMailSyncState = async (_id, state, options = {}) => {
    if (options.generation && options.generation !== generation) return false;
    if (state === 'pending') { generation = null; revalidate ||= options.revalidate; }
    if (state === 'complete') { completed.push(generation); revalidate = false; }
    return true;
  };
  users.setAllMailSyncCursor = async (_id, _cursor, expected) => expected === generation;
  messages.archiveMetadataNeeded = async () => [];
  const first = sync.initialSync('a');
  await waiting;
  await sync.incrementalSync('a');
  assert.equal(revalidate, true);
  releaseOldPage();
  await first;
  assert.equal(inventories, 2, 'Superseded job restarts recovery without waiting for another app request');
  assert.equal(oldMetadata, 1, 'New recovery revalidates the existing message');
  assert.deepEqual(completed, ['g2'], 'Old generation cannot complete or clear recovery');
});
