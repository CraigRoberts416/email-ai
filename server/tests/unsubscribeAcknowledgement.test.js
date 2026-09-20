'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// Exercise the production POST handler with every external boundary replaced.
// New work is aborted at acknowledgement; no browser or mailbox is reachable.
const index = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
const route = index.slice(index.indexOf("app.post('/unsubscribe'"), index.indexOf("app.get('/unsubscribe/runs'"));

function fixture() {
  let handler;
  let responseStatus = 200;
  const workers = new Map();
  const statuses = new Map();
  const accountSignal = new AbortController().signal;
  const context = {
    app: { post: (_, callback) => { handler = callback; } },
    resolveUserId: async () => 'synthetic-account',
    require: name => {
      assert.equal(name, './accountAccess');
      return { signal: () => accountSignal };
    },
    userStore: { getUser: async () => ({ access_token: 'synthetic', refresh_token: 'synthetic' }) },
    messageStore: { getMessage: async () => ({ unsubscribeUrl: 'https://example.invalid/preferences', fromName: 'Synthetic sender' }) },
    unsubscribeStopped: new Set(),
    unsubscribeWorkers: workers,
    getUnsubscribeStatuses: () => statuses,
    beginUnsubscribeRun: () => {},
    emitUnsubscribeStatus: async (_, run) => {
      statuses.set(run.messageId, { ...run, status: run.step, runId: 'server-run', updatedAt: 1 });
    },
    safePageURL: value => value,
    resolveUserProfile: () => { throw new Error('Unexpected external work'); },
    URL, AbortController,
  };
  vm.runInNewContext(route, context);
  async function request(body) {
    let response;
    const res = {
      status: value => { responseStatus = value; return res; },
      json: value => {
        response = value;
        for (const worker of workers.get('synthetic-account')?.values() || []) worker.controller?.abort();
        return res;
      },
    };
    await handler({ body }, res);
    return response;
  }
  return { request, workers, statuses, context, statusCode: () => responseStatus };
}

test('already-running acknowledgement returns the actual existing attempt', async () => {
  const f = fixture();
  const active = { messageId: 'message', status: 'verifying', runId: 'run-a', attemptId: 'attempt-a', updatedAt: 100 };
  f.workers.set('synthetic-account', new Map([['message', {}]]));
  f.statuses.set('message', active);
  const ack = await f.request({ messageId: 'message', attemptId: 'attempt-b' });
  assert.equal(ack.alreadyRunning, true);
  assert.equal(ack.run, active);
  assert.equal(ack.run.attemptId, 'attempt-a');
});

test('worker discovered after source lookup still returns its authoritative attempt', async () => {
  const f = fixture();
  const active = { messageId: 'message', status: 'navigating', runId: 'run-a', attemptId: 'attempt-a' };
  f.context.messageStore.getMessage = async () => {
    f.workers.set('synthetic-account', new Map([['message', {}]]));
    f.statuses.set('message', active);
    return { unsubscribeUrl: 'https://example.invalid/preferences' };
  };
  const ack = await f.request({ messageId: 'message', attemptId: 'attempt-b' });
  assert.equal(ack.alreadyRunning, true);
  assert.equal(ack.run, active);
});

test('new acknowledgement identifies persisted queued intent before external work', async () => {
  const f = fixture();
  const ack = await f.request({ messageId: 'message', attemptId: 'attempt-b' });
  assert.equal(ack.alreadyRunning, false);
  assert.equal(ack.run.attemptId, 'attempt-b');
  assert.equal(ack.run.runId, 'server-run');
  assert.equal(ack.run.status, 'queued');
});

test('queued storage failure publishes failed/not_started before returning without external work', async () => {
  const f = fixture();
  const transitions = [];
  f.context.emitUnsubscribeStatus = async (_, run) => {
    transitions.push(run.step);
    // Production emits/caches status before awaiting the journal write.
    f.statuses.set(run.messageId, { ...run, status: run.step, runId: 'server-run', updatedAt: 1 });
    throw new Error('Synthetic storage unavailable');
  };
  const response = await f.request({ messageId: 'message', attemptId: 'attempt-b' });
  assert.equal(f.statusCode(), 503);
  assert.deepEqual(transitions, ['queued', 'failed']);
  const final = f.statuses.get('message');
  assert.equal(final.status, 'failed');
  assert.equal(final.outcome, 'not_started');
  assert.equal(final.message, 'Could not save this task. No request was sent to the sender.');
  assert.equal(response.error, final.message);
  assert.equal(f.workers.get('synthetic-account').has('message'), false);
  assert.ok(!transitions.includes('done'));
});
