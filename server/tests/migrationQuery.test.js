const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const Module = require('node:module');
const { createMigrationQuery } = require('../migrationQuery');

test('deadlock and serialization conflicts retry only the failed statement with bounded backoff', async () => {
  const calls = [], waits = [], warnings = [];
  let failures = 2;
  const run = createMigrationQuery({
    query: async (sql, params) => {
      calls.push([sql, params]);
      if (sql === 'ALTER failed' && failures-- > 0) {
        throw Object.assign(Error('conflict'), { code: failures ? '40P01' : '40001' });
      }
      return { rows: [], rowCount: 1 };
    },
    wait: async ms => waits.push(ms), random: () => 0,
    logger: { warn: message => warnings.push(message) },
  });
  await run('ALTER earlier');
  assert.equal((await run('ALTER failed', ['safe-value'])).rowCount, 1);
  assert.deepEqual(calls.map(([sql]) => sql), ['ALTER earlier', 'ALTER failed', 'ALTER failed', 'ALTER failed']);
  assert.deepEqual(waits, [250, 500]);
  assert.ok(calls.slice(1).every(([, params]) => params[0] === 'safe-value'));
  assert.ok(warnings.every(message => !message.includes('safe-value') && !message.includes('ALTER')));
});

test('permanent schema errors fail immediately and persistent conflicts exhaust six attempts', async () => {
  for (const [code, attempts] of [['42601', 1], ['42501', 1], ['40P01', 6]]) {
    let calls = 0;
    const waits = [];
    const run = createMigrationQuery({
      query: async () => { calls++; throw Object.assign(Error('failure'), { code }); },
      wait: async ms => waits.push(ms), random: () => 0, logger: { warn() {} },
    });
    await assert.rejects(run('ALTER migration'), { code });
    assert.equal(calls, attempts);
    assert.equal(waits.length, attempts - 1);
    if (attempts === 6) assert.deepEqual(waits, [250, 500, 1000, 2000, 4000]);
  }
});

function isolatedDatabase(fail) {
  const calls = [], waits = [];
  const filename = require.resolve('../db');
  const isolated = new Module(filename, module);
  isolated.filename = filename;
  isolated.require = name => {
    if (name === 'dotenv') return { config() {} };
    if (name === 'pg') return { Pool: class {
      on() {}
      async query(sql, params) {
        calls.push(sql.trim());
        const error = fail?.(sql, calls);
        if (error) throw error;
        return { rows: [], rowCount: 0 };
      }
    } };
    if (name === './mailboxWrites') return require('../mailboxWrites');
    if (name === './migrationQuery') return {
      createMigrationQuery: options => createMigrationQuery({ ...options,
        wait: async ms => waits.push(ms), random: () => 0, logger: { warn() {} } }),
    };
    if (name === 'fs' || name === 'path') return require(name);
    throw Error(`Unexpected dependency ${name}`);
  };
  // Execute the actual migration orchestration against a fake pool, with no
  // environment credentials, network/database connection or real wait.
  isolated._compile('const process = { env: {} }; const console = { log() {}, error() {} };\n'
    + fs.readFileSync(filename, 'utf8'), filename);
  return { ...isolated.exports, calls, waits };
}

test('actual migration orchestration commits users/messages DDL separately and retries in place', async () => {
  let failed = false;
  const db = isolatedDatabase(sql => {
    if (!failed && sql.includes('ALTER TABLE users ADD COLUMN IF NOT EXISTS unread_sync_state')) {
      failed = true;
      return Object.assign(Error('old server writer conflict'), { code: '40P01' });
    }
  });
  await db.ready;
  assert.equal(db.calls.filter(sql => sql.startsWith('CREATE TABLE')).length, 1,
    'Earlier schema work is not repeated after a later statement fails');
  assert.equal(db.calls.filter(sql => sql.includes('ALTER TABLE users ADD COLUMN IF NOT EXISTS unread_sync_state')).length, 2);
  assert.deepEqual(db.waits, [250]);
  for (const sql of db.calls) {
    assert.ok(!(sql.includes('ALTER TABLE users') && sql.includes('ALTER TABLE messages')),
      'No migration holds users DDL locks while taking messages DDL locks');
    if (sql.startsWith('CREATE INDEX')) assert.equal((sql.match(/CREATE INDEX/g) ?? []).length, 1);
  }
  assert.ok(db.calls.some(sql => sql.includes('ADD COLUMN IF NOT EXISTS source_version')));
});

test('exhausted actual migration rejects db.ready and does not run later statements', async () => {
  const db = isolatedDatabase(sql => sql.includes('ALTER TABLE users ADD COLUMN IF NOT EXISTS unread_sync_state')
    ? Object.assign(Error('persistent lock conflict'), { code: '40P01' }) : null);
  await assert.rejects(db.ready, { code: '40P01' });
  assert.equal(db.calls.filter(sql => sql.includes('ALTER TABLE users ADD COLUMN IF NOT EXISTS unread_sync_state')).length, 6);
  assert.ok(!db.calls.some(sql => sql.includes('ADD COLUMN IF NOT EXISTS source_version')));
});
