const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const Module = require('node:module');
const { PGlite } = require('@electric-sql/pglite');
const { createAccountDisconnect, registerAccountDisconnectRoute } = require('../accountDisconnect');
const access = require('../accountAccess');

function deferred() { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; }
function fixture(overrides = {}) {
  const calls = [];
  let user = { access_token: 'synthetic-access', refresh_token: 'synthetic-refresh', push_token: 'synthetic-device' };
  const deps = {
    userStore: {
      getUser: async id => { calls.push(['read', id]); return { ...user }; },
      disconnectUser: async id => { calls.push(['clear', id]); user = { ...user, access_token: '', refresh_token: '', push_token: null }; },
      resetInterruptedProcessing: async id => { calls.push(['reset', id]); },
    },
    access: { suspend: id => calls.push(['suspend', id]) },
    processingWorker: { stopWorker: async id => { calls.push(['drain', id]); } },
    onDisconnect: async id => { calls.push(['jobs', id]); },
    stopWatch: async token => { calls.push(['watch', token]); return true; },
    refreshDetachedToken: async token => { calls.push(['badge', token]); },
    ...overrides,
  };
  return { calls, deps, disconnect: createAccountDisconnect(deps) };
}

test('disconnect clears credentials before cleanup and repeat calls need no provider credential', async () => {
  const f = fixture();
  const result = await f.disconnect('a');
  assert.deepEqual(result, { disconnected: true, watchStopped: true, storedMailDeleted: false, googleGrantRevoked: false });
  assert.ok(f.calls.findIndex(x => x[0] === 'suspend') < f.calls.findIndex(x => x[0] === 'clear'));
  assert.ok(f.calls.findIndex(x => x[0] === 'clear') < f.calls.findIndex(x => x[0] === 'watch'));
  await f.disconnect('a');
  assert.equal(f.calls.filter(x => x[0] === 'watch').length, 1);
});

test('overlapping requests coalesce and cannot confirm before current work has drained', async () => {
  const drain = deferred();
  const f = fixture({ processingWorker: { stopWorker: () => drain.promise } });
  const a = f.disconnect('a');
  const b = f.disconnect('a');
  assert.equal(a, b);
  let complete = false;
  a.then(() => { complete = true; });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(complete, false);
  drain.resolve();
  await a;
  assert.equal(f.calls.filter(x => x[0] === 'clear').length, 1);
});

test('provider and badge failures cannot preserve server access or invent provider revocation', async () => {
  const f = fixture({ stopWatch: async () => { throw Error('offline'); }, refreshDetachedToken: async () => { throw Error('offline'); } });
  const result = await f.disconnect('a');
  assert.equal(result.disconnected, true);
  assert.equal(result.watchStopped, false);
  assert.equal(result.googleGrantRevoked, false);
  assert.equal((await f.deps.userStore.getUser('a')).refresh_token, '');
});

test('durable deletion failure rejects confirmation and a later retry remains possible', async () => {
  const f = fixture();
  const original = f.deps.userStore.disconnectUser;
  let fail = true;
  f.deps.userStore.disconnectUser = async id => { if (fail) throw Error('DB unavailable'); return original(id); };
  await assert.rejects(f.disconnect('a'), /DB unavailable/);
  assert.equal(f.calls.some(x => x[0] === 'watch'), false);
  fail = false;
  assert.equal((await f.disconnect('a')).disconnected, true);
});

test('lifecycle gate aborts only the selected account and rejects stale registration generations', async () => {
  const before = access.version();
  const signalA = access.signal('gate-a');
  const signalB = access.signal('gate-b');
  access.suspend('gate-a');
  assert.equal(signalA.aborted, true);
  assert.equal(signalB.aborted, false);
  assert.throws(() => access.assertActive('gate-a'), /disconnected/);
  assert.throws(() => access.assertNotDisconnectedSince('gate-a', before), /registration/);
  access.assertNotDisconnectedSince('gate-b', before);
  const reconnect = access.version();
  access.assertNotDisconnectedSince('gate-a', reconnect);
  access.activate('gate-a');
  assert.equal(access.signal('gate-a').aborted, false);
  assert.equal(signalA.aborted, true, 'old requests remain aborted after a reconnect');
});

