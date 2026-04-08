const messageStore    = require('./messageStore');
const gmailSync       = require('./gmailSync');
const { cleanEmailForAI } = require('./emailCleaner');

// Injected by index.js to avoid circular imports
let _streamInterpretEmail     = null;
let _streamDecideActionSurface = null;
let _emitSSE                  = null;

function init({ streamInterpretEmail, streamDecideActionSurface, emitSSE }) {
  _streamInterpretEmail      = streamInterpretEmail;
  _streamDecideActionSurface = streamDecideActionSurface;
  _emitSSE                   = emitSSE;
}

// Per-user active worker flag and wake-up mechanism
const activeWorkers = new Map(); // userId → boolean
const wakeCallbacks  = new Map(); // userId → () => void

function wakeWorker(userId) {
  const cb = wakeCallbacks.get(userId);
  if (cb) {
    wakeCallbacks.delete(userId);
    cb();
  }
}

async function processNext(userId) {
  const messageId = await messageStore.getNextToProcess(userId);
  if (!messageId) return false;

  await messageStore.setAiStatus(userId, messageId, 'processing');
  _emitSSE(userId, { type: 'processing', messageId });

  try {
    const rawMsg = await gmailSync.fetchFullMessage(userId, messageId);
    const email  = cleanEmailForAI(rawMsg);

    // Save unsubscribe URL immediately — available before AI finishes
    if (email.unsubscribeUrl) {
      await messageStore.setUnsubscribeUrl(userId, messageId, email.unsubscribeUrl);
      _emitSSE(userId, { type: 'field-complete', messageId, field: 'unsubscribeUrl', value: email.unsubscribeUrl });
    }

    await _streamInterpretEmail(email, messageId, userId);
    await _streamDecideActionSurface(email, messageId, userId);

    // Consolidate final AI fields from DB (set field-by-field during streaming)
    const record = await messageStore.getMessage(userId, messageId);
    await messageStore.setAiFields(userId, messageId, {
      quote:             record.quote,
      summary:           record.summary,
      action:            record.action,
      actionUrl:         record.actionUrl,
      requiresAttention: record.requiresAttention,
    });

    _emitSSE(userId, { type: 'message-ready', messageId });
    console.log(`[worker] done: ${messageId} (user: ${userId.slice(0, 8)}…)`);
  } catch (err) {
    console.error(`[worker] error on ${messageId}:`, err.message);
    await messageStore.setAiStatus(userId, messageId, 'error');
  }

  return true;
}

async function workerLoop(userId) {
  console.log(`[worker] loop started for user ${userId.slice(0, 8)}…`);
  while (activeWorkers.get(userId)) {
    const processed = await processNext(userId);
    if (!processed) {
      // Queue empty — idle, wake on new work or after 30s
      await new Promise(resolve => {
        const timer = setTimeout(resolve, 30_000);
        wakeCallbacks.set(userId, () => { clearTimeout(timer); resolve(); });
      });
    }
    // Brief yield between items
    await new Promise(r => setTimeout(r, 50));
  }
  console.log(`[worker] loop stopped for user ${userId.slice(0, 8)}…`);
}

function startWorker(userId) {
  if (activeWorkers.get(userId)) return;
  activeWorkers.set(userId, true);
  workerLoop(userId).catch(err => {
    console.error(`[worker] loop crashed for ${userId.slice(0, 8)}…:`, err.message);
    activeWorkers.delete(userId);
  });
}

function stopWorker(userId) {
  activeWorkers.delete(userId);
  wakeWorker(userId); // unblock any sleep
}

module.exports = { init, startWorker, stopWorker, wakeWorker };
