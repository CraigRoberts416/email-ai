const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const filename = path.join(__dirname, 'conversations.js');
const isolated = new Module(filename, module);
isolated.filename = filename;
isolated.require = name => {
  if (name === './db') return { query: () => { throw Error('Live DB forbidden'); } };
  if (['./gmailSync','./messageStore','./replyText','./emailAttachments'].includes(name)) return {};
  throw Error(`Unexpected dependency ${name}`);
};
isolated._compile(fs.readFileSync(filename, 'utf8'), filename);
const { createConversationDirectory } = isolated.exports;
const turn = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };
const person = (id, lastAt, unread = true) => ({ id, lastAt, participants: [], messageCount: 1, unread, preview: 'Source snippet' });
const source = { sourceVersion: 'inventory-one-complete', sourceComplete: true, sourceState: 'complete' };

test('HTTP path returns immediately while aggregation is blocked, coalesces requests, and publishes partial pages', async () => {
  const first = deferred(), done = deferred(); let scans = 0;
  const directory = createConversationDirectory({ aggregate: async (user, own, { onBatch }) => {
    scans++;
    await first.promise;
    onBatch([person('c',300),person('b',200)]);
    await done.promise;
    return [person('c',300),person('b',200),person('a',100,false)];
  } });
  const start = performance.now();
  const initial = directory.page('account','owner@example.com', source);
  assert.ok(performance.now() - start < 100, 'No aggregation query or body lookup blocks the HTTP path');
  assert.deepEqual(initial.conversations, []);
  assert.equal(initial.historyComplete, false);
  assert.equal(initial.totalConversations, null);
  assert.equal(initial.historySyncState, 'indexing');
  await turn();
  directory.page('account','owner@example.com', source);
  assert.equal(scans, 1, 'Repeated polls share the in-flight scan');
  first.resolve(); await turn();
  const partial = directory.page('account','owner@example.com', { ...source, limit: 1 });
  assert.equal(partial.conversations[0].id, 'c');
  assert.equal(partial.totalConversations, null);
  assert.ok(partial.nextCursor);
  const tail = directory.page('account','owner@example.com', { ...source, cursor: partial.nextCursor });
  assert.deepEqual(tail.conversations.map(c => c.id), ['b']);
  assert.ok(tail.nextCursor, 'An unfinished aggregation cannot claim a verified pagination end');
  done.resolve(); await turn();
  const last = directory.page('account','owner@example.com', { ...source, cursor: tail.nextCursor });
  assert.deepEqual(last.conversations.map(c => c.id), ['a']);
  assert.equal(last.totalConversations, 3);
  assert.equal(last.unreadConversations, 2);
  assert.equal(last.historyComplete, true);
  assert.equal(last.nextCursor, null);
});

test('completed cursor snapshot remains available while a head refresh scans in the background', async () => {
  let time = 0, scans = 0; const next = deferred();
  const directory = createConversationDirectory({ now: () => time, ttlMs: 30, aggregate: async () => {
    scans++;
    if (scans > 1) await next.promise;
    return [person('c',300),person('b',200),person('a',100)];
  } });
  directory.page('a','me',source); await turn();
  const first = directory.page('a','me',{ ...source, limit: 1 });
  time = 31;
  const refreshing = directory.page('a','me',source);
  assert.equal(refreshing.historyComplete, false);
  assert.equal(refreshing.conversations.length, 3, 'New aggregation retains the cached rows while waiting');
  const older = directory.page('a','me',{ ...source, cursor: first.nextCursor });
  assert.equal(older.historyComplete, true);
  assert.deepEqual(older.conversations.map(c => c.id), ['b','a']);
  assert.throws(() => directory.page('b','me',{ ...source, cursor: first.nextCursor }), /Invalid conversation cursor/);
  next.resolve(); await turn();
  assert.equal(scans, 2);
});

test('exact totals require a finished inventory and a scan of that inventory generation', async () => {
  let scans = 0;
  const directory = createConversationDirectory({ aggregate: async () => { scans++; return []; } });
  const importing = { sourceVersion: 'importing', sourceComplete: false, sourceState: 'syncing' };
  directory.page('a','me',importing); await turn();
  const partial = directory.page('a','me',importing);
  assert.equal(partial.historyComplete, false);
  assert.equal(partial.totalConversations, null, 'Local zero during import is unknown');
  const newInventory = directory.page('a','me',source);
  assert.equal(newInventory.historyComplete, false, 'Provider completion starts a fresh aggregation');
  await turn();
  const empty = directory.page('a','me',source);
  assert.equal(empty.historyComplete, true);
  assert.equal(empty.totalConversations, 0);
  assert.equal(scans, 2);
});

test('failed background scan retains partial rows and retries without surfacing a false empty result', async () => {
  let time = 0, scans = 0;
  const directory = createConversationDirectory({ now: () => time, logger: { warn() {} }, aggregate: async (user, own, { onBatch }) => {
    scans++; onBatch([person('known',100)]);
    if (scans === 1) throw Error('temporary DB outage');
    return [person('known',100)];
  } });
  directory.page('a','me',source); await turn();
  const failed = directory.page('a','me',source);
  assert.equal(failed.historySyncState, 'failed');
  assert.equal(failed.historyComplete, false);
  assert.equal(failed.conversations[0].id, 'known');
  assert.equal(failed.totalConversations, null);
  time = 5001;
  directory.page('a','me',source); await turn();
  assert.equal(directory.page('a','me',source).historyComplete, true);
  assert.equal(scans, 2);
});
