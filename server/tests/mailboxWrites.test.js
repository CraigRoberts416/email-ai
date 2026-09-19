const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const Module = require('node:module');
const { createMailboxWriter } = require('../mailboxWrites');

const flush = () => new Promise(resolve => setImmediate(resolve));
function deferred() {
  let resolve;
  const promise = new Promise(yes => { resolve = yes; });
  return { promise, resolve };
}

function fixture(run) {
  const events = [];
  let connections = 0;
  const pool = { connect: async () => {
    const id = ++connections;
    events.push({ id, sql: 'CONNECT' });
    return {
      query: async (sql, params) => {
        events.push({ id, sql, params });
        if (sql.startsWith('WRITE')) return run(sql, id);
        return { rows: [] };
      },
      release: () => events.push({ id, sql: 'RELEASE' }),
    };
  } };
  const waits = [];
  const writer = createMailboxWriter({ pool, wait: async ms => waits.push(ms) });
  return { writer, events, waits };
}

test('same-mailbox bulk writes serialize before checkout, while another mailbox can proceed', async () => {
  const held = deferred();
  const h = fixture(async sql => {
    if (sql === 'WRITE archive') await held.promise;
    return { rows: [{ sql }] };
  });
  const archive = h.writer.write('a', 'WRITE archive', []);
  await flush();
  const unread = h.writer.write('a', 'WRITE unread', []);
  const other = h.writer.write('b', 'WRITE other', []);
  await other;
  assert.equal(h.events.filter(event => event.sql === 'CONNECT').length, 2,
    'Waiting same-account jobs cannot consume all pool connections');
  assert.equal(h.events.some(event => event.sql === 'WRITE unread'), false);
  held.resolve();
  await Promise.all([archive, unread]);
  const archiveCommit = h.events.findIndex(event => event.id === 1 && event.sql === 'COMMIT');
  const unreadWrite = h.events.findIndex(event => event.sql === 'WRITE unread');
  assert.ok(archiveCommit < unreadWrite);
  for (const id of [1, 2, 3]) {
    const statements = h.events.filter(event => event.id === id);
    assert.deepEqual(statements.map(event => event.sql), ['CONNECT', 'BEGIN',
      'SELECT pg_advisory_xact_lock(hashtextextended($1, 0))',
      id === 1 ? 'WRITE archive' : id === 2 ? 'WRITE other' : 'WRITE unread', 'COMMIT', 'RELEASE']);
    assert.deepEqual(statements[2].params, [`decision-inbox:mailbox-write:${id === 2 ? 'b' : 'a'}`]);
  }
});

test('deadlock rolls back and releases before a bounded retry; successful result is preserved', async () => {
  let attempts = 0;
  const h = fixture(async () => {
    if (++attempts < 3) throw Object.assign(new Error('deadlock detected'), { code: '40P01' });
    return { rows: [{ changed: true }] };
  });
  assert.deepEqual(await h.writer.write('a', 'WRITE reconciliation', []), { rows: [{ changed: true }] });
  assert.deepEqual(h.waits, [50, 100]);
  assert.equal(h.events.filter(event => event.sql === 'ROLLBACK').length, 2);
  assert.equal(h.events.filter(event => event.sql === 'COMMIT').length, 1);
  assert.equal(h.events.filter(event => event.sql === 'RELEASE').length, 3);
});

test('permanent failures and exhausted retries propagate, without poisoning later account writes', async () => {
  let fail = true;
  const h = fixture(async () => {
    if (fail) throw Object.assign(new Error('deadlock detected'), { code: '40P01' });
    return { rows: [] };
  });
  await assert.rejects(h.writer.write('a', 'WRITE failed', []), { code: '40P01' });
  assert.equal(h.events.filter(event => event.sql === 'ROLLBACK').length, 3);
  fail = false;
  await h.writer.write('a', 'WRITE later', []);
  const permanent = fixture(async () => { throw Object.assign(new Error('constraint'), { code: '23505' }); });
  await assert.rejects(permanent.writer.write('a', 'WRITE invalid', []), { code: '23505' });
  assert.equal(permanent.events.filter(event => event.sql === 'CONNECT').length, 1);
  assert.deepEqual(permanent.waits, []);
});

test('all message-store bulk mutation paths request the same mailbox lock; single-row reads stay independent', async () => {
  const calls = [];
  const filename = require.resolve('../messageStore');
  const isolated = new Module(filename, module);
  isolated.filename = filename;
  isolated.require = name => {
    if (name === './db') return { query: async (...args) => { calls.push(args); return { rows: [] }; } };
    if (name === './feedStorage') return { CARD_COLUMNS: [], createFeedStorage: () => ({}) };
    throw Error(`Unexpected dependency ${name}`);
  };
  isolated._compile(fs.readFileSync(filename, 'utf8'), filename);
  const store = isolated.exports;
  await store.upsertMessages('a', [{ messageId: 'one' }]);
  await store.reconcileUnreadLabels('a', ['one'], new Date());
  await store.queueNotifications('a', ['one']);
  await store.removeMessages('a', ['one']);
  await store.markAllMailSeen('a', ['one'], 'generation');
  await store.reconcileAllMail('a', 'generation', new Date());
  assert.equal(calls.length, 6);
  assert.ok(calls.every(([, , options]) => options?.mailboxWriteUserId === 'a'));
  await store.updateLabelIds('a', 'one', []);
  await store.getMessage('a', 'one');
  assert.ok(calls.slice(6).every(([, , options]) => options === undefined));
});
