const { test, before, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const { PGlite } = require('@electric-sql/pglite');

let db;
let calls;
let failRead;
const readQuery = async (sql, params) => {
  calls.push({ sql, params });
  if (failRead) throw Error('database unavailable');
  return db.query(sql, params);
};

// Execute the actual helper against PostgreSQL semantics, with no external
// database credentials or image-generation service available to the test.
const filename = path.join(__dirname, 'heroImageGenerator.js');
const isolated = new Module(filename, module);
isolated.filename = filename;
isolated.require = name => {
  if (name === 'fs' || name === 'path') return require(name);
  if (name === 'sharp') return () => { throw Error('Cached lookup must not process or invent an image'); };
  if (name === './db') return { query: readQuery };
  if (name === './senderIdentity') return require('./senderIdentity');
  throw Error(`Unexpected dependency ${name}`);
};
isolated._compile(fs.readFileSync(filename, 'utf8'), filename);
const { getCachedAssets } = isolated.exports;

before(async () => {
  db = new PGlite();
  await db.exec(`CREATE TABLE sender_domain_assets (
    domain TEXT PRIMARY KEY, bg_color TEXT, description TEXT, image_bytes BYTEA
  )`);
});
after(async () => db?.close());
beforeEach(async () => { await db.exec('TRUNCATE sender_domain_assets'); calls = []; failRead = false; });

test('subdomains and multi-label domains share the exact cached brand asset in one query', async () => {
  await db.query(`INSERT INTO sender_domain_assets VALUES
    ('amazon.co.uk','#123456','Known company',decode(REPEAT('FF',10000),'hex')),
    ('example.com','#ABCDEF',NULL,NULL),('gmail.com','#000000','Must not surface for people',NULL)`);
  const result = await getCachedAssets(['ship.amazon.co.uk', 'MAIL.AMAZON.CO.UK', 'amazon.co.uk',
    'example.com', 'new-company.com', 'gmail.com', 'co.uk', 'localhost']);
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].params, [['amazon.co.uk', 'example.com', 'new-company.com']]);
  assert.equal(result.size, 4);
  assert.deepEqual(result.get('ship.amazon.co.uk'), { domain: 'amazon.co.uk', bgColor: '#123456', description: 'Known company' });
  assert.equal(result.get('ship.amazon.co.uk'), result.get('MAIL.AMAZON.CO.UK'));
  assert.equal(result.get('amazon.co.uk').domain, 'amazon.co.uk');
  assert.equal(result.get('example.com').description, null);
  assert.equal(result.has('new-company.com'), false, 'A missing asset stays missing');
  assert.equal(result.has('gmail.com'), false, 'Never attach a generated provider image to a person');
  assert.equal(Object.hasOwn(result.get('amazon.co.uk'), 'image_bytes'), false);
  assert.doesNotMatch(calls[0].sql, /image_bytes|SELECT\s+\*/i, 'Feed metadata never fetches binary artwork');
});

test('a full 200-domain page takes one lookup, not 200 pool slots', async () => {
  await db.query(`INSERT INTO sender_domain_assets(domain,bg_color,description)
    SELECT 'brand'||n||'.com','#123456','Known company' FROM generate_series(1,50) n`);
  const domains = Array.from({ length: 200 }, (_, i) => `mail.brand${i + 1}.com`);
  const result = await getCachedAssets(new Set(domains).values());
  assert.equal(calls.length, 1);
  assert.equal(calls[0].params[0].length, 200);
  assert.equal(result.size, 50);
  for (let i = 1; i <= 50; i++) assert.equal(result.get(`mail.brand${i}.com`).domain, `brand${i}.com`);
});

test('empty, invalid or only personal-provider domains do not query the database', async () => {
  assert.equal((await getCachedAssets([])).size, 0);
  assert.equal((await getCachedAssets(['gmail.com', 'mail.proton.me', '', null, 'co.uk', 'a@b.com'])).size, 0);
  assert.equal(calls.length, 0);
});

test('failed lookup stays an error so caller cannot mistake outage for missing artwork', async () => {
  failRead = true;
  await assert.rejects(getCachedAssets(['amazon.com']), /database unavailable/);
  assert.equal(calls.length, 1);
});
