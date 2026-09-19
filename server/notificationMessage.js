// A notification can outlive the unread page that originally contained it.
// Resolve its card by authenticated mailbox and message ID, without importing
// it into the unread feed or scheduling interpretation/historical alerts.
function registerNotificationMessageRoute(app, { resolveUserId, messageStore, gmailSync,
  cardsForMessages, sanitize = value => value, logger = console }) {
  app.get('/messages/:messageId/card', async (req, res) => {
    try {
      const userId = await resolveUserId(req);
      if (!userId) return res.status(401).json({ error: 'unauthorized' });
      const { messageId } = req.params;
      if (!/^[A-Za-z0-9_-]{1,256}$/.test(messageId)) return res.status(400).json({ error: 'invalid message ID' });
      let record = await messageStore.getMessage(userId, messageId);
      if (!record) {
        const records = await gmailSync.fetchSenderRecords(userId, [messageId]);
        record = records.find(message => message.messageId === messageId);
        if (!record) return res.status(404).json({ error: 'email no longer available' });
        await messageStore.upsertMessages(userId, [record]);
      }
      const cards = await cardsForMessages(req, userId, [record], { generateHeroes: false });
      res.setHeader('Cache-Control', 'no-store');
      return res.json(sanitize({ card: cards[0] }));
    } catch (error) {
      logger.warn('[notification-message] lookup failed:', error.message);
      return res.status(502).json({ error: 'email temporarily unavailable' });
    }
  });
}

module.exports = { registerNotificationMessageRoute };
