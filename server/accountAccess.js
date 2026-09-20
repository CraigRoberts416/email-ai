// One cancellation boundary for every Gmail read owned by this process.
// Credential deletion is the durable boundary; this gate interrupts work
// already holding a token. A successful explicit registration opens it again.
const accounts = new Map();
const mutations = new Map();
const lifecycles = new Map();
const disconnectedAt = new Map();
let generation = 0;
function controller(userId) {
  if (!accounts.has(userId)) accounts.set(userId, new AbortController());
  return accounts.get(userId);
}
function assertActive(userId) { controller(userId).signal.throwIfAborted(); }
function signal(userId) { return controller(userId).signal; }
function suspend(userId) {
  disconnectedAt.set(userId, ++generation);
  controller(userId).abort(Object.assign(new Error('Mailbox disconnected'), { code: 'ACCOUNT_DISCONNECTED' }));
}
function version() { return generation; }
function assertNotDisconnectedSince(userId, startedVersion) {
  if ((disconnectedAt.get(userId) ?? 0) > startedVersion) {
    throw Object.assign(new Error('Mailbox disconnected during registration'), { code: 'ACCOUNT_DISCONNECTED' });
  }
}
function mutate(userId, work) {
  const previous = mutations.get(userId) ?? Promise.resolve();
  const next = previous.catch(() => {}).then(work);
  mutations.set(userId, next);
  return next.finally(() => { if (mutations.get(userId) === next) mutations.delete(userId); });
}
function withLifecycle(userId, work) {
  const previous = lifecycles.get(userId) ?? Promise.resolve();
  const next = previous.catch(() => {}).then(work);
  lifecycles.set(userId, next);
  return next.finally(() => { if (lifecycles.get(userId) === next) lifecycles.delete(userId); });
}
function activate(userId) {
  if (controller(userId).signal.aborted) accounts.set(userId, new AbortController());
}
module.exports = { assertActive, signal, suspend, activate, version, assertNotDisconnectedSince, mutate, withLifecycle };
