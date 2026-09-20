const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const { PGlite } = require('@electric-sql/pglite');
let db;
function load(name) {
  const filename = path.join(__dirname, name + '.js');
  const isolated = new Module(filename, module);
  isolated.filename = filename;
  isolated.require = name => {
    if (name === './db') return { query: (sql, params) => db.query(sql, params) };
    if (name === './feedStorage') return { CARD_COLUMNS: [], createFeedStorage: () => ({}) };
    if (name === 'node:crypto') return require(name);
    if (name === './accountAccess') return require(name);
    throw Error(`Unexpected dependency ${name}`);
  };
  isolated._compile(fs.readFileSync(filename, 'utf8'), filename);
  return isolated.exports;
}
const messages = load('messageStore');
const users = load('userStore');
before(async () => {
  db = new PGlite();
  await db.exec(`CREATE TABLE users(user_id TEXT PRIMARY KEY, all_mail_sync_state TEXT DEFAULT 'pending',
    all_mail_sync_cursor TEXT, all_mail_sync_generation TEXT, all_mail_sync_started_at TIMESTAMPTZ,
    all_mail_sync_completed_at TIMESTAMPTZ, all_mail_sync_revalidate BOOLEAN NOT NULL DEFAULT FALSE);
    CREATE TABLE messages(user_id TEXT, message_id TEXT, label_ids TEXT[],
      first_synced_at TIMESTAMPTZ, labels_updated_at TIMESTAMPTZ, all_mail_sync_generation TEXT,
      PRIMARY KEY(user_id,message_id));`);
});
after(async () => db.close());

test('persisted inventory generation resumes failure, resets pending, and clears the cursor on completion', async () => {
  await db.query("INSERT INTO users(user_id) VALUES('a')");
  const first = await users.beginAllMailSync('a');
  assert.ok(first.generation);
  assert.equal(first.cursor, null);
  await users.setAllMailSyncCursor('a', 'opaque-provider-page');
  await users.setAllMailSyncState('a', 'failed');
  const resumed = await users.beginAllMailSync('a');
  assert.equal(resumed.generation, first.generation);
  assert.equal(resumed.startedAt.toISOString(), first.startedAt.toISOString());
  assert.equal(resumed.cursor, 'opaque-provider-page');
  await users.setAllMailSyncState('a', 'complete');
  let row = (await db.query("SELECT * FROM users WHERE user_id='a'")).rows[0];
  assert.equal(row.all_mail_sync_cursor, null);
  assert.ok(row.all_mail_sync_completed_at);
  await users.setAllMailSyncState('a', 'pending');
  const next = await users.beginAllMailSync('a');
  assert.notEqual(next.generation, first.generation);
});

test('complete inventory prunes only missing eligible old rows, protecting other accounts, excluded folders, and concurrent writes', async () => {
  await db.query("UPDATE users SET all_mail_sync_generation='current' WHERE user_id='a'");
  await db.query(`INSERT INTO messages(user_id,message_id,label_ids,first_synced_at,labels_updated_at)
    SELECT 'a',id,labels,'2026-09-01','2026-09-01' FROM (VALUES
      ('present',ARRAY['UNREAD']),('deleted',ARRAY['INBOX']),('spam',ARRAY['SPAM','UNREAD']),
      ('trash',ARRAY['TRASH','UNREAD']),('new',ARRAY['INBOX']),('changed',ARRAY['INBOX'])) t(id,labels)`);
  await db.query("INSERT INTO messages VALUES('b','deleted',ARRAY['INBOX'],'2026-09-01','2026-09-01',NULL)");
  await db.query("UPDATE messages SET first_synced_at='2026-09-20' WHERE message_id='new'");
  await db.query("UPDATE messages SET labels_updated_at='2026-09-20' WHERE message_id='changed'");
  await messages.markAllMailSeen('a', ['present'], 'current');
  await messages.reconcileAllMail('a', 'current', '2026-09-19');
  const rows = (await db.query('SELECT user_id,message_id FROM messages ORDER BY user_id,message_id')).rows;
  assert.deepEqual(rows.map(r => `${r.user_id}:${r.message_id}`), ['a:changed','a:new','a:present','a:spam','a:trash','b:deleted']);
  await messages.removeMessages('a', ['present']);
  assert.equal((await db.query("SELECT * FROM messages WHERE user_id='a' AND message_id='present'")).rows.length, 0);
  assert.equal((await db.query("SELECT * FROM messages WHERE user_id='b' AND message_id='deleted'")).rows.length, 1);
});

test('superseded generation cannot change a new cursor, clear recovery, mark inventory or prune rows', async () => {
  await users.setAllMailSyncState('a', 'pending', { revalidate: true });
  const fresh = await users.beginAllMailSync('a');
  await users.setAllMailSyncCursor('a', 'fresh-page', fresh.generation);
  assert.equal(await users.setAllMailSyncCursor('a', 'obsolete-page', 'current'), false);
  assert.equal(await users.setAllMailSyncState('a', 'complete', { generation: 'current' }), false);
  await messages.markAllMailSeen('a', ['changed'], 'current');
  await messages.reconcileAllMail('a', 'current', '2027-01-01');
  const row = (await db.query("SELECT * FROM users WHERE user_id='a'")).rows[0];
  assert.equal(row.all_mail_sync_cursor, 'fresh-page');
  assert.equal(row.all_mail_sync_revalidate, true);
  assert.equal(row.all_mail_sync_state, 'syncing');
  const protectedRow = (await db.query("SELECT * FROM messages WHERE user_id='a' AND message_id='changed'")).rows[0];
  assert.ok(protectedRow);
  assert.notEqual(protectedRow.all_mail_sync_generation, 'current');
});
