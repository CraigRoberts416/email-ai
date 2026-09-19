const crypto = require('node:crypto');
const { isAPNsToken } = require('./apns');
const { createUnreadCountCache } = require('./unreadCountCache');

function validCount(value) { return Number.isSafeInteger(value) && value >= 0; }

function buildAPNsPayload(userId, badgeCount, message) {
  const aps = { 'content-available': 1 };
  if (validCount(badgeCount)) aps.badge = badgeCount;
  if (message) {
    // Actual sender and subject; no generated interpretation or private body
    // is exposed on the lock screen.
    aps.alert = {
      title: (message.fromName || message.fromEmail || '').slice(0, 150),
      body: (message.subject || '').slice(0, 250),
    };
    aps.sound = 'default';
    aps['thread-id'] = 'mail';
  }
  return {
    aps, type: message ? 'new-mail' : 'mailbox-updated', userId,
    ...(message ? { messageId: message.messageId } : {}),
    ...(validCount(badgeCount) ? { unreadCount: badgeCount } : {}),
  };
}

function createMailNotifications({ apns, expo, isExpoPushToken, messageStore, userStore, gmailSync, logger = console,
  countCacheOptions = {} }) {
  const lastBadges = new Map();
  const queues = new Map();
  let warnedMissingConfig = false;
  const counts = createUnreadCountCache({
    ...countCacheOptions, load: (userId, options) => gmailSync.getUnreadCount(userId, options), logger,
  });

  function validToken(token) { return isAPNsToken(token) || isExpoPushToken(token); }

  function unreadCount(userId, options = { force: true }) { return counts.refresh(userId, options); }

  async function badgeCount(pushToken, options = { force: true }) {
    const users = await userStore.getUsersByPushToken(pushToken);
    const values = await Promise.all(users.map(user => unreadCount(user.user_id, options)));
    // A partial sum is not an accurate device total. Preserve the last badge
    // if even one connected account is temporarily unavailable.
    return values.every((count, index) => validCount(count) && counts.isCurrent(users[index].user_id, count))
      ? values.reduce((sum, count) => sum + count, 0) : null;
  }

  async function send(user, count, message = null) {
    const token = user.push_token;
    if (!token || !validToken(token)) return false;
    // A disconnect may have completed while this delivery waited in the queue.
    if (user.user_id) {
      const current = await userStore.getUser(user.user_id);
      if (current?.push_token !== token) return false;
    }
    const collapseId = message
      ? crypto.createHash('sha256').update(`${user.user_id}:${message.messageId}`).digest('hex')
      : 'mailbox-badge';
    if (isAPNsToken(token)) {
      if (!apns.isConfigured()) {
        if (!warnedMissingConfig) {
          logger.warn('[push] native APNs credentials are not configured; delivery is pending');
          warnedMissingConfig = true;
        }
        return false;
      }
      try {
        await apns.send(token, buildAPNsPayload(user.user_id, count, message), { collapseId });
      } catch (err) {
        if (err.code === 'Unregistered') {
          const accounts = await userStore.getUsersByPushToken(token);
          await Promise.all(accounts.map(account => userStore.updatePushToken(account.user_id, null)));
        }
        throw err;
      }
    } else {
      const payload = buildAPNsPayload(user.user_id, count, message);
      const [ticket] = await expo.sendPushNotificationsAsync([{
        to: token, _contentAvailable: true, collapseId,
        priority: message ? 'high' : 'normal',
        data: { type: payload.type, userId: user.user_id, messageId: message?.messageId, unreadCount: count },
        ...(validCount(count) ? { badge: count } : {}),
        ...(message ? { title: payload.aps.alert.title, body: payload.aps.alert.body, sound: 'default', channelId: 'new-mail' } : {}),
      }]);
      if (ticket?.status !== 'ok') {
        if (ticket?.details?.error === 'DeviceNotRegistered') {
          await userStore.updatePushToken(user.user_id, null);
        }
        throw new Error(`Expo push rejected: ${ticket?.details?.error || 'unknown'}`);
      }
    }
    if (validCount(count)) lastBadges.set(token, count);
    return true;
  }

  function serialize(token, task) {
    const previous = queues.get(token) ?? Promise.resolve();
    const pending = previous.catch(() => {}).then(task);
    queues.set(token, pending);
    return pending.finally(() => { if (queues.get(token) === pending) queues.delete(token); });
  }

  async function notifyMailbox(userId, newUnreadIds = [], { forceBadge = false, mailboxChanged = true } = {}) {
    // Feed correctness does not depend on notification permission or a token.
    if (mailboxChanged) counts.invalidate(userId);
    if (newUnreadIds.length) await messageStore.queueNotifications(userId, [...new Set(newUnreadIds)]);
    const user = await userStore.getUser(userId);
    if (!user?.push_token || !validToken(user.push_token)) return;
    if (isAPNsToken(user.push_token) && !apns.isConfigured()) {
      if (!warnedMissingConfig) {
        logger.warn('[push] native APNs credentials are not configured; delivery is pending');
        warnedMissingConfig = true;
      }
      return;
    }
    return serialize(user.push_token, async () => {
      const count = await badgeCount(user.push_token, { force: mailboxChanged || forceBadge });
      let alerted = false;
      const pending = await messageStore.getPendingNotifications(userId);
      for (const message of pending) {
        if (!message.requiresAttention || message.aiStatus !== 'done' || !message.labelIds.includes('UNREAD')) continue;
        if (!await messageStore.claimNotification(userId, message.messageId)) continue;
        let delivered = false;
        try {
          delivered = await send(user, count, message);
          alerted = delivered || alerted;
        } catch (err) {
          logger.warn('[push] notification delivery failed:', err.code || err.message);
        } finally {
          await messageStore.finishNotification(userId, message.messageId, delivered);
        }
      }
      if (!alerted && validCount(count) && (forceBadge || lastBadges.get(user.push_token) !== count)) {
        try { await send(user, count); }
        catch (err) { logger.warn('[push] badge delivery failed:', err.code || err.message); }
      }
    });
  }

  async function refreshDetachedToken(pushToken) {
    if (!validToken(pushToken)) return;
    return serialize(pushToken, async () => {
      const count = await badgeCount(pushToken);
      if (validCount(count)) await send({ user_id: null, push_token: pushToken }, count);
    });
  }

  return { unreadCount, unreadCountSnapshot: counts.snapshot, invalidateUnreadCount: counts.invalidate,
    badgeCount, notifyMailbox, refreshDetachedToken, validToken };
}

module.exports = { createMailNotifications, buildAPNsPayload, validCount };
