const { test, before, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const { PGlite } = require('@electric-sql/pglite');

// Load the production module with fail-closed external dependencies. Listing
// conversations must never read a live database or hydrate mail from Gmail.
const filename = path.join(__dirname, 'conversations.js');
const isolated = new Module(filename, module);
isolated.filename = filename;
isolated.require = name => {
  if (name === './db') return { query: () => { throw Error('Live database forbidden in this test'); } };
  if (name === './gmailSync') return { fetchFullMessage: () => { throw Error('People list must never hydrate Gmail'); } };
  if (name === './messageStore') return {};
  if (name === './replyText') return { unwrap: text => text };
  if (name === './emailAttachments') return {};
  throw Error(`Unexpected dependency ${name}`);
};
isolated._compile(fs.readFileSync(filename, 'utf8'), filename);
const { listConversations, listConversationsPage, conversationMessagesPage } = isolated.exports;

let db;
let reads;
const readQuery = async (sql, params) => {
  const result = await db.query(sql, params);
  reads.push({ sql, params, rows: result.rows, bytes: Buffer.byteLength(JSON.stringify(result.rows)) });
  return result;
};

before(async () => {
  db = new PGlite();
  await db.exec(`CREATE TABLE messages (
    user_id TEXT NOT NULL, message_id TEXT NOT NULL, thread_id TEXT,
    subject TEXT, from_name TEXT, from_email TEXT, snippet TEXT,
    internal_date BIGINT, participants JSONB, unsubscribe_url TEXT,
    label_ids TEXT[], quote TEXT, summary TEXT, body_text TEXT,
    attachments JSONB, post_cutoff BOOLEAN DEFAULT FALSE, PRIMARY KEY(user_id, message_id)
  ); CREATE INDEX user_date ON messages(user_id, internal_date DESC);`);
});
after(async () => db?.close());
beforeEach(async () => { await db.exec('TRUNCATE messages'); reads = []; });

async function add(id, date, { email = 'alice@gmail.com', name = 'Alice Adams',
  body = 'Original body', quote = null, snippet = 'A snippet', labels = [],
  participants = [{ email: 'owner@gmail.com', name: 'Owner Reader' }], user = 'a', unsubscribe = null } = {}) {
  await db.query(`INSERT INTO messages(user_id,message_id,thread_id,subject,from_name,from_email,snippet,
    internal_date,participants,unsubscribe_url,label_ids,quote,summary,body_text)
    VALUES($1,$2,$2,$2,$3,$4,$5,$6,$7,$8,$9,$10,'summary not used by People',$11)`,
    [user, id, name, email, snippet, date, JSON.stringify(participants), unsubscribe, labels, quote, body]);
}

test('metadata scan preserves archived grouping, counts, unread state and newest preview', async () => {
  await add('alice-old', 100, { labels: ['UNREAD'] });
  await add('bob', 200, { name: 'Bob Baker', email: 'bob@gmail.com' });
  await add('sent', 300, { name: 'Owner Reader', email: 'owner@gmail.com', labels: ['SENT'],
    participants: [{ name: 'Alice Adams', email: 'alice@gmail.com' }] });
  await add('alice-new', 400, { body: 'https://example.test/tracking\nHello Craig,\nHere are the new dates.' });
  await add('bulk', 500, { labels: ['CATEGORY_UPDATES'] });
  await add('alice-new', 900, { user: 'b', body: 'OTHER ACCOUNT PRIVATE BODY' });

  const list = await listConversations('a', 'owner@gmail.com', { limit: 1, query: readQuery,
    resolveAvatar: ({ sender }) => `https://logo.test/${sender.domain}` });
  assert.equal(list.length, 1);
  assert.equal(list[0].id, 'alice@gmail.com');
  assert.equal(list[0].messageCount, 3);
  assert.equal(list[0].unread, true, 'An older unread message still contributes');
  assert.equal(list[0].lastMessageId, 'alice-new');
  assert.equal(list[0].lastAt, 400);
  assert.equal(list[0].lastFromMe, false);
  assert.equal(list[0].preview, 'Hello Craig, Here are the new dates.');
  assert.equal(list[0].participants[0].avatarUri, 'https://logo.test/gmail.com');
  assert.equal(reads.length, 2);
  for (const row of reads[0].rows) {
    assert.equal(Object.hasOwn(row, 'body_text'), false);
    assert.equal(Object.hasOwn(row, 'snippet'), false);
    assert.equal(Object.hasOwn(row, 'quote'), false);
    assert.equal(Object.hasOwn(row, 'summary'), false);
  }
  assert.deepEqual(reads[1].params, ['a', ['alice-new']], 'Only returned conversations fetch preview text');
  assert.equal(JSON.stringify(list).includes('OTHER ACCOUNT'), false);
});

test('keeps group conversations distinct and uses quote then snippet only when body is absent', async () => {
  await add('direct', 100, { body: null, quote: 'Quoted source text' });
  await add('group', 200, { body: '', quote: null, snippet: 'The group snippet', participants: [
    { name: 'Owner Reader', email: 'owner@gmail.com' }, { name: 'Bob Baker', email: 'bob@gmail.com' },
  ] });
  const list = await listConversations('a', 'owner@gmail.com', { query: readQuery });
  assert.deepEqual(list.map(c => c.id), ['alice@gmail.com|bob@gmail.com', 'alice@gmail.com']);
  assert.deepEqual(list.map(c => c.preview), ['The group snippet', 'Quoted source text']);
  assert.deepEqual(list.map(c => c.messageCount), [1, 1]);
});

test('bounded Unicode previews keep full bodies out of response without breaking emoji', async () => {
  await add('long', 100, { body: '🙂'.repeat(5000) });
  const list = await listConversations('a', 'owner@gmail.com', { query: readQuery });
  assert.equal(Array.from(reads[1].rows[0].body_text).length, 4096, 'Database transfer is bounded before JS');
  assert.equal(Array.from(list[0].preview).length, 512);
  assert.equal(list[0].preview, '🙂'.repeat(512));
  const stored = await db.query('SELECT LENGTH(body_text) AS length FROM messages WHERE message_id=$1', ['long']);
  assert.equal(stored.rows[0].length, 5000, 'Opening the conversation retains its full original body');
});

test('empty or commercial-only mailbox skips the preview query', async () => {
  await add('newsletter', 100, { unsubscribe: 'https://example.test/unsubscribe' });
  const list = await listConversations('a', 'owner@gmail.com', { query: readQuery });
  assert.deepEqual(list, []);
  assert.equal(reads.length, 1);
});

test('historical body volume no longer scales with the full candidate set', async () => {
  await db.query(`INSERT INTO messages(user_id,message_id,thread_id,subject,from_name,from_email,snippet,
    internal_date,participants,label_ids,body_text)
    SELECT 'a', 'message-'||n, 'thread-'||n, 'Subject', 'Person Reader',
      'person'||(n % 40)||'@gmail.com', 'Short snippet', n,
      '[{"name":"Owner Reader","email":"owner@gmail.com"}]'::jsonb, ARRAY['UNREAD'],
      REPEAT('Real message text. ', 1500)
    FROM generate_series(1,1000) n`);
  const list = await listConversations('a', 'owner@gmail.com', { limit: 10, query: readQuery });
  assert.equal(list.length, 10);
  assert.ok(list.every(c => c.messageCount === 25), 'Counts still cover all historical candidates');
  assert.equal(reads[0].rows.length, 1000);
  assert.equal(reads[1].rows.length, 10);
  const actualTransfer = reads.reduce((total, read) => total + read.bytes, 0);
  // Compare the original query's body volume in Postgres, without transferring
  // those bodies into the test process just to measure the avoided transfer.
  const original = await db.query("SELECT SUM(OCTET_LENGTH(body_text))::int AS bytes FROM messages WHERE user_id='a'");
  assert.ok(actualTransfer < original.rows[0].bytes / 20,
    `Expected at least 20x lower DB transfer: ${actualTransfer} vs ${original.rows[0].bytes}`);
  assert.ok(Buffer.byteLength(JSON.stringify(list)) < 12_000);
  console.info(`[test conversations] originalBodyBytes=${original.rows[0].bytes} optimizedTransferBytes=${actualTransfer}`);
});


test('People pagination reaches beyond 200 conversations and 20,000 metadata rows with exact totals', async () => {
  await db.query(`INSERT INTO messages(user_id,message_id,thread_id,subject,from_name,from_email,
    internal_date,participants,label_ids,body_text)
    SELECT 'a','message-'||LPAD(n::text,6,'0'),'thread-'||n,'Subject','Person Reader',
      'person'||(n % 230)||'@gmail.com', n,
      '[{"name":"Owner Reader","email":"owner@gmail.com"}]'::jsonb, ARRAY['UNREAD'], 'Body'
    FROM generate_series(1,20125) n`);
  const seen = new Map();
  let cursor;
  do {
    const page = await listConversationsPage('a', 'owner@gmail.com', { cursor, limit: 50, query: readQuery });
    assert.equal(page.totalConversations, 230);
    assert.equal(page.unreadConversations, 230);
    for (const c of page.conversations) { assert.equal(seen.has(c.id), false); seen.set(c.id, c); }
    cursor = page.nextCursor;
  } while (cursor);
  assert.equal(seen.size, 230);
  assert.equal([...seen.values()].reduce((n, c) => n + c.messageCount, 0), 20125);
  assert.ok(reads.filter(r => !r.sql.includes('LEFT(body_text')).every(r => r.rows.length <= 2000));
});

test('stable equal-date pages scope cursors to account and conversation and exclude draft/spam/trash', async () => {
  await add('a', 100, { labels: ['UNREAD'] });
  await add('b', 100, { email: 'bob@gmail.com', name: 'Bob Baker' });
  await add('draft', 200, { labels: ['DRAFT'] });
  await add('spam', 300, { labels: ['SPAM', 'UNREAD'] });
  await add('trash', 400, { labels: ['TRASH', 'UNREAD'] });
  const first = await listConversationsPage('a', 'owner@gmail.com', { limit: 1, query: readQuery, batchSize: 1 });
  const second = await listConversationsPage('a', 'owner@gmail.com', { limit: 1, cursor: first.nextCursor, query: readQuery, batchSize: 1 });
  assert.deepEqual([first.conversations[0].id, second.conversations[0].id], ['bob@gmail.com', 'alice@gmail.com']);
  assert.equal(first.totalConversations, 2);
  assert.equal(second.nextCursor, null);
  await assert.rejects(() => listConversationsPage('b', 'owner@gmail.com', { cursor: first.nextCursor, query: readQuery }), /Invalid/);
  await assert.rejects(() => conversationMessagesPage('a', 'owner@gmail.com', 'alice@gmail.com', { cursor: first.nextCursor, query: readQuery }), /Invalid/);
});

test('thread pages cover all history, preserve real same-millisecond message IDs, and load bodies only for the page', async () => {
  await db.query(`INSERT INTO messages(user_id,message_id,thread_id,subject,from_name,from_email,
    internal_date,participants,label_ids,body_text,attachments)
    SELECT 'a','message-'||LPAD(n::text,6,'0'),'one-thread','Subject','Alice Adams',
      'alice@gmail.com', n / 2,
      '[{"name":"Owner Reader","email":"owner@gmail.com"}]'::jsonb, ARRAY['UNREAD'], REPEAT('Body ',1000), '[]'::jsonb
    FROM generate_series(1,1105) n`);
  await add('old-sent', 0, { email: 'owner@gmail.com', name: 'Owner Reader', participants: null, labels: ['SENT'] });
  await db.query("UPDATE messages SET thread_id='one-thread',attachments='[]'::jsonb WHERE message_id='old-sent'");
  await add('other-group', 900, { participants: [{ name: 'Bob Baker', email: 'bob@gmail.com' }] });
  const seen = new Set(); const hydrated = []; let cursor;
  do {
    const page = await conversationMessagesPage('a', 'owner@gmail.com', 'alice@gmail.com', {
      limit: 200, cursor, query: readQuery, batchSize: 300, hydrate: async (u, rows) => hydrated.push(rows.length),
    });
    assert.equal(page.totalMessages, 1106);
    assert.ok(page.messages.every((m, i, a) => i === 0 || a[i-1].internalDate <= m.internalDate));
    for (const m of page.messages) { assert.equal(seen.has(m.messageId), false); seen.add(m.messageId); }
    cursor = page.nextCursor;
  } while (cursor);
  assert.equal(seen.size, 1106);
  assert.ok(seen.has('old-sent'));
  assert.equal(seen.has('other-group'), false);
  assert.ok(hydrated.every(count => count <= 200));
  assert.ok(reads.filter(r => r.sql.includes('attachments, body_text')).every(r => r.rows.length <= 200));
});
