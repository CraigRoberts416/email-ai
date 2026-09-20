'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { PGlite } = require('@electric-sql/pglite');
const { createUnsubscribeJournal, recordStatus, reconciledStatus, safePageURL } = require('../unsubscribeJournal');

const schema = fs.readFileSync(path.join(__dirname, '../schema.sql'), 'utf8');
const baseTime = Date.parse('2026-09-19T12:00:00Z');
function status(messageId, state, offset, extra = {}) {
  return { messageId, runId: 'attempt-1', status: state, step: state,
    senderName: 'Synthetic Sender', message: `Synthetic ${state}`, updatedAt: baseTime + offset,
    sourceURL: 'https://example.invalid/preferences', ...extra };
}
async function database(t, location) {
  const db = new PGlite(location);
  t.after(() => db.close());
  await db.exec(schema);
  await db.query(`INSERT INTO users(user_id,access_token,refresh_token,token_expiry)
    VALUES ('mailbox-a','synthetic-a','synthetic-a',NOW()),('mailbox-b','synthetic-b','synthetic-b',NOW())`);
  return { db, journal: createUnsubscribeJournal({ query: (...args) => db.query(...args) }) };
}
function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

// Exercise the production route bodies without booting index.js, its workers,
// OAuth, Playwright or network listeners. A changed route boundary fails here
// rather than silently testing a handwritten duplicate implementation.
function routeFixture(journal) {
  const source = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
  const begin = source.indexOf("app.get('/unsubscribe/runs'");
  const end = source.indexOf('// ─── UI copy', begin);
  assert.ok(begin >= 0 && end > begin, 'production activity-route block must be found');
  const routes = new Map(), statuses = new Map(), workers = new Map(), writes = new Map();
  let identity = 'mailbox-a';
  const context = {
    app: { get: (route, handler) => routes.set(`GET ${route}`, handler),
      delete: (route, handler) => routes.set(`DELETE ${route}`, handler) },
    resolveUserId: async () => identity,
    unsubscribeJournal: journal,
    getUnsubscribeStatuses: id => {
      if (!statuses.has(id)) statuses.set(id, new Map());
      return statuses.get(id);
    },
    unsubscribeWorkers: workers,
    unsubscribeWrites: writes,
    reconciledStatus,
    Map,
  };
  vm.runInNewContext(source.slice(begin, end), context, { filename: 'index.js:unsubscribe-activity-routes' });
  async function invoke(key, req = {}) {
    const response = { statusCode: 200, body: null,
      status(code) { this.statusCode = code; return this; },
      json(value) { this.body = value; return this; } };
    await routes.get(key)({ params: {}, ...req }, response);
    return response;
  }
  return { invoke, statuses, workers, writes, setIdentity: value => { identity = value; } };
}

test('request-sent evidence remains distinct from sender confirmation across persistence and restart reconciliation', async t => {
  const { journal } = await database(t);
  const queued = recordStatus(null, status('same', 'queued', 0), baseTime);
  const sent = recordStatus(queued, status('same', 'done', 10, {
    outcome: 'request_sent', evidence: 'Provider accepted the outgoing request email.' }), baseTime + 10);
  await journal.save('mailbox-a', sent);
  const restored = reconciledStatus(await journal.get('mailbox-a', 'same'), false);
  assert.equal(restored.status, 'done');
  assert.equal(restored.outcome, 'request_sent');
  assert.match(restored.evidence, /outgoing request/);
  assert.deepEqual(restored.history.map(event => event.status), ['queued', 'done']);
  assert.equal(restored.history.some(event => event.outcome === 'sender_confirmed'), false);
});

test('new attempts reset handoff and history while retaining the message source, and repeated events do not inflate history', () => {
  const first = recordStatus(null, status('same', 'needs_you', 0, {
    handoffURL: 'https://example.invalid/old-session', outcome: 'sender_confirmed' }), baseTime);
  const duplicate = recordStatus(first, { ...first }, baseTime + 1);
  assert.equal(duplicate.history.length, 1);
  const next = recordStatus(duplicate, status('same', 'queued', 10, { runId: 'attempt-2' }), baseTime + 10);
  assert.deepEqual(next.history.map(event => event.status), ['queued']);
  assert.equal(next.handoffURL, null);
  assert.equal(next.outcome, null);
  assert.equal(next.sourceURL, 'https://example.invalid/preferences');
  assert.equal(first.history.length, 1, 'recording a next state does not mutate prior evidence');
});

