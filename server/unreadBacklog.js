// Exhaustive unread reconciliation is separate from the all-mail archive
// import. It can repair an old account without re-fetching every read email.
function createUnreadBacklog({ userStore, messageStore, listPage, metadata, toRecord, now = () => new Date() }) {
  const running = new Map();
  const attempted = new Map();

  function ensure(userId, { force = false } = {}) {
    if (running.has(userId)) return running.get(userId);
    if (attempted.has(userId) && now() - attempted.get(userId) < 60000) return Promise.resolve();
    const task = run(userId, force).finally(() => running.delete(userId));
    running.set(userId, task);
    return task;
  }

  async function run(userId, force) {
    const user = await userStore.getUser(userId);
    if (!force && user?.unread_sync_state === 'complete') return;
    const started = now();
    attempted.set(userId, started);
    await userStore.setUnreadSyncState(userId, 'syncing');
    try {
      const seen = new Set();
      const pages = new Set();
      let pageToken = null;
      do {
        const page = await listPage(userId, pageToken, null);
        const ids = [...new Set(page.messageIds)];
        ids.forEach(id => seen.add(id));
        const missing = await messageStore.unreadMetadataNeeded(userId, ids);
        if (missing.length) {
          const messages = await metadata(userId, missing);
          await messageStore.upsertMessages(userId, messages.map(message => toRecord(message, false)));
        }
        pageToken = page.nextPageToken;
        if (pageToken && pages.has(pageToken)) throw new Error('Gmail repeated an unread page token');
        if (pageToken) pages.add(pageToken);
      } while (pageToken);
      const excluded = {};
      for (const label of ['SPAM', 'TRASH']) {
        const ids = new Set();
        const visited = new Set();
        let token = null;
        do {
          const page = await listPage(userId, token, label);
          page.messageIds.forEach(id => ids.add(id));
          token = page.nextPageToken;
          if (token && visited.has(token)) throw new Error('Gmail repeated an unread folder page token');
          if (token) visited.add(token);
        } while (token);
        excluded[label] = [...ids];
      }
      // Apply only after every page succeeds. A failed page must never mark
      // the unvisited part of a mailbox read. Recent local/provider changes
      // are protected by each row's labels_updated_at watermark.
      await messageStore.reconcileUnreadLabels(userId, [...seen], started, excluded);
      await userStore.setUnreadSyncState(userId, 'complete');
    } catch (error) {
      await userStore.setUnreadSyncState(userId, 'error');
      throw error;
    }
  }

  return { ensure };
}

module.exports = { createUnreadBacklog };
