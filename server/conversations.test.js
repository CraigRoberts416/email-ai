const { test, before, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const { PGlite } = require('@electric-sql/pglite');

// Load the production module with fail-closed external dependencies. Listing
// conversations must never read a live database or hydrate mail from Gmail.
const filename = path.join(__dirname, 'conversations.js');
let fetchSource = () => { throw Error('People list must never hydrate Gmail'); };
let savedSources = [];
const isolated = new Module(filename, module);
isolated.filename = filename;
isolated.require = name => {
  if (name === './db') return { query: () => { throw Error('Live database forbidden in this test'); } };
  if (name === './gmailSync') return { fetchFullMessage: (...args) => fetchSource(...args) };
  if (name === './messageStore') return { saveProfileSource: async (user, id, source) => {
    await db.query(`UPDATE messages SET body_text=COALESCE(body_text,$3),attachments=$4::jsonb,source_version=2
      WHERE user_id=$1 AND message_id=$2`, [user,id,source.bodyText,JSON.stringify(source.attachments)]);
    savedSources.push(source);
  } };
  if (name === './replyText') return { ...require('./replyText'), unwrap: text => text };
  if (name === './emailAttachments') return require('./emailAttachments');
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
    attachments JSONB, source_version INT DEFAULT 0, post_cutoff BOOLEAN DEFAULT FALSE, PRIMARY KEY(user_id, message_id)
  ); CREATE INDEX user_date ON messages(user_id, internal_date DESC);
  CREATE INDEX idx_messages_user_sender ON messages(user_id, lower(from_email));
  CREATE INDEX idx_messages_user_thread ON messages(user_id, thread_id);
  CREATE INDEX idx_messages_participant_emails
    ON messages USING gin ((lower(participants::text)::jsonb) jsonb_path_ops);`);
});
after(async () => db?.close());
beforeEach(async () => {
  await db.exec('TRUNCATE messages'); reads = []; savedSources = [];
  fetchSource = () => { throw Error('Unexpected Gmail source fetch'); };
});

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

test('thread lookup uses sender and participant indexes rather than expanding unrelated archive metadata', async () => {
  await db.query(`INSERT INTO messages(user_id,message_id,thread_id,subject,from_name,from_email,
    internal_date,participants,label_ids,body_text,attachments)
    SELECT 'a','unrelated-'||n,'other-thread-'||n,'Subject','Other Person',
      'person'||n||'@gmail.com', n,
      '[{"name":"Owner Reader","email":"owner@gmail.com"}]'::jsonb,
      ARRAY['UNREAD'], 'Unrelated body', '[]'::jsonb FROM generate_series(1,30000) n`);
  await add('received', 2, { email: 'ALICE@GMAIL.COM' });
  await add('sent', 1, { email: 'owner@gmail.com', name: 'Owner Reader', labels: ['SENT'],
    participants: [{ name: 'Alice Adams', email: 'ALICE@GMAIL.COM' }] });
  await add('fork', 3, { participants: [{ name: 'Bob Baker', email: 'bob@gmail.com' }] });
  await add('other-account', 5, { user: 'b' });
  await add('excluded', 6, { labels: ['SPAM'] });
  await db.exec('ANALYZE messages');
  const page = await conversationMessagesPage('a','owner@gmail.com','alice@gmail.com', {
    query: readQuery, hydrate: async () => {},
  });
  assert.deepEqual(page.messages.map(message => message.messageId), ['sent','received']);
  assert.equal(page.totalMessages, 2);
  assert.equal(page.nextCursor, null);
  const candidates = reads.find(read => read.sql.includes('ANY($4::jsonb[])'));
  assert.ok(candidates, 'Production predicate uses indexed JSONB containment');
  assert.equal(candidates.sql.includes('jsonb_array_elements'), false);
  const explained = await db.query('EXPLAIN (FORMAT JSON) ' + candidates.sql, candidates.params);
  const plan = JSON.stringify(explained.rows[0]['QUERY PLAN']);
  assert.match(plan, /idx_messages_user_sender/);
  assert.match(plan, /idx_messages_participant_emails/);
  assert.ok(reads.every(read => read.rows.length <= 3), 'Only matching correspondence leaves the database');
});

test('legacy cached thread re-inspects inline photos asynchronously and coalesces concurrent source requests', async () => {
  await add('legacy', 100, { body: 'Already cached body' });
  await db.query("UPDATE messages SET attachments='[]'::jsonb WHERE message_id='legacy'");
  let release; let fetches = 0;
  const gate = new Promise(resolve => { release = resolve; });
  fetchSource = async () => { fetches++; return gate; };
  const first = await conversationMessagesPage('a','owner@gmail.com','alice@gmail.com', { query: readQuery });
  assert.equal(first.sourcesPending, true);
  assert.equal(first.messages[0].body, 'Already cached body', 'Cached text returns while Gmail source is blocked');
  assert.deepEqual(first.messages[0].attachments, []);
  const second = await conversationMessagesPage('a','owner@gmail.com','alice@gmail.com', { query: readQuery });
  assert.equal(second.sourcesPending, true);
  assert.equal(fetches, 1, 'Polling joins the in-flight inspection instead of fetching again');
  release({ payload: { mimeType:'multipart/mixed', parts:[
    { mimeType:'text/plain', body:{ data:Buffer.from('Original source').toString('base64url') } },
    { mimeType:'image/jpeg', filename:'photo.jpg', body:{ attachmentId:'inline-photo',size:1200 },
      headers:[{ name:'Content-Disposition',value:'inline' },{ name:'Content-ID',value:'<photo>' }] },
    { mimeType:'application/pdf', filename:'notes.pdf', body:{ attachmentId:'document',size:100 } },
  ] } });
  const deadline = Date.now() + 1000;
  while (!savedSources.length && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 5));
  assert.equal(savedSources.length, 1);
  assert.deepEqual(savedSources[0].attachments.map(file => file.id), ['inline-photo','document']);
  const complete = await conversationMessagesPage('a','owner@gmail.com','alice@gmail.com', { query: readQuery });
  assert.equal(complete.sourcesPending, false, 'Pending clears only after complete attachment persistence');
  assert.deepEqual(complete.messages[0].attachments.map(file => file.id), ['inline-photo','document']);
  assert.equal(fetches, 1, 'Version 2 rows do not re-fetch on every poll');
});

test('source failure preserves cached files and leaves legacy rows unchecked for retry', async () => {
  await add('legacy-failure',100);
  await db.query("UPDATE messages SET attachments='[]'::jsonb WHERE message_id='legacy-failure'");
  fetchSource = async () => { throw Error('source temporarily unavailable'); };
  const page = await conversationMessagesPage('a','owner@gmail.com','alice@gmail.com', { query: readQuery });
  assert.equal(page.sourcesPending, true);
  await new Promise(resolve => setImmediate(resolve));
  const stored = await db.query("SELECT source_version,body_text,attachments FROM messages WHERE message_id='legacy-failure'");
  assert.equal(stored.rows[0].source_version,0);
  assert.equal(stored.rows[0].body_text,'Original body');
  assert.deepEqual(stored.rows[0].attachments,[]);
  assert.equal(savedSources.length,0);
});

test('production background directory reads bounded metadata and source snippets without loading bodies', async () => {
  await add('alice', 200, { body: 'x'.repeat(200000), snippet: 'Original source preview' });
  await add('bob', 100, { name: 'Bob Baker', email: 'bob@gmail.com', body: 'y'.repeat(200000) });
  const directory = isolated.exports.createConversationDirectory({ query: readQuery, batchSize: 1 });
  const source = { sourceVersion: 'complete-one', sourceComplete: true, sourceState: 'complete' };
  let page = directory.page('a','owner@gmail.com',source);
  assert.equal(page.historyComplete, false);
  const deadline = Date.now() + 2000;
  while (!page.historyComplete && Date.now() < deadline) {
    await new Promise(resolve => setTimeout(resolve, 5));
    page = directory.page('a','owner@gmail.com',source);
  }
  assert.equal(page.historyComplete, true);
  assert.equal(page.totalConversations, 2);
  assert.equal(page.conversations[0].preview, 'Original source preview');
  assert.ok(reads.every(read => read.rows.length <= 1));
  assert.ok(reads.every(read => !/body_text|quote|summary/.test(read.sql)));
  const count = reads.length;
  directory.page('a','owner@gmail.com',source);
  assert.equal(reads.length, count, 'Polling a finished snapshot never rescans the archive');
});
