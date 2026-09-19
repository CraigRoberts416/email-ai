const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const Module = require('node:module');
const { PGlite } = require('@electric-sql/pglite');

function withDatabase(name, db) {
  const filename = require.resolve(name);
  const isolated = new Module(filename, module);
  isolated.filename = filename;
  isolated.require = dependency => dependency === './db' ? { query: (...args) => db.query(...args) }
    : require(require.resolve(dependency, { paths: [require('node:path').dirname(filename)] }));
  isolated._compile(fs.readFileSync(filename, 'utf8'), filename);
  return isolated.exports;
}

test('archive metadata reuse is scoped, rejects legacy fields, and refreshes restored Spam/Trash rows', async t => {
  const db = new PGlite(); t.after(() => db.close());
  await db.exec(`CREATE TABLE messages(user_id TEXT, message_id TEXT, participants JSONB, from_email TEXT, label_ids TEXT[]);
    INSERT INTO messages VALUES
    ('a','known','[]','person@example.com','{}'),
    ('a','legacy',NULL,'person@example.com','{}'),
    ('a','no-sender','[]','','{}'),
    ('a','spam-restored','[]','person@example.com','{SPAM}'),
    ('a','trash-restored','[]','person@example.com','{TRASH}'),
    ('b','other-account','[]','person@example.com','{}');`);
  const messages = withDatabase('../messageStore', db);
  const needed = await messages.archiveMetadataNeeded('a', ['known','legacy','no-sender','spam-restored','trash-restored','other-account','missing']);
  assert.deepEqual(needed.sort(), ['legacy','missing','no-sender','other-account','spam-restored','trash-restored']);
  assert.deepEqual(await messages.archiveMetadataNeeded('a', []), []);
});

test('expired-history revalidation survives failed/resumed generations and clears only on successful completion', async t => {
  const db = new PGlite(); t.after(() => db.close());
  await db.exec(`CREATE TABLE users(user_id TEXT PRIMARY KEY, all_mail_sync_state TEXT,
    all_mail_sync_completed_at TIMESTAMPTZ, all_mail_sync_cursor TEXT, all_mail_sync_generation TEXT,
    all_mail_sync_started_at TIMESTAMPTZ, all_mail_sync_revalidate BOOLEAN NOT NULL DEFAULT FALSE);
    INSERT INTO users(user_id,all_mail_sync_state) VALUES ('a','complete'), ('b','complete');`);
  const users = withDatabase('../userStore', db);
  await users.setAllMailSyncState('a', 'pending', { revalidate: true });
  const first = await users.beginAllMailSync('a');
  assert.equal(first.revalidate, true);
  await users.setAllMailSyncCursor('a', 'saved-page');
  await users.setAllMailSyncState('a', 'failed');
  const resumed = await users.beginAllMailSync('a');
  assert.equal(resumed.revalidate, true);
  assert.equal(resumed.generation, first.generation);
  assert.equal(resumed.cursor, 'saved-page');
  await users.setAllMailSyncState('a', 'complete');
  const finished = (await db.query("SELECT * FROM users WHERE user_id='a'")).rows[0];
  assert.equal(finished.all_mail_sync_revalidate, false);
  assert.equal(finished.all_mail_sync_cursor, null);
  assert.ok(finished.all_mail_sync_completed_at);
  assert.equal((await db.query("SELECT all_mail_sync_revalidate FROM users WHERE user_id='b'")).rows[0].all_mail_sync_revalidate, false);
});
