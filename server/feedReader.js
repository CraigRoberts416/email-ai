const { withCompleteness, needsUnreadReconciliation } = require('./feedStorage');

function createFeedReader({ messageStore, mailNotifications, gmailSync, processingWorker, logger = console }) {
  return async function readFeedPage(userId, options, countsOnly = false) {
    const page = await (countsOnly
      ? messageStore.getUnreadCounts(userId, options)
      : messageStore.getUnreadPage(userId, options));
    // This starts a shared background refresh when needed, but never waits for
    // Gmail. A sample begun before the last completed import cannot certify it.
    const provider = mailNotifications.unreadCountSnapshot(userId, {
      notBefore: new Date(page.syncCompletedAt).getTime() || 0,
    });
    const result = { ...withCompleteness(page, provider.unreadCount), ...provider };
    if (needsUnreadReconciliation(result)) {
      gmailSync.ensureUnreadSync(userId, { force: result.syncState === 'complete' })
        .then(() => processingWorker.wakeWorker(userId))
        .catch(error => logger.warn('[feed] unread reconciliation failed:', error.message));
    }
    return result;
  };
}

module.exports = { createFeedReader };
