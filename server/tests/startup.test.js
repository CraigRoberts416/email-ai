const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const flush = () => new Promise(resolve => setImmediate(resolve));
function fixture() {
  let resolve, reject;
  const ready = new Promise((yes, no) => { resolve = yes; reject = no; });
  const events = [];
  const context = {
    require: name => {
      assert.equal(name, './db');
      return { ready, pool: { end: async () => events.push('pool-end') } };
    },
    processingWorker: { init: () => events.push('worker-init') },
    streamInterpretEmail() {}, streamDecideActionSurface() {}, detectRiskSignals() {}, emitSSE() {},
    mailNotifications: { notifyMailbox() {} },
    watchManager: { startWatchRenewalCron: () => events.push('watch-cron') },
    app: { listen: (_port, callback) => { events.push('listen'); callback(); } },
    process: { env: {}, exit: code => events.push(`exit-${code}`) },
    console: { log() {}, error: message => events.push(message) },
    syncEveryone: async () => events.push('sync'),
    setInterval: () => events.push('sync-interval'), SYNC_INTERVAL_MS: 120000,
    userStore: { getAllUsers: async () => { events.push('resume-users'); return []; } },
  };
  const source = fs.readFileSync(require.resolve('../index'), 'utf8');
  const bootstrap = source.slice(source.indexOf('// ─── Bootstrap'));
  assert.ok(bootstrap.length > 1000, 'Execute the production bootstrap, not a copy of its behavior');
  vm.runInNewContext(bootstrap, context);
  return { events, resolve, reject };
}

test('production startup waits for migrations before listener, workers, cron or sync', async () => {
  const h = fixture();
  await flush();
  assert.deepEqual(h.events, []);
  h.resolve();
  await flush();
  assert.deepEqual(h.events, ['worker-init', 'watch-cron', 'listen', 'sync', 'sync-interval', 'resume-users']);
});

test('migration failure closes the database and exits without accepting traffic or starting imports', async () => {
  const h = fixture();
  h.reject(new Error('schema failed'));
  await flush();
  assert.deepEqual(h.events, ['[startup] database schema unavailable:', 'pool-end', 'exit-1']);
});
