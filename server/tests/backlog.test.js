const { test } = require('node:test');
const assert = require('node:assert/strict');
const { PGlite } = require('@electric-sql/pglite');
const fs = require('node:fs');
const { createBacklogService, createBacklogRepository, registerBacklogRoutes } = require('../backlog');

function fixture(total = 22000) {
  const jobs = new Map(), mutations = [], queries = [], writes = [];
  let time = Date.parse('2026-09-28T14:00:00Z'), failed = false;
  const repository = {
    async create(user, job) { jobs.set(user + job.id, structuredClone(job)); },
    async get(user, id) { const job = jobs.get(user + id); if (!job) throw Object.assign(Error(), { status: 404 }); return structuredClone(job); },
    async change(user, id, work) {
      const job = await this.get(user, id);
      const result = await work(job, async (ids, floor) => { writes.push({ ids, floor }); return ids; });
      jobs.set(user + id, job); return result;
    },
  };
  const service = createBacklogService({ repository, now: () => time, tokenFor: async () => 'test', fetch: async (url, options) => {
    if (url.endsWith('/profile')) return { ok: true, json: async () => ({ historyId: '10000000000000000000' }) };
    if (url.endsWith('/batchModify')) {
      if (failed) return { ok: false, status: 503 };
      mutations.push(JSON.parse(options.body)); return { ok: true };
    }
    const params = new URL(url).searchParams; queries.push(params);
    const start = Number(params.get('pageToken') ?? 0), end = Math.min(total, start + 500);
    return { ok: true, json: async () => ({ messages: Array.from({ length: end - start }, (_, i) => ({ id: `mail-${start + i}` })),
      ...(end < total ? { nextPageToken: String(end) } : {}), resultSizeEstimate: 1 }) };
  } });
  const step = (job, action, user = 'a') => service.step(user, job.id, job.version, action);
  async function preview(before) { let job = await service.create('a', before); while (job.phase === 'scanning') job = await step(job, 'scan'); return job; }
  return { service, step, preview, mutations, queries, writes, jobs, fail: value => failed = value, age: () => time += 25 * 3600000 };
}

test('22K preview counts every page exactly and changes no mail; only approval can start batches', async () => {
  const h = fixture(); let job = await h.preview();
  assert.equal(job.total, 22000); assert.equal(h.queries.length, 44); assert.equal(h.mutations.length, 0);
  await assert.rejects(h.step(job, 'apply'), { status: 409 });
  job = await h.step(job, 'start');
  const approved = job;
  while (job.phase !== 'complete') job = await h.step(job, 'apply');
  assert.equal(job.completed, 22000); assert.equal(h.mutations.length, 44);
  const ids = h.mutations.flatMap(batch => batch.ids);
  assert.equal(new Set(ids).size, 22000);
  assert.ok(h.mutations.every(batch => batch.ids.length <= 1000 && JSON.stringify(batch.removeLabelIds) === '["UNREAD"]' && !batch.addLabelIds));
  assert.equal((await h.step(approved, 'apply')).completed, 22000, 'lost-response replay returns durable progress without another mutation');
  assert.equal(h.mutations.length, 44);
  assert.equal(h.writes[0].floor, '10000000000000000001', 'provider revision keeps integer precision');
});

test('cutoff uses absolute seconds, excludes Spam/Trash, and retains archived mail', async () => {
  const h = fixture(2); await h.preview('2026-08-29T04:00:00Z');
  assert.equal(h.queries[0].get('q'), 'is:unread -in:spam -in:trash before:1787976000');
  assert.equal(h.queries[0].get('includeSpamTrash'), 'false');
});

test('approved manifest stays fixed; no query re-run can sweep in new arrivals', async () => {
  const h = fixture(501); let job = await h.preview(); const queryCount = h.queries.length;
  job = await h.step(job, 'start'); job = await h.step(job, 'apply');
  assert.equal(job.completed, 500); job = await h.step(job, 'apply');
  assert.equal(job.completed, 501); assert.equal(h.queries.length, queryCount);
  assert.deepEqual(h.mutations[1].ids, ['mail-500']);
});

test('provider failure keeps the unconfirmed batch outstanding and supports resume', async () => {
  const h = fixture(501); let job = await h.step(await h.preview(), 'start');
  job = await h.step(job, 'apply'); h.fail(true);
  await assert.rejects(h.step(job, 'apply'), { status: 502 });
  assert.equal((await h.service.get('a', job.id)).completed, 500);
  h.fail(false); job = await h.step(job, 'apply'); assert.equal(job.completed, 501);
  assert.equal(h.mutations.length, 2);
});

