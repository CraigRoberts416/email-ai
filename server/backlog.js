const { randomUUID } = require('crypto');

const BASE = 'https://gmail.googleapis.com/gmail/v1/users/me';
const fail = (status, message) => Object.assign(new Error(message), { status });
const publicJob = job => ({ id: job.id, phase: job.phase, before: job.before,
  total: job.ids.length, completed: job.completed, version: job.version, readIDs: job.readIDs ?? [] });

// Each preview is an immutable list of provider identities, not an approximate
// Gmail resultSizeEstimate or a query re-run after approval.
function createBacklogService({ repository, tokenFor, fetch: request = fetch,
  invalidate = () => {}, now = () => Date.now() }) {
  async function provider(userId, path, body) {
    const response = await request(`${BASE}${path}`, {
      method: body ? 'POST' : 'GET',
      headers: { Authorization: `Bearer ${await tokenFor(userId)}`, 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) throw fail(response.status === 401 ? 401 : 502, 'Gmail could not finish this step.');
    return body ? null : response.json();
  }
  return {
    async create(userId, before) {
      const cutoff = before == null ? now() : Date.parse(before);
      if (!Number.isFinite(cutoff) || cutoff <= 0 || cutoff > now()) throw fail(400, 'Invalid cutoff date.');
      const job = { id: randomUUID(), phase: 'scanning', before: new Date(cutoff).toISOString(),
        created: now(), ids: [], cursor: null, pages: [], completed: 0, version: 0 };
      await repository.create(userId, job);
      return publicJob(job);
    },
    async get(userId, id) { return publicJob(await repository.get(userId, id)); },
    async step(userId, id, version, action) {
      if (!Number.isInteger(version) || !['scan', 'start', 'apply'].includes(action)) throw fail(400, 'Invalid step.');
      const result = await repository.change(userId, id, async (job, saveReads) => {
        // A response lost after commit returns its durable progress on retry.
        if (job.version !== version) return publicJob(job);
        if (['scanning', 'ready'].includes(job.phase) && now() - job.created > 24 * 3600000) {
          throw fail(409, 'This preview expired. Create a new preview.');
        }
        if (action === 'scan' && job.phase === 'scanning') {
          const q = `is:unread -in:spam -in:trash before:${Math.floor(Date.parse(job.before) / 1000)}`;
          const params = new URLSearchParams({ q, maxResults: '500', includeSpamTrash: 'false' });
          if (job.cursor) params.set('pageToken', job.cursor);
          const page = await provider(userId, `/messages?${params}`);
          if (page.messages != null && (!Array.isArray(page.messages) || page.messages.some(m => typeof m.id !== 'string'))) {
            throw fail(502, 'Invalid Gmail inventory.');
          }
          const next = page.nextPageToken || null;
          if (next && (typeof next !== 'string' || job.pages.includes(next))) throw fail(502, 'Gmail repeated a page.');
          job.ids = [...new Set([...job.ids, ...(page.messages ?? []).map(m => m.id)])];
          job.cursor = next;
          if (next) job.pages.push(next); else job.phase = 'ready';
        } else if (action === 'start' && job.phase === 'ready') {
          job.phase = job.ids.length ? 'applying' : 'complete';
        } else if (action === 'apply' && job.phase === 'applying') {
          const ids = job.ids.slice(job.completed, job.completed + 500);
          invalidate(userId);
          try {
            // A lower revision bound prevents a late pre-operation snapshot
            // from restoring UNREAD. Never overwrite a newer provider revision.
            const profile = await provider(userId, '/profile');
            if (!/^[0-9]+$/.test(profile.historyId ?? '')) throw fail(502, 'Missing Gmail revision.');
            const floor = String(BigInt(profile.historyId) + 1n);
            await provider(userId, '/messages/batchModify', { ids, removeLabelIds: ['UNREAD'] });
            job.readIDs = await saveReads(ids, floor);
            job.completed += ids.length;
            if (job.completed === job.ids.length) job.phase = 'complete';
          } finally { invalidate(userId); }
        } else if (job.phase !== 'complete') throw fail(409, 'This step is not available.');
        job.version++;
        return publicJob(job);
      });
      // Also invalidate after COMMIT; an in-flight count must not cache the
      // pre-commit labels between provider confirmation and the DB write.
      if (action === 'apply') invalidate(userId);
      return result;
    },
  };
}

function createBacklogRepository(pool) {
  return {
    async create(userId, job) {
      await pool.query('INSERT INTO backlog_jobs (user_id, id, state) VALUES ($1, $2, $3)', [userId, job.id, job]);
    },
    async get(userId, id) {
      const { rows } = await pool.query('SELECT state FROM backlog_jobs WHERE user_id = $1 AND id = $2', [userId, id]);
      if (!rows.length) throw fail(404, 'Cleanup not found.');
      return rows[0].state;
    },
    async change(userId, id, work) {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        await client.query("SET LOCAL lock_timeout = '4s'");
        const { rows } = await client.query('SELECT state FROM backlog_jobs WHERE user_id = $1 AND id = $2 FOR UPDATE', [userId, id]);
        if (!rows.length) throw fail(404, 'Cleanup not found.');
        const job = rows[0].state;
        const result = await work(job, async (ids, floor) => {
          const { rows } = await client.query(`UPDATE messages SET label_ids = array_remove(label_ids, 'UNREAD'),
            history_id = $3, labels_updated_at = NOW()
            WHERE user_id = $1 AND message_id = ANY($2::text[])
              AND CASE WHEN history_id ~ '^[0-9]+$' THEN history_id::numeric < $3::numeric ELSE TRUE END
            RETURNING message_id`,
          [userId, ids, floor]);
          return rows.map(row => row.message_id);
        });
        await client.query('UPDATE backlog_jobs SET state = $3, updated_at = NOW() WHERE user_id = $1 AND id = $2', [userId, id, job]);
        await client.query('COMMIT');
        return result;
      } catch (error) { await client.query('ROLLBACK'); throw error; }
      finally { client.release(); }
    },
  };
}

function registerBacklogRoutes(app, { resolveUserId, service }) {
  const handler = fn => async (req, res) => {
    try {
      const userId = await resolveUserId(req);
      if (!userId) return res.status(401).json({ error: 'unauthorized' });
      res.json(await fn(req, userId));
    } catch (error) {
      const status = error.code === 'MAILBOX_RECONNECT_REQUIRED' ? 401 : (error.status ?? 500);
      res.status(status).json({ error: status === 409 ? error.message : 'Could not finish cleanup. Your progress is saved.' });
    }
  };
  app.post('/feed/backlog', handler((req, userId) => service.create(userId, req.body?.before)));
  app.get('/feed/backlog/:id', handler((req, userId) => service.get(userId, req.params.id)));
  app.post('/feed/backlog/:id/step', handler((req, userId) => service.step(userId, req.params.id, req.body?.version, req.body?.action)));
}
module.exports = { createBacklogService, createBacklogRepository, registerBacklogRoutes };
