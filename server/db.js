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
}

runMigrations().catch(err =>
  console.error('[db] migration error:', err.message)
);

module.exports = { query, pool };
