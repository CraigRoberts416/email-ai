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

  // The sender's own picture for this message, extracted from its HTML. Held
  // as the original URL and only ever served through the proxy.
  await pool.query(`
    ALTER TABLE messages ADD COLUMN IF NOT EXISTS image_url TEXT
  `);

  // Every hero generated before this instant came from a prompt that told the
  // model to fall back to "a quiet, sensory still life", and it took that
  // literally: an airline, a car service and a property marketplace all came
  // back as the same dim photograph of a desk. They are not salvageable by
  // tweaking anything downstream — the subject is wrong.
  //
  // Dropping them makes /feed treat each domain as uncached and regenerate it
  // against the new prompt. The cutoff is a fixed instant rather than a flag,
  // which makes this self-limiting: after the first pass every surviving row
  // is newer than it, so re-running on every boot deletes nothing.
  const dropped = await pool.query(`
    DELETE FROM sender_domain_assets WHERE created_at < TIMESTAMPTZ '2026-09-15 12:45:00+00'
  `);
  if (dropped.rowCount) {
    console.log(`[db] dropped ${dropped.rowCount} hero asset(s) from the still-life prompt`);
  }

  // The first extraction pass ran before the filter knew about tracking GIFs
  // and masthead strips, and it chose both: a DNC beacon and a 700x114 West
  // Elm header were sitting in the feed as "this email's picture". Clearing
  // them lets the backfill re-decide with the stricter rules. Costs Gmail
  // fetches, not model calls, and is bounded by the same 400.
  // The files an email carried. JSONB rather than a join table: it is a
  // handful of rows read only alongside their message, and never queried
  // across messages.
  await pool.query(`
    ALTER TABLE messages ADD COLUMN IF NOT EXISTS attachments JSONB
  `);

  // One line about who a sender is, generated alongside their hero and cached
  // per domain. Nullable on purpose: a missing sentence is a blank, and a
  // wrong one is the product asserting something false about a real company.
  await pool.query(`
    ALTER TABLE sender_domain_assets ADD COLUMN IF NOT EXISTS description TEXT
  `);

  // Everyone who was on a message besides the sender. A direct message is
  // identified by its participant set, so without this there is nothing to
  // group a conversation by.
  await pool.query(`
    ALTER TABLE messages ADD COLUMN IF NOT EXISTS participants JSONB
  `);

  // What the sender actually wrote, with the quoted history cut off.
  //
  // A conversation was rendering `quote || snippet` — the model's pulled
  // sentence, or Gmail's 200-character preview. Both are fragments, and in a
  // chat bubble a fragment reads as the whole message, so every turn looked
  // truncated because it was. NULL means never fetched; '' means fetched and
  // there was nothing but quoted text.
  await pool.query(`
    ALTER TABLE messages ADD COLUMN IF NOT EXISTS body_text TEXT
  `);

  // Bodies stored before link footnotes were recognised as quoted material.
  // A tracker rewrites every URL and leaves the rewrite in brackets on its own
  // line, so these are cached with 70 characters of hex where the sender wrote
  // nothing. Clearing them re-asks Gmail on next open; NULL is the "never
  // fetched" state and costs one round trip, not a model call.
  const stale = await pool.query(`
    UPDATE messages SET body_text = NULL
    WHERE body_text ~ '(^|\\n)[[:space:]]*[[<][[:space:]]*(https?://|mailto:)[^[:space:]]*[[:space:]]*[]>][[:space:]]*($|\\n)'
  `);
  if (stale.rowCount) {
    console.log(`[db] re-asking ${stale.rowCount} message(s) for a body`);
  }

  // Bodies stored before a text/plain part was checked for actually being
  // text. Senders paste the HTML build into it, and one list row read
  // `<p>Hi CRAIG,</p><br><br>`.
  const markup = await pool.query(`
    UPDATE messages SET body_text = NULL
    WHERE body_text ~* '</?(p|br|div|table|td|tr|span|img|h[1-6])[ />]'
  `);
  if (markup.rowCount) {
    console.log(`[db] re-asking ${markup.rowCount} message(s) whose body was markup`);
  }

  // Every "no picture here" verdict reached before candidates could fall
  // through is worth re-asking. Extraction used to commit to a single image,
  // so an email whose first candidate measured as a masthead strip was written
  // off entirely — even when a real photograph sat three images below it. That
  // is most of the 173 empties in this mailbox.
  const recheck = await pool.query(`
    UPDATE messages SET image_url = NULL
    WHERE post_cutoff = TRUE
      AND (image_url = ''
           OR image_url ~* '\\.gif(\\?|$)'
           OR image_url ~* '(banner|header|masthead|preheader|wordmark)')
  `);
  if (recheck.rowCount) {
    console.log(`[db] re-asking ${recheck.rowCount} message(s) for a picture`);
  }

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
