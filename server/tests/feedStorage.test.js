const { test, before, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { PGlite } = require('@electric-sql/pglite');
const { createFeedStorage, feedOptions, withCompleteness, needsUnreadReconciliation } = require('../feedStorage');

let db;
const query = (...args) => db.query(...args);
const store = createFeedStorage({ query, toRecord: row => row });
const anchor = new Date('2026-11-02T05:30:00Z');

before(async () => {
  db = new PGlite();
  await db.exec(fs.readFileSync(path.join(__dirname, '../schema.sql'), 'utf8'));
  await db.exec(`ALTER TABLE messages ADD COLUMN participants JSONB,
    ADD COLUMN attachments JSONB, ADD COLUMN image_url TEXT, ADD COLUMN body_text TEXT,
    ADD COLUMN source_version INT NOT NULL DEFAULT 0`);
});
after(async () => db?.close());
beforeEach(async () => {
  await db.exec('TRUNCATE messages, users CASCADE');
  await db.query(`INSERT INTO users(user_id,access_token,refresh_token,token_expiry,unread_sync_state,unread_sync_completed_at)
    VALUES('a','test','test',NOW(),'complete',NOW()),('b','test','test',NOW(),'pending',NULL)`);
});

async function add(id, at, labels = ['UNREAD'], account = 'a', ingested = '2026-01-01T00:00:00Z') {
  await db.query(`INSERT INTO messages(user_id,message_id,internal_date,label_ids,first_synced_at,labels_updated_at)
    VALUES($1,$2,$3,$4,$5,'2026-01-01T00:00:00Z')`, [account, id, Date.parse(at), labels, ingested]);
}

test('all historical categories paginate without tier caps, duplicates, offset skips, or late insertions', async () => {
  await db.query(`INSERT INTO messages(user_id,message_id,internal_date,label_ids,post_cutoff,first_synced_at)
    SELECT 'a', LPAD(n::text,4,'0'), $1::bigint, ARRAY['UNREAD','CATEGORY_PROMOTIONS'], FALSE, '2026-01-01'::timestamptz
    FROM generate_series(1,451) n`, [Date.parse('2025-01-01T00:00:00Z')]);
  const first = await store.page('a', { limit: 200 }, anchor);
  assert.equal(first.records.length, 200);
  assert.equal(first.syncedUnreadCount, 451);
  assert.equal(first.records[0].message_id, '0451');
  await db.query("UPDATE messages SET label_ids='{}' WHERE message_id='0451'");
  await add('arrival', '2026-11-02T05:31:00Z', ['UNREAD'], 'a', '2026-11-02T05:31:00Z');
  await add('late-backfill', '2020-01-01T00:00:00Z', ['UNREAD'], 'a', '2026-11-02T05:31:00Z');
  const second = await store.page('a', { cursor: first.nextCursor }, new Date('2026-11-02T06:00:00Z'));
  const third = await store.page('a', { cursor: second.nextCursor }, new Date('2026-11-02T06:00:00Z'));
  const ids = [...first.records, ...second.records, ...third.records].map(row => row.message_id);
  assert.equal(ids.length, 451);
  assert.equal(new Set(ids).size, 451);
  assert.equal(second.records[0].message_id, '0251');
  assert.equal(third.nextCursor, null);
  assert.equal(second.syncedUnreadCount, 452, 'Live totals include unloaded arrivals, independent of the cursor');
  assert.ok(!ids.includes('late-backfill') && !ids.includes('arrival'));
});

test('sections use the session date in its timezone across a 25-hour DST day, including future mail in Today', async () => {
  await add('today', '2026-11-02T05:00:00Z');
  await add('future', '2026-11-05T05:00:00Z');
  await add('yesterday-early', '2026-11-01T04:30:00Z');
  await add('yesterday-late', '2026-11-02T04:59:59Z');
  await add('earlier', '2026-11-01T03:59:59Z');
  const first = await store.page('a', { limit: 1, timeZone: 'America/New_York', sectionDate: anchor.toISOString() }, anchor);
  assert.deepEqual(first.sections, { today: 2, yesterday: 2, earlier: 1 });
  const later = await store.page('a', { cursor: first.nextCursor, timeZone: 'America/New_York' }, new Date('2026-11-03T06:00:00Z'));
  assert.deepEqual(later.sections, first.sections);
  assert.equal(later.sectionDate, anchor.toISOString());
});

test('archived unread is included; Spam, Trash, read mail and other accounts are excluded from sections/cards', async () => {
  await add('archived', '2025-01-01T00:00:00Z', ['UNREAD']);
  await add('spam', '2025-01-01T00:00:00Z', ['UNREAD', 'SPAM']);
  await add('trash', '2025-01-01T00:00:00Z', ['UNREAD', 'TRASH']);
  await add('read', '2025-01-01T00:00:00Z', ['INBOX']);
  await add('other-account', '2025-01-01T00:00:00Z', ['UNREAD'], 'b');
  const page = await store.page('a', {}, anchor);
  assert.deepEqual(page.records.map(row => row.message_id), ['archived']);
  assert.equal(page.feedUnreadCount, 1);
  assert.equal(page.allSyncedUnreadCount, 3);
  assert.equal(withCompleteness(page, 1).countsComplete, true);
  assert.equal(withCompleteness(page, 3).countsComplete, false, 'Raw label membership is not the provider counter scope');
  assert.equal(withCompleteness(page, 2).countsComplete, false);
  assert.equal(withCompleteness(page, null).countsComplete, false);
  await db.query("UPDATE messages SET label_ids='{}' WHERE message_id='archived'");
  const cleared = withCompleteness(await store.page('a', {}, anchor), 0);
  assert.equal(cleared.feedUnreadCount, 0);
  assert.equal(cleared.allSyncedUnreadCount, 2, 'Excluded label membership remains available for diagnostics');
  assert.equal(cleared.unreadCount, 0, 'Spam and Trash are excluded from the provider counter and icon badge');
  assert.equal(cleared.countsComplete, true, 'Excluded folders do not block eligible feed zero');
});

test('excluded unread mail cannot cause repeated repair after an exhaustive matching import', () => {
  const page = {
    syncState: 'complete', syncCompletedAt: anchor,
    sections: { today: 7, yesterday: 56, earlier: 22309 },
    feedUnreadCount: 22372, allSyncedUnreadCount: 23146,
  };
  const matching = withCompleteness(page, 22372);
  assert.equal(matching.countsComplete, true);
  assert.equal(matching.knownStateComplete, true);
  assert.equal(needsUnreadReconciliation(matching), false);
  for (const incomplete of [{ ...page, syncState: 'syncing' }, { ...page, syncCompletedAt: null }]) {
    assert.equal(withCompleteness(incomplete, 22372).countsComplete, false,
      'Matching eligible totals still require a successfully finished enumeration');
  }
  const mismatch = withCompleteness(page, 22371);
  assert.equal(mismatch.countsComplete, false);
  assert.equal(needsUnreadReconciliation(mismatch), true);
});

test('empty pending/error reconciliation never claims completion, even when the provider reports zero', async () => {
  assert.equal(withCompleteness(await store.page('b', {}, anchor), 0).countsComplete, false);
  await db.query("UPDATE users SET unread_sync_state='error' WHERE user_id='a'");
  assert.equal(withCompleteness(await store.page('a', {}, anchor), 0).countsComplete, false);
  await db.query("UPDATE users SET unread_sync_state='complete' WHERE user_id='a'");
  assert.equal(withCompleteness(await store.page('a', {}, anchor), 0).countsComplete, true);
});

test('an unavailable provider count preserves unknown state without restarting a completed import', () => {
  const synced = { syncState: 'complete', syncCompletedAt: anchor, feedUnreadCount: 23000, allSyncedUnreadCount: 23774 };
  for (const unreadCount of [null, undefined, NaN, -1]) {
    const result = withCompleteness(synced, unreadCount);
    assert.equal(result.countsComplete, false);
    assert.equal(needsUnreadReconciliation(result), false, 'Unknown count must not amplify a provider outage');
  }
  assert.equal(needsUnreadReconciliation(withCompleteness(synced, 23000)), false);
  assert.equal(needsUnreadReconciliation(withCompleteness(synced, 22999)), true, 'A known mismatch still schedules repair');
  for (const syncState of ['pending', 'syncing', 'error']) {
    assert.equal(needsUnreadReconciliation(withCompleteness({ ...synced, syncState }, null)), true,
      'An unfinished import still needs to run, even before its count is available');
  }
});

test('invalid, cross-account and timezone-switched cursors are rejected before SQL', async () => {
  await add('one', '2025-01-01T00:00:00Z');
  await add('two', '2025-01-01T00:00:00Z');
  const page = await store.page('a', { limit: 1 }, anchor);
  for (const options of [{ cursor: '%' }, { cursor: page.nextCursor, timeZone: 'America/New_York' },
    { limit: 0 }, { limit: 201 }, { limit: '1.5' }, { timeZone: 'Unknown/Zone' }, { sectionDate: 'bad' }]) {
    assert.throws(() => feedOptions('a', options, anchor), { statusCode: 400 });
  }
  assert.throws(() => feedOptions('b', { cursor: page.nextCursor }, anchor), { statusCode: 400 });
});

test('known read IDs distinguish confirmed read rows from missing IDs, unread rows, and other accounts', async () => {
  await add('cached-read', '2025-01-01T00:00:00Z', []);
  await add('still-unread', '2025-01-01T00:00:00Z');
  await add('other-read', '2025-01-01T00:00:00Z', [], 'b');
  const page = await store.page('a', {
    knownMessageIds: 'cached-read,still-unread,not-synced,other-read,cached-read',
  }, anchor);
  assert.deepEqual(page.knownReadMessageIds, ['cached-read']);
  assert.equal(withCompleteness(page, 1).knownStateComplete, true);
  assert.equal(withCompleteness(page, 2).knownStateComplete, false);
  assert.equal(withCompleteness(page, null).knownStateComplete, false);
  await db.query("UPDATE users SET unread_sync_state='syncing' WHERE user_id='a'");
  assert.equal(withCompleteness(await store.page('a', {}, anchor), 1).knownStateComplete, false);
  for (const value of [Array(501).fill('id').join(','), 'a,,b', ['a', 'b'], 'bad id']) {
    assert.throws(() => feedOptions('a', { knownMessageIds: value }, anchor), { statusCode: 400 });
  }
  assert.equal(feedOptions('a', { knownMessageIds: Array(500).fill('id').join(',') }, anchor).knownIds.length, 1);
});

test('late backlog metadata cannot undo a confirmed read; reconciliation protects recent label edits', async () => {
  // Only replace the DB dependency while loading the production message store.
  // No connection to a configured account database can be opened by this test.
  const dbPath = require.resolve('../db');
  const previous = require.cache[dbPath];
  require.cache[dbPath] = { id: dbPath, filename: dbPath, loaded: true, exports: { query } };
  delete require.cache[require.resolve('../messageStore')];
  const messages = require('../messageStore');
  if (previous) require.cache[dbPath] = previous; else delete require.cache[dbPath];
  await add('read-race', '2025-01-01T00:00:00Z', []);
  await db.query("UPDATE messages SET labels_updated_at='2026-11-02T05:20:00Z' WHERE message_id='read-race'");
  await messages.upsertMessages('a', [{ messageId: 'read-race', labelIds: ['UNREAD'],
    internalDate: Date.parse('2025-01-01'), labelsObservedAt: '2026-11-02T05:00:00Z' }]);
  assert.deepEqual((await messages.getMessage('a', 'read-race')).labelIds, []);
  await add('stale-unread', '2025-01-01T00:00:00Z');
  await add('new-spam', '2025-01-01T00:00:00Z');
  await add('other-account', '2025-01-01T00:00:00Z', ['UNREAD'], 'b');
  await messages.reconcileUnreadLabels('a', ['read-race', 'new-spam'], new Date('2026-11-02T05:10:00Z'), { SPAM: ['new-spam'] });
  assert.deepEqual((await messages.getMessage('a', 'read-race')).labelIds, []);
  assert.deepEqual((await messages.getMessage('a', 'stale-unread')).labelIds, []);
  assert.deepEqual((await messages.getMessage('a', 'new-spam')).labelIds, ['UNREAD', 'SPAM']);
  assert.deepEqual((await messages.getMessage('b', 'other-account')).labelIds, ['UNREAD']);
});

test('counts-only query needs no card or body columns and returns identical metadata', async () => {
  await add('today', '2026-11-02T05:00:00Z');
  await add('yesterday', '2026-11-01T04:30:00Z');
  await add('old', '2020-01-01T00:00:00Z');
  await add('spam', '2020-01-01T00:00:00Z', ['UNREAD', 'SPAM']);
  await add('read', '2020-01-01T00:00:00Z', []);
  const options = { timeZone: 'America/New_York', knownMessageIds: 'read,missing,old' };
  const { records, nextCursor, ...metadata } = await store.page('a', options, anchor);
  await db.exec(`CREATE ROLE feed_counter;
    GRANT SELECT(user_id, message_id, internal_date, label_ids) ON messages TO feed_counter;
    GRANT SELECT(user_id, unread_sync_state, unread_sync_completed_at) ON users TO feed_counter;
    SET ROLE feed_counter`);
  try {
    const counter = createFeedStorage({ query, toRecord: () => assert.fail('Counts must not map a card') });
    const counts = await counter.counts('a', options, anchor);
    assert.deepEqual(counts, metadata);
    assert.equal(counts.records, undefined);
    assert.equal(counts.nextCursor, undefined);
    assert.deepEqual(counts.knownReadMessageIds, ['read']);
  } finally {
    await db.exec('RESET ROLE; DROP OWNED BY feed_counter; DROP ROLE feed_counter');
  }
});

test('23k unread mailbox keeps cached bodies out of page/count database payloads and uses cursor index', async t => {
  await db.exec(`CREATE INDEX IF NOT EXISTS idx_messages_unread_cursor
    ON messages(user_id, internal_date DESC, message_id COLLATE "C" DESC)
    WHERE 'UNREAD' = ANY(label_ids)`);
  await db.query(`INSERT INTO messages(user_id,message_id,internal_date,label_ids,first_synced_at,body_text)
    SELECT 'a', n::text, 1760000000000+n, ARRAY['UNREAD'], '2025-01-01'::timestamptz,
      CASE WHEN n > 22800 THEN repeat(md5(n::text),4096) ELSE NULL END
    FROM generate_series(1,23000) n`);
  await db.exec('ANALYZE messages');
  let sql, params, raw;
  const measured = createFeedStorage({ query: async (statement, bindings) => {
    sql = statement; params = bindings;
    const result = await query(statement, bindings);
    raw = result.rows;
    return result;
  }, toRecord: row => row });
  let start = performance.now();
  const counts = await measured.counts('a', {}, anchor);
  const countBytes = Buffer.byteLength(JSON.stringify(raw));
  t.diagnostic(`Synthetic counts: ${Math.round(performance.now() - start)}ms; database JSON ${countBytes} bytes`);
  assert.equal(counts.feedUnreadCount, 23000);
  assert.ok(countBytes < 1024, 'Counts payload remains constant-size without card/body materialization');
  start = performance.now();
  const page = await measured.page('a', {}, anchor);
  const pageBytes = Buffer.byteLength(JSON.stringify(raw));
  t.diagnostic(`Synthetic page: ${Math.round(performance.now() - start)}ms; database JSON ${pageBytes} bytes`);
  assert.equal(page.records.length, 200);
  assert.equal(page.feedUnreadCount, 23000);
  assert.ok(page.nextCursor);
  assert.ok(page.records.every(row => !Object.hasOwn(row, 'body_text')));
  assert.ok(pageBytes < 200000, '128 KiB cached bodies never inflate the 201-row card transfer');
  const explained = await query('EXPLAIN (FORMAT JSON, COSTS FALSE) ' + sql, params);
  const plan = explained.rows[0]['QUERY PLAN'][0].Plan;
  function nodes(node) { return [node, ...(node.Plans ?? []).flatMap(nodes)]; }
  assert.ok(nodes(plan).some(node => node['Index Name'] === 'idx_messages_unread_cursor'),
    'Page selection can stop on the chronological unread index');
});

test('profile source inspection is account-scoped, distinguishes unknown from empty, and never fills AI fields', async () => {
  const dbPath = require.resolve('../db'), previous = require.cache[dbPath];
  require.cache[dbPath] = { id: dbPath, filename: dbPath, loaded: true, exports: { query } };
  delete require.cache[require.resolve('../messageStore')];
  const messages = require('../messageStore');
  if (previous) require.cache[dbPath] = previous; else delete require.cache[dbPath];
  await add('source', '2020-01-01T00:00:00Z', [], 'a');
  await add('source', '2020-01-01T00:00:00Z', [], 'b');
  const initial = (await messages.getHistoryPageRecords('a', ['source']))[0];
  assert.equal(initial.sourceInspected, false);
  assert.equal(initial.originalText, null);
  await messages.saveProfileSource('a', 'source', { bodyText: 'Original text '.repeat(1000), attachments: [] });
  const partial = (await messages.getHistoryPageRecords('a', ['source']))[0];
  assert.equal(partial.sourceInspected, false, 'Unknown image state remains unknown');
  assert.equal(partial.originalText.length, 8000, 'Original text transfer is bounded per visible card');
  await messages.saveProfileSource('a', 'source', { bodyText: 'Original text', attachments: [], imageUrl: '' });
  const inspected = (await messages.getHistoryPageRecords('a', ['source']))[0];
  assert.equal(inspected.sourceInspected, true);
  assert.deepEqual(inspected.attachments, []);
  assert.equal(inspected.quote, null);
  assert.equal(inspected.summary, null);
  assert.equal((await messages.getHistoryPageRecords('b', ['source']))[0].sourceInspected, false);
  await query("UPDATE messages SET body_text = 'legacy', attachments = '[]', image_url = '' WHERE user_id = 'b' AND message_id = 'source'");
  assert.equal((await messages.getHistoryPageRecords('b', ['source']))[0].sourceInspected, false,
    'Previously inspected sources are rechecked for inline personal photos');
  const metadata = (await messages.getMessagesByIds('a', ['source']))[0];
  assert.equal(metadata.originalText, undefined, 'Counting candidates does not transfer body excerpts');
  await messages.saveProfileSource('a', 'source', { bodyText: 'Original text', imageUrl: '',
    attachments: [{ id: 'one', filename: 'one.pdf' }, { id: 'two', filename: 'two.pdf' }] });
  await messages.setAttachments('a', 'source', [{ id: 'one', filename: 'updated.pdf' }]);
  const merged = (await messages.getHistoryPageRecords('a', ['source']))[0].attachments;
  assert.deepEqual(merged, [{ id: 'one', filename: 'updated.pdf' }, { id: 'two', filename: 'two.pdf' }],
    'A later bounded worker preview preserves files discovered during complete profile inspection');
});
