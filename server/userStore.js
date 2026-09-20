const { query } = require('./db');
const { randomUUID } = require('node:crypto');
const accountAccess = require('./accountAccess');

async function upsertUser(userId, fields) {
  const connectionVersion = fields.connectionVersion ?? accountAccess.version();
  return accountAccess.withLifecycle(userId, () => accountAccess.mutate(userId, () => {
    accountAccess.assertNotDisconnectedSince(userId, connectionVersion);
    return upsertConnectedUser(userId, fields, connectionVersion);
  }));
}

async function upsertConnectedUser(userId, { email, accessToken, refreshToken, tokenExpiry, onboardingHistoryId, pushToken }, connectionVersion) {
  await query(`
    INSERT INTO users (user_id, email, access_token, refresh_token, token_expiry, onboarding_history_id, updated_at)
    VALUES ($1, $2, $3, $4, $5, $6, NOW())
    ON CONFLICT (user_id) DO UPDATE SET
      email                 = COALESCE(EXCLUDED.email, users.email),
      access_token          = EXCLUDED.access_token,
      refresh_token         = COALESCE(EXCLUDED.refresh_token, users.refresh_token),
      token_expiry          = EXCLUDED.token_expiry,
      onboarding_history_id = COALESCE(users.onboarding_history_id, EXCLUDED.onboarding_history_id),
      updated_at            = NOW()
  `, [userId, email ?? null, accessToken, refreshToken ?? null, new Date(tokenExpiry), onboardingHistoryId ?? null]);
  accountAccess.assertNotDisconnectedSince(userId, connectionVersion);
  accountAccess.activate(userId);

  if (pushToken) {
    await query(
      'UPDATE users SET push_token = $2 WHERE user_id = $1',
      [userId, pushToken]
    );
  }
}

async function updatePushToken(userId, pushToken) {
  await query(
    `UPDATE users SET push_token = $2, updated_at = NOW(),
      notifications_started_at = CASE WHEN push_token IS NULL AND $2::text IS NOT NULL
        THEN NOW() ELSE notifications_started_at END
      WHERE user_id = $1 AND ($2::text IS NULL OR (access_token <> '' AND refresh_token <> ''))`,
    [userId, pushToken]
  );
}

async function getUser(userId) {
  const { rows } = await query('SELECT * FROM users WHERE user_id = $1', [userId]);
  return rows[0] ?? null;
}

async function getUserByEmail(email) {
  const { rows } = await query('SELECT * FROM users WHERE email = $1', [email]);
  return rows[0] ?? null;
}

async function updateTokens(userId, { accessToken, tokenExpiry }) {
  await query(
    "UPDATE users SET access_token = $2, token_expiry = $3, updated_at = NOW() WHERE user_id = $1 AND refresh_token <> ''",
    [userId, accessToken, new Date(tokenExpiry)]
  );
}

async function updateHistoryId(userId, historyId) {
  await query('UPDATE users SET history_id = $2 WHERE user_id = $1', [userId, historyId]);
}

async function updateWatchExpiry(userId, expiry) {
  await query('UPDATE users SET watch_expiry = $2 WHERE user_id = $1', [userId, new Date(expiry)]);
}

async function setUnreadSyncState(userId, state) {
  await query(`
    UPDATE users SET unread_sync_state = $2,
      unread_sync_completed_at = CASE WHEN $2 = 'complete' THEN NOW() ELSE unread_sync_completed_at END
    WHERE user_id = $1
  `, [userId, state]);
}

async function setAllMailSyncState(userId, state, { revalidate = false, generation = null } = {}) {
  const result = await query(`UPDATE users SET all_mail_sync_state = $2,
    all_mail_sync_cursor = CASE WHEN $2 IN ('pending', 'complete') THEN NULL ELSE all_mail_sync_cursor END,
    all_mail_sync_generation = CASE WHEN $2 = 'pending' THEN NULL ELSE all_mail_sync_generation END,
    all_mail_sync_revalidate = CASE WHEN $2 = 'complete' THEN FALSE ELSE all_mail_sync_revalidate OR $3 END,
    all_mail_sync_completed_at = CASE WHEN $2 = 'complete' THEN NOW() ELSE all_mail_sync_completed_at END
    WHERE user_id = $1 AND ($4::text IS NULL OR all_mail_sync_generation = $4)
    RETURNING user_id`, [userId, state, revalidate, generation]);
  return result.rows.length > 0;
}

