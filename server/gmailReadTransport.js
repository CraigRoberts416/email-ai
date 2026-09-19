const RETRYABLE_REASONS = new Set(['rateLimitExceeded', 'userRateLimitExceeded', 'backendError']);
const SAFE_REASONS = new Set([...RETRYABLE_REASONS, 'dailyLimitExceeded', 'domainPolicy',
  'insufficientPermissions', 'forbidden', 'authError', 'notFound', 'badRequest']);

function gmailReadError(response, operation) {
  const detail = response.gmailFailure ?? {};
  const suffix = detail.reasons?.length ? ` (${detail.reasons.join(',')})` : '';
  return Object.assign(new Error(`${operation} failed: ${response.status}${suffix}`), {
    status: response.status, retryAfterMs: detail.retryAfterMs ?? 0,
  });
}

// All metadata, original-source, history and count reads share a mailbox budget.
// Current Gmail quotas charge messages.get 20 units; 80 units/sec leaves room
// below the 6,000 units/min allowance for interactive mutations and other clients.
// https://developers.google.com/workspace/gmail/api/reference/quota
function createGmailReadTransport({ fetch: request = (...args) => fetch(...args),
  now = () => Date.now(), random = Math.random, maxConcurrent = 4, unitsPerSecond = 80,
  maxAttempts = 4, logger = console, retryBaseMs = 1000 } = {}) {
  const accounts = new Map();

  function account(userId) {
    if (!accounts.has(userId)) accounts.set(userId, { queue: [], running: 0, nextStart: 0, cooldown: 0, timer: null });
    return accounts.get(userId);
  }

  function pump(state) {
    if (state.timer || !state.queue.length || state.running >= maxConcurrent) return;
    const pause = Math.max(state.nextStart, state.cooldown) - now();
    if (pause > 0) {
      state.timer = setTimeout(() => { state.timer = null; pump(state); }, pause);
      return;
    }
    // Foreground reads cannot be trapped behind queued archive batches.
    state.queue.sort((a, b) => b.priority - a.priority);
    const job = state.queue.shift();
    job.signal.removeEventListener('abort', job.abort);
    if (job.signal.aborted) { job.reject(job.signal.reason); pump(state); return; }
    state.running++;
    state.nextStart = now() + job.units * 1000 / unitsPerSecond;
    Promise.resolve().then(job.run).then(job.resolve, job.reject).finally(() => {
      state.running--;
      pump(state);
    });
    pump(state);
  }

  function schedule(state, run, { units, priority, signal }) {
    signal.throwIfAborted();
    return new Promise((resolve, reject) => {
      const job = { run, resolve, reject, units, priority, signal };
      job.abort = () => {
        const index = state.queue.indexOf(job);
        if (index >= 0) state.queue.splice(index, 1);
        reject(signal.reason);
        if (!state.queue.length && state.timer) { clearTimeout(state.timer); state.timer = null; }
      };
      signal.addEventListener('abort', job.abort, { once: true });
      state.queue.push(job);
      pump(state);
    });
  }

  return async function read(userId, url, accessToken, { units = 20, priority = 1, signal } = {}) {
    if (!userId) throw Error('Gmail read requires mailbox identity');
    const state = account(userId);
    // Caller-provided deadlines cover OAuth, queueing and request execution.
    // A background request also has a finite lifetime, including quota waits.
    const overallSignal = signal ?? AbortSignal.timeout(60_000);
    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      const response = await schedule(state, async () => {
        const response = await request(url, {
          headers: { Authorization: `Bearer ${accessToken}` },
          signal: signal ?? AbortSignal.any([overallSignal, AbortSignal.timeout(15_000)]),
        });
        if (response.ok) {
          // fetch resolves when headers arrive; the quota/concurrency slot
          // must also cover the actual message-body transfer and decoding.
          const body = await response.json();
          return { ok: true, status: response.status, headers: response.headers, json: async () => body };
        }
        const body = await response.json().catch(() => ({}));
        const reasons = [...new Set((body.error?.errors ?? []).map(error => error.reason)
          .filter(reason => SAFE_REASONS.has(reason)))];
        const retryable = response.status === 429 || response.status >= 500
          || (response.status === 403 && reasons.some(reason => RETRYABLE_REASONS.has(reason)));
        const retryAfter = response.headers?.get?.('retry-after');
        const seconds = Number(retryAfter);
        const providerDelay = retryAfter == null ? 0 : Number.isFinite(seconds)
          ? Math.max(0, seconds * 1000) : Math.max(0, Date.parse(retryAfter) - now()) || 0;
        const delay = retryable ? Math.max(providerDelay, retryBaseMs * 2 ** attempt + Math.floor(random() * 250)) : 0;
        response.gmailFailure = { reasons, retryable, retryAfterMs: delay };
        if (retryable) {
          state.cooldown = Math.max(state.cooldown, now() + delay);
          logger.warn(`[gmail] read throttled: status=${response.status} reason=${reasons.join(',') || 'unspecified'} retryInMs=${delay}`);
        }
        return response;
      }, { units, priority, signal: overallSignal });
      if (response.ok || !response.gmailFailure?.retryable
        || response.gmailFailure.retryAfterMs > 30_000 || attempt + 1 === maxAttempts) return response;
    }
  };
}

module.exports = { createGmailReadTransport, gmailReadError };
