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
