CREATE TABLE IF NOT EXISTS users (
  user_id               TEXT PRIMARY KEY,
  email                 TEXT,
  access_token          TEXT NOT NULL,
  refresh_token         TEXT NOT NULL,
  token_expiry          TIMESTAMPTZ NOT NULL,
  history_id            TEXT,
  onboarding_history_id TEXT,
  watch_expiry          TIMESTAMPTZ,
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS messages (
  user_id             TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  message_id          TEXT NOT NULL,
  thread_id           TEXT,
  label_ids           TEXT[] NOT NULL DEFAULT '{}',
  subject             TEXT NOT NULL DEFAULT '',
  from_name           TEXT NOT NULL DEFAULT '',
  from_email          TEXT NOT NULL DEFAULT '',
  snippet             TEXT NOT NULL DEFAULT '',
  internal_date       BIGINT NOT NULL DEFAULT 0,
  history_id          TEXT,
  synced_at           TIMESTAMPTZ DEFAULT NOW(),
  ai_status           TEXT NOT NULL DEFAULT 'none',
  post_cutoff         BOOLEAN NOT NULL DEFAULT FALSE,
  quote               TEXT,
  summary             TEXT,
  action              TEXT,
  action_url          TEXT,
  requires_attention  BOOLEAN NOT NULL DEFAULT FALSE,
  PRIMARY KEY (user_id, message_id)
);

CREATE INDEX IF NOT EXISTS idx_messages_user_date
  ON messages(user_id, internal_date DESC);

CREATE INDEX IF NOT EXISTS idx_messages_unread
  ON messages(user_id, internal_date DESC)
  WHERE 'UNREAD' = ANY(label_ids);

CREATE INDEX IF NOT EXISTS idx_messages_worker
  ON messages(user_id, internal_date DESC)
  WHERE ai_status IN ('none', 'queued')
  AND ('UNREAD' = ANY(label_ids) OR post_cutoff = TRUE);
