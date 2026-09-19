const { setTimeout: delay } = require('node:timers/promises');

// Archive imports, unread reconciliation and notification batches can visit
// the same message rows in different orders. Serialize their short database
// writes, never their Gmail requests, to prevent opposing row-lock cycles.
function createMailboxWriter({ pool, wait = delay, maxAttempts = 3 }) {
  const queues = new Map();

  async function execute(userId, sql, params) {
    for (let attempt = 0; ; attempt++) {
      const client = await pool.connect();
      let retry;
      try {
        await client.query('BEGIN');
        await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))',
          [`decision-inbox:mailbox-write:${userId}`]);
        const result = await client.query(sql, params);
        await client.query('COMMIT');
        return result;
      } catch (error) {
        try { await client.query('ROLLBACK'); } catch { /* Preserve the original error. */ }
        retry = ['40P01', '40001'].includes(error.code) && attempt + 1 < maxAttempts;
        if (!retry) throw error;
      } finally {
        client.release();
      }
      await wait(50 * 2 ** attempt);
    }
  }

  function write(userId, sql, params) {
    const previous = queues.get(userId) ?? Promise.resolve();
    // Wait before checkout: queued imports must not exhaust the connection
    // pool while card/count reads need a connection of their own.
    const pending = previous.catch(() => {}).then(() => execute(userId, sql, params));
    queues.set(userId, pending);
    return pending.finally(() => { if (queues.get(userId) === pending) queues.delete(userId); });
  }
  return { write };
}

module.exports = { createMailboxWriter };
