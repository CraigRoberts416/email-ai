const cron       = require('node-cron');
const userStore  = require('./userStore');
const { query }  = require('./db');

async function registerWatch(userId) {
  const topicName = process.env.GOOGLE_PUBSUB_TOPIC;
  if (!topicName) {
    console.warn('[watch] GOOGLE_PUBSUB_TOPIC not set — skipping watch registration');
    return;
  }

  const accessToken = await userStore.getValidAccessToken(userId);
  const res = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/watch', {
    method:  'POST',
    headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body:    JSON.stringify({ topicName, labelIds: ['INBOX'] }),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    console.error(`[watch] registration failed for ${userId.slice(0, 8)}…:`, JSON.stringify(err));
    return;
  }

  const data   = await res.json();
  const expiry = new Date(Number(data.expiration));
  await userStore.updateWatchExpiry(userId, expiry);
  console.log(`[watch] registered for ${userId.slice(0, 8)}… expires ${expiry.toISOString()}`);
}

async function renewAllExpiring() {
  const { rows } = await query(`
    SELECT user_id FROM users
    WHERE watch_expiry IS NULL
       OR watch_expiry < NOW() + INTERVAL '24 hours'
  `);
  for (const { user_id } of rows) {
    try {
      await registerWatch(user_id);
    } catch (err) {
      console.error(`[watch] renewal failed for ${user_id.slice(0, 8)}…:`, err.message);
    }
  }
}

function startWatchRenewalCron() {
  cron.schedule('0 3 * * *', async () => {
    console.log('[watch] daily renewal check');
    try { await renewAllExpiring(); }
    catch (err) { console.error('[watch] cron error:', err.message); }
  });
  console.log('[watch] renewal cron scheduled (daily at 3am)');
}

module.exports = { registerWatch, renewAllExpiring, startWatchRenewalCron };