test('restart exposes interruption as unknown without inventing a result or erasing available evidence', () => {
  for (const phase of ['queued', 'navigating', 'analyzing', 'filling', 'clicking', 'verifying']) {
    const prior = status('same', phase, 1, { evidence: 'Last visible sender-page title', handoffURL: 'https://example.invalid/review',
      history: [{ status: phase, at: baseTime + 1, message: 'Last observation' }] });
    const recovered = reconciledStatus(prior, false);
    assert.equal(recovered.status, 'unknown');
    assert.equal(recovered.outcome, 'outcome_unknown');
    assert.equal(recovered.evidence, prior.evidence);
    assert.equal(recovered.handoffURL, prior.handoffURL);
    assert.equal(recovered.updatedAt, prior.updatedAt, 'read-time reconciliation cannot invent a new observation timestamp');
    assert.deepEqual(recovered.history, prior.history);
    assert.equal(prior.status, phase, 'reading a status does not mutate the journal payload');
    assert.equal(reconciledStatus(prior, true), prior, 'a real live worker retains its observed active state');
  }
  for (const phase of ['done', 'failed', 'needs_you', 'no_link', 'still_sending', 'unknown']) {
    const prior = status('same', phase, 2);
    assert.equal(reconciledStatus(prior, false), prior, 'terminal state survives a worker restart');
  }
  assert.equal(reconciledStatus(null, false), null);
});

test('only usable sender pages enter human handoff data', () => {
  for (const value of ['javascript:alert(1)', 'file:///tmp/fixture', 'mailto:sender@example.invalid',
    'https://user:secret@example.invalid/preferences', 'not a URL', null]) {
    assert.equal(safePageURL(value), null);
  }
  assert.equal(safePageURL('https://example.invalid/preferences?source=email'), 'https://example.invalid/preferences?source=email');
  assert.equal(safePageURL('http://example.invalid/preferences'), 'http://example.invalid/preferences');
});

test('real SQL rejects delayed writes, sorts by observed time, and isolates equal message IDs by mailbox', async t => {
  const { journal } = await database(t);
  await journal.save('mailbox-a', status('same', 'done', 20, { outcome: 'sender_confirmed' }));
  await journal.save('mailbox-b', status('same', 'needs_you', 30));
  await journal.save('mailbox-a', status('other', 'failed', 40));
  await journal.save('mailbox-a', status('same', 'queued', 10, { runId: 'obsolete-attempt' }));
  assert.equal((await journal.get('mailbox-a', 'same')).status, 'done');
  assert.equal((await journal.get('mailbox-b', 'same')).status, 'needs_you');
  assert.deepEqual((await journal.list('mailbox-a')).map(run => run.messageId), ['other', 'same']);
  assert.deepEqual((await journal.list('mailbox-b')).map(run => run.messageId), ['same']);
  assert.equal(await journal.get('mailbox-a', 'missing'), null);
});

test('same-millisecond progress cannot replace terminal evidence in the recorder or durable journal', async t => {
  const { journal } = await database(t);
  const done = recordStatus(null, status('same', 'done', 20, { outcome: 'sender_confirmed', evidence: 'Sender confirmed removal' }), baseTime + 20);
  const delayed = status('same', 'clicking', 20);
  const recorded = recordStatus(done, delayed, baseTime + 20);
  assert.equal(recorded.status, 'done', 'recorder must reject same-attempt terminal regression');
  await journal.save('mailbox-a', done);
  await journal.save('mailbox-a', delayed);
  assert.equal((await journal.get('mailbox-a', 'same')).status, 'done', 'SQL must also reject a delayed writer bypassing the recorder');
  await journal.save('mailbox-a', status('same', 'queued', 30, { runId: 'attempt-2' }));
  assert.equal((await journal.get('mailbox-a', 'same')).runId, 'attempt-2', 'a later fresh attempt is allowed');
});

