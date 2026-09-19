// Provider verification must never hold cached feed cards behind a network
// request. A snapshot is synchronous; a badge can await the shared refresh.
function createUnreadCountCache({ load, now = Date.now, freshMs = 30000,
  timeoutMs = 15000, retryMs = 5000, logger = console }) {
  const entries = new Map();
  const validCount = value => Number.isSafeInteger(value) && value >= 0;

  function entryFor(userId) {
    if (!entries.has(userId)) entries.set(userId, {
      generation: 0, count: null, observedAt: null, valid: false, retryAt: 0, flight: null,
    });
    return entries.get(userId);
  }

  function fresh(entry, notBefore = 0) {
    return entry.valid && validCount(entry.count) && entry.observedAt >= notBefore
      && now() - entry.observedAt < freshMs;
  }

  function invalidate(userId) {
    const entry = entryFor(userId);
    entry.generation++;
    entry.valid = false;
    entry.retryAt = 0;
    const flight = entry.flight;
    entry.flight = null;
    flight?.controller.abort(new Error('Unread count superseded by mailbox change'));
  }

  function refresh(userId, { force = false, notBefore = 0 } = {}) {
    const entry = entryFor(userId);
    if (entry.flight) return entry.flight.promise;
    if (!force && fresh(entry, notBefore)) return Promise.resolve(entry.count);
    if (now() < entry.retryAt) return Promise.resolve(null);

    const generation = entry.generation;
    const startedAt = now();
    const controller = new AbortController();
    const flight = { controller, promise: null };
    entry.flight = flight;
    let timer;
    let abortListener;
    const aborted = new Promise((_, reject) => {
      abortListener = () => reject(controller.signal.reason);
      controller.signal.addEventListener('abort', abortListener, { once: true });
      timer = setTimeout(() => controller.abort(new Error('Unread count timed out')), timeoutMs);
    });
    // The outer deadline also covers token refresh and a slow database lookup.
    // Passing the signal lets the underlying HTTP requests stop as well.
    flight.promise = Promise.race([
      Promise.resolve().then(() => load(userId, { signal: controller.signal })), aborted,
    ]).then(count => {
      if (entry.generation !== generation) return null;
      if (!validCount(count)) throw new Error('Invalid provider unread count');
      entry.count = count;
      entry.observedAt = startedAt;
      entry.valid = true;
      entry.retryAt = 0;
      return fresh(entry, notBefore) ? count : null;
    }).catch(error => {
      if (entry.generation === generation) {
        entry.valid = false;
        entry.retryAt = now() + retryMs;
        logger.warn('[badge] mailbox count unavailable:', error.message);
      }
      return null;
    }).finally(() => {
      clearTimeout(timer);
      controller.signal.removeEventListener('abort', abortListener);
      if (entry.flight === flight) entry.flight = null;
    });
    return flight.promise;
  }

  function snapshot(userId, { notBefore = 0 } = {}) {
    const entry = entryFor(userId);
    if (!fresh(entry, notBefore)) void refresh(userId, { notBefore });
    const isFresh = fresh(entry, notBefore);
    return {
      unreadCount: isFresh ? entry.count : null,
      providerCountAsOf: entry.observedAt === null ? null : new Date(entry.observedAt).toISOString(),
      providerCountAgeMs: entry.observedAt === null ? null : Math.max(0, now() - entry.observedAt),
      providerCountState: isFresh ? 'fresh' : entry.flight ? 'refreshing' : 'unavailable',
    };
  }

  return { snapshot, refresh, invalidate,
    isCurrent: (userId, count) => fresh(entryFor(userId)) && entryFor(userId).count === count };
}

module.exports = { createUnreadCountCache };
