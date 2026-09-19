function createMarkReadHandler({ resolveUserId, userStore, messageStore, emitSSE,
  notifyMailbox, fetch: providerFetch = fetch, logger = console }) {
  const queues = new Map();

  async function confirm(userId, messageId) {
    const accessToken = await userStore.getValidAccessToken(userId);
    const url = `https://gmail.googleapis.com/gmail/v1/users/me/messages/${encodeURIComponent(messageId)}`;
    const headers = { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' };
    const before = await providerFetch(`${url}?format=minimal`, { headers, signal: AbortSignal.timeout(15000) });
    if (!before.ok) throw Object.assign(new Error('Gmail read-state lookup failed'), { statusCode: 502 });
    let message = await before.json();
    const valid = value => value?.id === messageId && (value.labelIds === undefined
      || (Array.isArray(value.labelIds) && value.labelIds.every(label => typeof label === 'string')));
    if (!valid(message)) throw Object.assign(new Error('Invalid Gmail read state'), { statusCode: 502 });
    const wasUnread = (message.labelIds ?? []).includes('UNREAD');
    if (wasUnread) {
      const changed = await providerFetch(`${url}/modify`, {
        method: 'POST', headers, body: JSON.stringify({ removeLabelIds: ['UNREAD'] }),
        signal: AbortSignal.timeout(15000),
      });
      if (!changed.ok) throw Object.assign(new Error('Gmail modify failed'), { statusCode: 502 });
      message = await changed.json();
      if (!valid(message) || (message.labelIds ?? []).includes('UNREAD')) {
        throw Object.assign(new Error('Gmail did not confirm read state'), { statusCode: 502 });
      }
    }
    // Use the provider's current label set, including archive/folder changes.
    // An already-read cached post is a successful reconciliation, not another
    // decrement of the mailbox's unread count.
    await messageStore.updateLabelIds(userId, messageId, message.labelIds ?? []);
    return { success: true, wasUnread, readChanged: wasUnread };
  }

  return async (req, res) => {
    const userId = await resolveUserId(req);
    if (!userId) return res.status(401).json({ error: 'unauthorized' });
    const { messageId } = req.params;
    try {
      const key = JSON.stringify([userId, messageId]);
      const previous = queues.get(key) ?? Promise.resolve();
      const pending = previous.catch(() => {}).then(() => confirm(userId, messageId));
      queues.set(key, pending);
      let result;
      try { result = await pending; }
      finally { if (queues.get(key) === pending) queues.delete(key); }
      emitSSE(userId, { type: 'message-read', messageId, wasUnread: result.wasUnread, readChanged: result.readChanged });
      res.json(result);
      Promise.resolve().then(() => notifyMailbox(userId))
        .catch(error => logger.warn('[push] read badge failed:', error.message));
    } catch (error) {
      logger.error('[read] failed:', error.message);
      res.status(error.statusCode === 502 ? 502 : 500).json({ error: 'mark-read failed' });
    }
  };
}

module.exports = { createMarkReadHandler };