test('a retry inside an active batch uses its own attempt identity through recording and SQL', async t => {
  const { journal } = await database(t);
  const first = recordStatus(null, status('same', 'needs_you', 1, {
    runId: 'shared-batch', attemptId: 'first-intent', handoffURL: 'https://example.invalid/old-session',
    outcome: 'outcome_unknown', evidence: 'Previous attempt stopped at a login page' }), baseTime + 1);
  const retry = recordStatus(first, status('same', 'queued', 2, {
    runId: 'shared-batch', attemptId: 'second-intent' }), baseTime + 2);
  assert.equal(retry.status, 'queued', 'a batch ID is not a per-sender attempt ID');
  assert.equal(retry.attemptId, 'second-intent');
  assert.deepEqual(retry.history.map(event => event.status), ['queued']);
  assert.equal(retry.handoffURL, null);
  assert.equal(retry.outcome, null);
  assert.equal(retry.evidence, undefined);
  await journal.save('mailbox-a', first);
  await journal.save('mailbox-a', retry);
  assert.equal((await journal.get('mailbox-a', 'same')).attemptId, 'second-intent');
  await journal.save('mailbox-a', first);
  assert.equal((await journal.get('mailbox-a', 'same')).status, 'queued', 'delayed prior attempt cannot reappear');
  const done = recordStatus(retry, status('same', 'done', 3, {
    runId: 'shared-batch', attemptId: 'second-intent', outcome: 'sender_confirmed' }), baseTime + 3);
  await journal.save('mailbox-a', done);
  await journal.save('mailbox-a', status('same', 'clicking', 3, { runId: 'shared-batch', attemptId: 'second-intent' }));
  assert.equal((await journal.get('mailbox-a', 'same')).outcome, 'sender_confirmed');
});

test('remove, clear and foreign-key cleanup affect only their specified scope', async t => {
  const { db, journal } = await database(t);
  await journal.save('mailbox-a', status('same', 'done', 1));
  await journal.save('mailbox-a', status('kept', 'needs_you', 2));
  await journal.save('mailbox-b', status('same', 'done', 3));
  await journal.remove('mailbox-a', 'same');
  assert.equal(await journal.get('mailbox-a', 'same'), null);
  assert.ok(await journal.get('mailbox-a', 'kept'));
  assert.ok(await journal.get('mailbox-b', 'same'));
  await journal.remove('mailbox-a', 'same');
  await journal.clear('mailbox-a');
  assert.deepEqual(await journal.list('mailbox-a'), []);
  assert.equal((await journal.list('mailbox-b')).length, 1);
  await db.query('DELETE FROM users WHERE user_id = $1', ['mailbox-b']);
  assert.deepEqual(await journal.list('mailbox-b'), []);
});

test('receipts survive a real PGlite close and reopen without promoting an interrupted task', async t => {
  const location = fs.mkdtempSync(path.join(os.tmpdir(), 'unsubscribe-journal-'));
  let db = new PGlite(location);
  t.after(async () => { await db.close(); fs.rmSync(location, { recursive: true, force: true }); });
  await db.exec(schema);
  await db.query(`INSERT INTO users(user_id,access_token,refresh_token,token_expiry)
    VALUES ('mailbox-a','synthetic','synthetic',NOW())`);
  await createUnsubscribeJournal({ query: (...args) => db.query(...args) }).save('mailbox-a', status('same', 'clicking', 50, {
    evidence: 'Submitted form; response has not arrived' }));
  await db.close();
  db = new PGlite(location);
  const restored = await createUnsubscribeJournal({ query: (...args) => db.query(...args) }).get('mailbox-a', 'same');
  assert.equal(restored.status, 'clicking');
  assert.equal(reconciledStatus(restored, false).outcome, 'outcome_unknown');
  assert.match(restored.evidence, /response has not arrived/);
});

test('production activity routes use authenticated identity and reconcile worker loss rather than claiming success', async t => {
  const { journal } = await database(t);
  await journal.save('mailbox-a', status('same', 'clicking', 1));
  await journal.save('mailbox-b', status('same', 'done', 2, { outcome: 'sender_confirmed' }));
  const routes = routeFixture(journal);
  let response = await routes.invoke('GET /unsubscribe/runs', { query: { userId: 'mailbox-b' }, body: { userId: 'mailbox-b' } });
  assert.equal(response.statusCode, 200);
  assert.equal(response.body.runs.length, 1);
  assert.equal(response.body.runs[0].status, 'unknown');
  assert.equal(response.body.runs[0].outcome, 'outcome_unknown');
  routes.workers.set('mailbox-a', new Map([['same', {}]]));
  response = await routes.invoke('GET /unsubscribe/:messageId/status', { params: { messageId: 'same' } });
  assert.equal(response.body.status, 'clicking');
  response = await routes.invoke('DELETE /unsubscribe/:messageId/receipt', { params: { messageId: 'same' } });
  assert.equal(response.statusCode, 409);
  assert.ok(await journal.get('mailbox-a', 'same'));
  response = await routes.invoke('GET /unsubscribe/:messageId/status', { params: { messageId: 'missing' } });
  assert.equal(response.statusCode, 404);
  routes.setIdentity(null);
  for (const route of ['GET /unsubscribe/runs', 'GET /unsubscribe/:messageId/status', 'DELETE /unsubscribe/:messageId/receipt']) {
    response = await routes.invoke(route, { params: { messageId: 'same' } });
    assert.equal(response.statusCode, 401);
  }
  assert.equal((await journal.get('mailbox-b', 'same')).outcome, 'sender_confirmed');
});

