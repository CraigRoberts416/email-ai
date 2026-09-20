const accountAccess = require('./accountAccess');

// Deliberately retains server message records. This operation stops access; it
// is not provider account deletion, OAuth grant revocation or history erasure.
function createAccountDisconnect({ userStore, processingWorker, stopWatch,
  onDisconnect = async () => {}, refreshDetachedToken = async () => {}, access = accountAccess }) {
  const inFlight = new Map();
  return function disconnect(userId) {
    if (inFlight.has(userId)) return inFlight.get(userId);
    const lifecycle = access.withLifecycle ?? ((_id, work) => work());
    const job = lifecycle(userId, async () => {
      const user = await userStore.getUser(userId);
      access.suspend(userId);
      // Stop persisted access before any optional provider cleanup. An offline
      // Google stop-watch response must not leave credentials available.
      await userStore.disconnectUser(userId);
      await Promise.all([processingWorker.stopWorker(userId), onDisconnect(userId)]);
      await userStore.resetInterruptedProcessing(userId);
      let watchStopped = !user?.access_token;
      if (user?.access_token) {
        try { watchStopped = await stopWatch(user.access_token); } catch { watchStopped = false; }
      }
      if (user?.push_token) {
        // Badge correction is independent of terminating server access.
        await refreshDetachedToken(user.push_token).catch(() => {});
      }
      return { disconnected: true, watchStopped, storedMailDeleted: false, googleGrantRevoked: false };
    }).finally(() => inFlight.delete(userId));
    inFlight.set(userId, job);
    return job;
  };
}

function registerAccountDisconnectRoute(app, { resolveUserId, disconnect }) {
  app.delete('/auth/account', async (req, res) => {
    const userId = await resolveUserId(req);
    if (!userId) return res.status(401).json({ error: 'unauthorized' });
    try { res.json(await disconnect(userId)); }
    catch { res.status(503).json({ error: 'Disconnect could not be confirmed. Retry safely.' }); }
  });
}

module.exports = { createAccountDisconnect, registerAccountDisconnectRoute };
