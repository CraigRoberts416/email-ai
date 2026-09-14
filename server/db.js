require('dotenv').config();
const { Pool } = require('pg');

// Requires DATABASE_URL environment variable — e.g.:
//   postgres://user:password@host:5432/dbname
// For local development, set DATABASE_URL=postgres://localhost/email_ai

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DATABASE_URL?.includes('localhost')
    ? false
    : { rejectUnauthorized: false },
});

pool.on('error', (err) => {
  console.error('[db] unexpected pool error:', err.message);
});

async function query(sql, params) {
  const client = await pool.connect();
  try {
    return await client.query(sql, params);
  } finally {
    client.release();
  }
}

// Run lightweight migrations on startup — idempotent, safe to re-run.
async function runMigrations() {
  // schema.sql is entirely CREATE ... IF NOT EXISTS, so applying it on every
  // boot costs nothing and means a table added to the schema can never again
  // be missing from a deployed database. sender_domain_assets was added to
  // the schema and to no migration, so it was never created in production —
  // and every /feed request 500'd on a table nobody had noticed was absent.
  await pool.query(
    require('fs').readFileSync(require('path').join(__dirname, 'schema.sql'), 'utf8')
  );
  await pool.query(`
    ALTER TABLE messages ADD COLUMN IF NOT EXISTS unsubscribe_url TEXT
  `);
  await pool.query(`
    ALTER TABLE users ADD COLUMN IF NOT EXISTS push_token TEXT
  `);
  // The fraud verdict and the evidence behind it. Two columns, because the
  // card prints the verdict and the explainer screen prints the evidence —
  // and a verdict with nothing to show for it is a vibe, not a finding.
  // Defaults to 'none': a database that has never been asked must not imply
  // that every message in it is clean-by-inspection, but it must also never
  // imply the opposite.
  await pool.query(`
    ALTER TABLE messages ADD COLUMN IF NOT EXISTS risk_level TEXT NOT NULL DEFAULT 'none'
  `);
  await pool.query(`
    ALTER TABLE messages ADD COLUMN IF NOT EXISTS risk_evidence JSONB
  `);

  // 'error' was a terminal state. getNextToProcess only ever selects 'none'
  // and 'queued', so a message that failed once was never looked at again —
  // and when the Google client id was wrong, every fetch failed and 18,828
  // messages were written off in a batch. Nothing in the product could
  // recover them, and nothing said so.
  //
  // The counter is what makes retrying safe: without it, a message that fails
  // for its own reasons would be re-queued on every boot forever, and each
  // attempt is a paid model call.
  await pool.query(`
    ALTER TABLE messages ADD COLUMN IF NOT EXISTS ai_attempts INT NOT NULL DEFAULT 0
  `);

  // Re-queue only what the feed actually draws on. The rest of that batch is
  // pre-cutoff backlog going back to 2023 that the product deliberately does
  // not interpret, and re-queueing it would buy nothing and cost ~19,000
  // model calls.
  const { rowCount } = await pool.query(`
    UPDATE messages SET ai_status = 'none'
    WHERE ai_status = 'error' AND post_cutoff = TRUE AND ai_attempts < 3
  `);
  if (rowCount) console.log(`[db] re-queued ${rowCount} failed post-cutoff message(s)`);
}

runMigrations().catch(err =>
  console.error('[db] migration error:', err.message)
);

module.exports = { query, pool };