test('route authenticates identity and reports cleanup failures without false success', async () => {
  let route;
  let identity = null;
  const seen = [];
  registerAccountDisconnectRoute({ delete: (path, handler) => { assert.equal(path, '/auth/account'); route = handler; } }, {
    resolveUserId: async () => identity,
    disconnect: async id => { seen.push(id); if (id === 'failed') throw Error('DB'); return { disconnected: true }; },
  });
  const response = () => ({ code: 200, body: null, status(code) { this.code = code; return this; }, json(body) { this.body = body; return this; } });
  let res = response(); await route({ body: { userId: 'someone-else' } }, res);
  assert.equal(res.code, 401); assert.deepEqual(seen, []);
  identity = 'authenticated'; res = response(); await route({ body: { userId: 'someone-else' } }, res);
  assert.deepEqual(seen, ['authenticated']); assert.equal(res.body.disconnected, true);
  identity = 'failed'; res = response(); await route({}, res);
  assert.equal(res.code, 503); assert.equal(res.body.disconnected, undefined);
});

test('real SQL clears one account, retains its mail and blocks late refresh credential resurrection', async t => {
  const db = new PGlite(); t.after(() => db.close());
  await db.exec(`CREATE TABLE users(user_id TEXT PRIMARY KEY, email TEXT, access_token TEXT NOT NULL,
    refresh_token TEXT NOT NULL, token_expiry TIMESTAMPTZ NOT NULL, push_token TEXT, watch_expiry TIMESTAMPTZ, updated_at TIMESTAMPTZ);
    CREATE TABLE messages(user_id TEXT REFERENCES users(user_id), message_id TEXT, ai_status TEXT);
    INSERT INTO users VALUES ('a','a@example.invalid','access-a','refresh-a',NOW(),'device',NOW(),NOW()),
      ('b','b@example.invalid','access-b','refresh-b',NOW(),'device',NOW(),NOW());
    INSERT INTO messages VALUES ('a','kept-mail','processing'),('b','other-mail','processing');`);
  const filename = require.resolve('../userStore');
  const isolated = new Module(filename, module);
  isolated.require = dependency => dependency === './db' ? { query: (...args) => db.query(...args) }
    : require(require.resolve(dependency, { paths: [require('node:path').dirname(filename)] }));
  isolated._compile(fs.readFileSync(filename, 'utf8'), filename);
  const users = isolated.exports;
  await users.disconnectUser('a');
  await users.updateTokens('a', { accessToken: 'stale-refresh-result', tokenExpiry: Date.now() + 30000 });
  await users.resetInterruptedProcessing('a');
  const a = await users.getUser('a');
  assert.equal(a.access_token, ''); assert.equal(a.refresh_token, ''); assert.equal(a.push_token, null);
  assert.equal((await users.getUser('b')).refresh_token, 'refresh-b');
  assert.deepEqual((await users.getAllUsers()).map(x => x.user_id), ['b']);
  assert.deepEqual((await db.query('SELECT message_id, ai_status FROM messages ORDER BY user_id')).rows,
    [{ message_id: 'kept-mail', ai_status: 'queued' }, { message_id: 'other-mail', ai_status: 'processing' }]);
  await assert.rejects(users.getValidAccessToken('a'), /disconnected/);
});