async function beginAllMailSync(userId) {
  const { rows } = await query(`UPDATE users SET
    all_mail_sync_generation = CASE WHEN all_mail_sync_state IN ('syncing','failed') AND all_mail_sync_generation IS NOT NULL
      THEN all_mail_sync_generation ELSE $2 END,
    all_mail_sync_started_at = CASE WHEN all_mail_sync_state IN ('syncing','failed') AND all_mail_sync_generation IS NOT NULL
      THEN all_mail_sync_started_at ELSE NOW() END,
    all_mail_sync_cursor = CASE WHEN all_mail_sync_state IN ('syncing','failed') AND all_mail_sync_generation IS NOT NULL
      THEN all_mail_sync_cursor ELSE NULL END,
    all_mail_sync_state = 'syncing'
    WHERE user_id = $1 RETURNING all_mail_sync_generation AS generation,
      all_mail_sync_started_at AS "startedAt", all_mail_sync_cursor AS cursor,
      all_mail_sync_revalidate AS revalidate`, [userId, randomUUID()]);
  if (!rows[0]) throw new Error('Cannot sync an unknown account');
  return rows[0];
}

async function setAllMailSyncCursor(userId, cursor, generation = null) {
  const result = await query(`UPDATE users SET all_mail_sync_cursor = $2
    WHERE user_id = $1 AND ($3::text IS NULL OR all_mail_sync_generation = $3)
    RETURNING user_id`, [userId, cursor, generation]);
  return result.rows.length > 0;
}

async function getValidAccessToken(userId, { signal } = {}) {
  const accessSignal = accountAccess.signal(userId);
  accountAccess.assertActive(userId);
  const user = await getUser(userId);
  accessSignal.throwIfAborted();
  signal?.throwIfAborted();
  if (!user?.access_token || !user?.refresh_token) throw new Error('Mailbox disconnected or unavailable');

  const expiryMs = new Date(user.token_expiry).getTime();
  if (expiryMs - Date.now() > 5 * 60 * 1000) {
    return user.access_token;
  }

  if (!user.refresh_token) throw new Error(`No refresh token for user: ${userId}`);

  const body = new URLSearchParams({
    client_id:     process.env.GOOGLE_CLIENT_ID,
    grant_type:    'refresh_token',
    refresh_token: user.refresh_token,
  });

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method:  'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body:    body.toString(),
    signal: AbortSignal.any([accessSignal, signal ?? AbortSignal.timeout(30000)]),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(`Token refresh failed: ${JSON.stringify(err)}`);
  }

  const data = await res.json();
  accessSignal.throwIfAborted();
  const newExpiry = Date.now() + data.expires_in * 1000;
  await updateTokens(userId, { accessToken: data.access_token, tokenExpiry: newExpiry });
  accessSignal.throwIfAborted();
  signal?.throwIfAborted();
  return data.access_token;
}

async function getAllUsers() {
  const { rows } = await query("SELECT * FROM users WHERE access_token <> '' AND refresh_token <> ''");
  return rows;
}

async function disconnectUser(userId) {
  await accountAccess.mutate(userId, () => query(`UPDATE users SET access_token = '', refresh_token = '',
    token_expiry = to_timestamp(0), push_token = NULL, watch_expiry = NULL,
    updated_at = NOW() WHERE user_id = $1`, [userId]));
}

async function resetInterruptedProcessing(userId) {
  await query("UPDATE messages SET ai_status = 'queued' WHERE user_id = $1 AND ai_status = 'processing'", [userId]);
}

async function getUsersByPushToken(pushToken) {
  if (!pushToken) return [];
  const { rows } = await query("SELECT * FROM users WHERE push_token = $1 AND access_token <> '' AND refresh_token <> ''", [pushToken]);
  return rows;
}

module.exports = { upsertUser, getUser, getUserByEmail, getAllUsers, getUsersByPushToken, updateTokens, updateHistoryId, updateWatchExpiry, getValidAccessToken, updatePushToken, setUnreadSyncState, setAllMailSyncState, setAllMailSyncCursor, beginAllMailSync, disconnectUser, resetInterruptedProcessing };