test('job ownership, scope validation and expired unapproved previews fail closed', async () => {
  const h = fixture(1); const job = await h.preview();
  await assert.rejects(h.service.get('other', job.id), { status: 404 });
  await assert.rejects(h.step(job, 'start', 'other'), { status: 404 });
  await assert.rejects(h.service.create('a', 'invalid'), { status: 400 });
  await assert.rejects(h.service.create('a', '2099-01-01'), { status: 400 });
  h.age(); await assert.rejects(h.step(job, 'start'), { status: 409 });
  assert.equal(h.mutations.length, 0);
});

test('approved progress resumes after a day, while zero-match cleanup never mutates Gmail', async () => {
  const h = fixture(1); let job = await h.step(await h.preview(), 'start'); h.age();
  job = await h.step(job, 'apply'); assert.equal(job.phase, 'complete');
  const empty = fixture(0); const result = await empty.step(await empty.preview(), 'start');
  assert.equal(result.phase, 'complete'); assert.equal(empty.mutations.length, 0);
});

test('SQL repository persists batches, preserves unrelated labels/newer revisions and scopes both jobs and writes', async t => {
  const db = new PGlite(); t.after(() => db.close());
  await db.exec(fs.readFileSync(require.resolve('../schema.sql'), 'utf8'));
  await db.exec(`INSERT INTO users(user_id,access_token,refresh_token,token_expiry) VALUES ('a','x','x',NOW()),('b','x','x',NOW());
    INSERT INTO messages(user_id,message_id,label_ids,history_id) VALUES
    ('a','old',ARRAY['UNREAD','INBOX','STARRED'],'100'),('a','newer',ARRAY['UNREAD','STARRED'],'300'),
    ('b','old',ARRAY['UNREAD'],'100')`);
  const pool = { query: (...args) => db.query(...args), connect: async () => ({ query: (...args) => db.query(...args), release() {} }) };
  const repo = createBacklogRepository(pool);
  await repo.create('a', { id: 'run', completed: 0 });
  await repo.change('a', 'run', async (job, saveReads) => {
    assert.deepEqual(await saveReads(['old', 'newer'], '201'), ['old']); job.completed = 2;
  });
  assert.equal((await repo.get('a', 'run')).completed, 2);
  const { rows } = await db.query('SELECT user_id, message_id, label_ids, history_id FROM messages ORDER BY user_id,message_id');
  assert.deepEqual(rows.map(r => r.label_ids), [['UNREAD','STARRED'],['INBOX','STARRED'],['UNREAD']]);
  assert.equal(rows[1].history_id, '201');
  await assert.rejects(repo.get('b', 'run'), { status: 404 });
  await assert.rejects(repo.change('a', 'run', async job => { job.completed = 999; throw Error('interrupted'); }));
  assert.equal((await repo.get('a', 'run')).completed, 2);
});

test('HTTP routes authenticate the account and keep preview/read operations distinct', async t => {
  const app = require('express')(); app.use(require('express').json());
  const h = fixture(1);
  registerBacklogRoutes(app, { resolveUserId: async req => req.headers['x-test-user'], service: h.service });
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const base = `http://127.0.0.1:${server.address().port}/feed/backlog`;
  const request = (path = '', body, user = 'a') => fetch(base + path, {
    method: body ? 'POST' : 'GET', headers: { 'Content-Type': 'application/json', ...(user ? { 'x-test-user': user } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  assert.equal((await request('', {}, null)).status, 401);
  let job = await (await request('', {})).json();
  assert.equal((await request(`/${job.id}`, undefined, 'other')).status, 404);
  job = await (await request(`/${job.id}/step`, { action: 'scan', version: job.version })).json();
  assert.equal(job.phase, 'ready'); assert.equal(job.total, 1); assert.equal(h.mutations.length, 0);
  assert.equal((await request(`/${job.id}/step`, { action: 'apply', version: job.version })).status, 409);
  job = await (await request(`/${job.id}/step`, { action: 'start', version: job.version })).json();
  job = await (await request(`/${job.id}/step`, { action: 'apply', version: job.version })).json();
  assert.equal(job.phase, 'complete'); assert.equal(job.completed, 1); assert.equal(h.mutations.length, 1);
});