test('receipt deletion waits for its pending write and cannot delete another mailbox record', async t => {
  const { journal } = await database(t);
  await journal.save('mailbox-a', status('same', 'done', 1));
  await journal.save('mailbox-b', status('same', 'done', 1));
  const routes = routeFixture(journal), gate = deferred();
  routes.writes.set('mailbox-a:same', gate.promise.then(() => journal.save('mailbox-a', status('same', 'done', 2))));
  let returned = false;
  const deletion = routes.invoke('DELETE /unsubscribe/:messageId/receipt', { params: { messageId: 'same' } })
    .then(response => { returned = true; return response; });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(returned, false);
  assert.ok(await journal.get('mailbox-a', 'same'));
  gate.resolve();
  assert.equal((await deletion).body.success, true);
  assert.equal(await journal.get('mailbox-a', 'same'), null);
  assert.ok(await journal.get('mailbox-b', 'same'));
});

test('a worker starting while receipt deletion waits retains its durable task', async t => {
  const { journal } = await database(t);
  await journal.save('mailbox-a', status('same', 'done', 1));
  const routes = routeFixture(journal), gate = deferred();
  routes.writes.set('mailbox-a:same', gate.promise);
  const deletion = routes.invoke('DELETE /unsubscribe/:messageId/receipt', { params: { messageId: 'same' } });
  await new Promise(resolve => setImmediate(resolve));
  routes.workers.set('mailbox-a', new Map([['same', {}]]));
  gate.resolve();
  assert.equal((await deletion).statusCode, 409);
  assert.ok(await journal.get('mailbox-a', 'same'));
});

test('an atomic receipt delete cannot erase a new attempt committed while its SQL is queued', async t => {
  const { db, journal } = await database(t);
  const reachedDelete = deferred(), releaseDelete = deferred();
  const delayedJournal = createUnsubscribeJournal({ query: async (sql, parameters) => {
    if (sql.startsWith('DELETE FROM unsubscribe_tasks')) {
      reachedDelete.resolve();
      await releaseDelete.promise;
    }
    return db.query(sql, parameters);
  } });
  const old = status('same', 'done', 1, { attemptId: 'old-intent', outcome: 'request_sent' });
  const fresh = status('same', 'queued', 2, { attemptId: 'fresh-intent' });
  await journal.save('mailbox-a', old);
  const routes = routeFixture(delayedJournal);
  routes.statuses.set('mailbox-a', new Map([['same', old]]));
  const deletion = routes.invoke('DELETE /unsubscribe/:messageId/receipt', { params: { messageId: 'same' } });
  await reachedDelete.promise;
  routes.workers.set('mailbox-a', new Map([['same', {}]]));
  routes.statuses.get('mailbox-a').set('same', fresh);
  await journal.save('mailbox-a', fresh);
  releaseDelete.resolve();
  assert.equal((await deletion).statusCode, 409, 'changed receipt is reported instead of a false successful removal');
  assert.equal((await journal.get('mailbox-a', 'same')).attemptId, 'fresh-intent');
  assert.equal(routes.statuses.get('mailbox-a').get('same'), fresh, 'new in-memory observation also survives');
});

test('journal and route failures reject success instead of returning an empty successful activity list', async () => {
  const journal = createUnsubscribeJournal({ query: async () => { throw Error('Synthetic database unavailable'); } });
  await assert.rejects(journal.save('mailbox-a', status('same', 'queued', 1)), /database unavailable/);
  const routes = routeFixture(journal);
  for (const route of ['GET /unsubscribe/runs', 'GET /unsubscribe/:messageId/status', 'DELETE /unsubscribe/:messageId/receipt']) {
    const response = await routes.invoke(route, { params: { messageId: 'same' } });
    assert.equal(response.statusCode, 503);
    assert.equal(response.body.success, undefined);
    assert.equal(response.body.runs, undefined);
  }
});