test('real worker drains submitted model work and never begins the next interpretation stage after disconnect', async () => {
  const interpretation = deferred(); const risk = deferred(); const started = deferred();
  const calls = [];
  const filename = require.resolve('../processingWorker');
  const isolated = new Module(filename, module);
  const dependencies = {
    './accountAccess': access,
    './gmailSync': { fetchFullMessage: async () => ({ payload: {} }) },
    './emailCleaner': { cleanEmailForAI: () => ({}) },
    './emailImage': { extractHtml: () => '', pickCandidates: () => [], resolveBest: async () => null },
    './emailAttachments': { extractAttachments: () => [] },
    './messageStore': {
      getNextToProcess: async () => { calls.push('next'); return 'synthetic-message'; },
      setAiStatus: async () => {}, failAttempt: async () => { calls.push('failed'); },
    },
  };
  isolated.require = name => { assert.ok(name in dependencies); return dependencies[name]; };
  isolated._compile(fs.readFileSync(filename, 'utf8'), filename);
  const worker = isolated.exports;
  worker.init({
    emitSSE() {}, detectRiskSignals: () => risk.promise,
    streamInterpretEmail: async () => { started.resolve(); await interpretation.promise; },
    streamDecideActionSurface: async () => { calls.push('next-stage'); },
  });
  worker.startWorker('worker-fixture');
  await started.promise;
  access.suspend('worker-fixture');
  let drained = false;
  const stopped = worker.stopWorker('worker-fixture').then(() => { drained = true; });
  interpretation.resolve();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(drained, false, 'risk work already submitted must drain too');
  risk.resolve(); await stopped;
  assert.deepEqual(calls, ['next'], 'no further stage, next message, or failed-attempt penalty');
});

test('real registration cannot race disconnect cleanup or restore a stale request', async t => {
  const db = new PGlite(); t.after(() => db.close());
  await db.exec(`CREATE TABLE users(user_id TEXT PRIMARY KEY, email TEXT, access_token TEXT NOT NULL,
    refresh_token TEXT NOT NULL, token_expiry TIMESTAMPTZ NOT NULL, push_token TEXT, watch_expiry TIMESTAMPTZ,
    onboarding_history_id TEXT, updated_at TIMESTAMPTZ);
    CREATE TABLE messages(user_id TEXT REFERENCES users(user_id), message_id TEXT, ai_status TEXT);
    INSERT INTO users VALUES ('registration-race','race@example.invalid','old-access','old-refresh',NOW(),NULL,NULL,'1',NOW());`);
  const filename = require.resolve('../userStore');
  const isolated = new Module(filename, module);
  isolated.require = dependency => dependency === './db' ? { query: (...args) => db.query(...args) }
    : require(require.resolve(dependency, { paths: [require('node:path').dirname(filename)] }));
  isolated._compile(fs.readFileSync(filename, 'utf8'), filename);
  const users = isolated.exports;
  const enteredDrain = deferred(); const drain = deferred();
  const disconnect = createAccountDisconnect({
    userStore: users,
    processingWorker: { stopWorker: () => { enteredDrain.resolve(); return drain.promise; } },
    stopWatch: async () => true,
  });
  const staleVersion = access.version();
  const closing = disconnect('registration-race');
  await enteredDrain.promise;
  const fields = { email: 'race@example.invalid', accessToken: 'new-access', refreshToken: 'new-refresh', tokenExpiry: Date.now() + 3600000 };
  const stale = users.upsertUser('registration-race', { ...fields, connectionVersion: staleVersion });
  const staleRejected = assert.rejects(stale, /disconnected during registration/);
  let reconnected = false;
  const fresh = users.upsertUser('registration-race', { ...fields, connectionVersion: access.version() })
    .then(() => { reconnected = true; });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(reconnected, false, 'fresh reconnect waits until old cleanup has finished');
  assert.equal((await users.getUser('registration-race')).refresh_token, '');
  drain.resolve();
  await closing; await staleRejected; await fresh;
  const connected = await users.getUser('registration-race');
  assert.equal(connected.access_token, 'new-access');
  assert.equal(connected.refresh_token, 'new-refresh');
  assert.equal(access.signal('registration-race').aborted, false);
});
