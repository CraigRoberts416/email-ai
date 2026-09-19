const test = require('node:test');
const assert = require('node:assert/strict');
const { setTimeout: wait } = require('node:timers/promises');
const { createGmailReadTransport, gmailReadError } = require('../gmailReadTransport');
const quiet = { warn() {} };
const response = (status = 200, reason, retryAfter) => ({
  ok: status < 400, status, headers: { get: () => retryAfter ?? null },
  json: async () => ({ error: { message: 'private provider detail must not escape',
    errors: reason ? [{ reason, message: 'private email content' }] : [] } }),
});
const url = 'https://gmail.googleapis.com/gmail/v1/users/me/messages/private-id';

test('shared account pacing prioritizes foreground reads and bounds concurrency across simultaneous jobs', async () => {
  const started = []; const releases = [];
  let active = 0, peak = 0;
  const read = createGmailReadTransport({ maxConcurrent: 2, unitsPerSecond: 1000, logger: quiet,
    fetch: async path => {
      started.push({ path, at: Date.now() }); active++; peak = Math.max(peak, active);
      await new Promise(resolve => releases.push(resolve)); active--;
      return response();
    },
  });
  const archive1 = read('account', 'archive1', 'secret', { units: 20, priority: 0 });
  const archive2 = read('account', 'archive2', 'secret', { units: 20, priority: 0 });
  const archive3 = read('account', 'archive3', 'secret', { units: 20, priority: 0 });
  const foreground = read('account', 'foreground', 'secret', { units: 1, priority: 3 });
  await wait(40);
  assert.deepEqual(started.map(item => item.path), ['archive1', 'foreground']);
  assert.ok(started[1].at - started[0].at >= 15, 'Weighted interval applies before the next read');
  releases.shift()(); releases.shift()();
  await wait(35);
  releases.shift()(); releases.shift()();
  await Promise.all([archive1, archive2, archive3, foreground]);
  assert.equal(peak, 2);
});

test('queued abort never sends a request and one mailbox cannot hold another mailbox behind its backfill', async () => {
  const started = []; let release;
  const read = createGmailReadTransport({ maxConcurrent: 1, unitsPerSecond: Infinity, logger: quiet,
    fetch: async path => { started.push(path); if (path === 'first') await new Promise(resolve => { release = resolve; }); return response(); },
  });
  const first = read('a', 'first', 'secret');
  const controller = new AbortController();
  const queued = read('a', 'cancelled', 'secret', { signal: controller.signal });
  controller.abort(new Error('caller cancelled'));
  await assert.rejects(queued, /caller cancelled/);
  await read('b', 'independent', 'secret');
  assert.deepEqual(started, ['first', 'independent']);
  release(); await first;
  await read('a', 'next', 'secret');
  assert.deepEqual(started, ['first', 'independent', 'next']);
});

test('a read slot remains occupied until the full response body is consumed', async () => {
  const started = []; let finishBody;
  const read = createGmailReadTransport({ maxConcurrent: 1, unitsPerSecond: Infinity, logger: quiet,
    fetch: async path => {
      started.push(path);
      return { ok: true, status: 200, json: async () => {
        if (path === 'large-body') await new Promise(resolve => { finishBody = resolve; });
        return { id: path };
      } };
    },
  });
  const first = read('a', 'large-body', 'secret');
  const second = read('a', 'next', 'secret');
  await wait(5);
  assert.deepEqual(started, ['large-body'], 'Receiving headers must not release the active-transfer slot');
  finishBody();
  assert.deepEqual(await (await first).json(), { id: 'large-body' });
  await second;
  assert.deepEqual(started, ['large-body', 'next']);
});

test('transient quota 403 retries with safe reasons; permanent policy 403 is never retried', async () => {
  let calls = 0; const logs = [];
  const read = createGmailReadTransport({ unitsPerSecond: Infinity, retryBaseMs: 1, random: () => 0,
    logger: { warn: message => logs.push(message) },
    fetch: async () => ++calls < 3 ? response(403, 'userRateLimitExceeded') : response(),
  });
  assert.equal((await read('a', url, 'secret')).status, 200);
  assert.equal(calls, 3);
  assert.match(logs[0], /reason=userRateLimitExceeded/);
  assert.doesNotMatch(logs.join(' '), /secret|private|https/);
  for (const reason of ['domainPolicy', 'insufficientPermissions', 'dailyLimitExceeded', 'unknown-private-value']) {
    let attempts = 0;
    const permanent = createGmailReadTransport({ unitsPerSecond: Infinity, logger: quiet,
      fetch: async () => { attempts++; return response(403, reason); },
    });
    const result = await permanent('b', url, 'secret');
    assert.equal(attempts, 1);
    const error = gmailReadError(result, 'metadata fetch');
    assert.equal(error.status, 403);
    assert.doesNotMatch(error.message, /private|secret/);
    if (reason !== 'unknown-private-value') assert.match(error.message, new RegExp(reason));
  }
});

test('Retry-After seconds and HTTP dates are honored without retrying early or blocking an interactive deadline', async () => {
  const epoch = Date.parse('2026-09-19T15:00:00Z');
  for (const retryAfter of ['120', 'Sat, 19 Sep 2026 15:02:00 GMT']) {
    let calls = 0;
    const read = createGmailReadTransport({ now: () => epoch, random: () => 0, logger: quiet,
      fetch: async () => { calls++; return response(429, null, retryAfter); },
    });
    const result = await read('a', url, 'secret');
    assert.equal(result.gmailFailure.retryAfterMs, 120_000);
    assert.equal(calls, 1, 'Long provider delay is returned to resumable import, not retried immediately');
    const controller = new AbortController();
    const pending = read('a', 'foreground', 'secret', { priority: 3, signal: controller.signal });
    controller.abort(new Error('interactive deadline'));
    await assert.rejects(pending, /interactive deadline/);
    assert.equal(calls, 1);
  }
});

test('persistent transient failures stop after a bounded attempt budget, and 404 remains available to reconciliation', async () => {
  let calls = 0;
  const read = createGmailReadTransport({ unitsPerSecond: Infinity, retryBaseMs: 1, random: () => 0, logger: quiet,
    fetch: async () => { calls++; return response(503, 'backendError'); },
  });
  const failed = await read('a', url, 'secret');
  assert.equal(calls, 4);
  assert.equal(failed.status, 503);
  assert.match(gmailReadError(failed, 'metadata fetch').message, /503 \(backendError\)/);
  const missing = createGmailReadTransport({ logger: quiet, fetch: async () => response(404, 'notFound') });
  assert.equal((await missing('a', url, 'secret')).status, 404);
});
