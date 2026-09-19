const { setTimeout: delay } = require('node:timers/promises');

// A rolling deploy runs migrations beside the previous server's writers.
// Retry only the failed, idempotent statement; do not repeat earlier repairs.
function createMigrationQuery({ query, wait = delay, random = Math.random,
  maxAttempts = 6, logger = console }) {
  return async function migrationQuery(sql, params) {
    for (let attempt = 0; ; attempt++) {
      try { return await query(sql, params); }
      catch (error) {
        if (!['40P01', '40001'].includes(error.code) || attempt + 1 >= maxAttempts) throw error;
        const pause = 250 * 2 ** attempt + Math.floor(random() * 250);
        logger.warn(`[db] migration conflict ${error.code}; retry ${attempt + 1}/${maxAttempts - 1} in ${pause}ms`);
        // pool.query's implicit failed transaction has already rolled back;
        // the next attempt uses a clean connection/transaction.
        await wait(pause);
      }
    }
  };
}

module.exports = { createMigrationQuery };
