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

module.exports = { query, pool };
