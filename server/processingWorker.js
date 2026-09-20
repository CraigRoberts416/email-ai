const messageStore    = require('./messageStore');
const gmailSync       = require('./gmailSync');
const { cleanEmailForAI } = require('./emailCleaner');
const emailImage      = require('./emailImage');
const emailAttachments = require('./emailAttachments');
const accountAccess = require('./accountAccess');

// Injected by index.js to avoid circular imports
let _streamInterpretEmail     = null;
let _streamDecideActionSurface = null;
let _detectRiskSignals        = null;
let _emitSSE                  = null;
let _onMessageReady           = null;

function init({ streamInterpretEmail, streamDecideActionSurface, detectRiskSignals, emitSSE, onMessageReady }) {
  _streamInterpretEmail      = streamInterpretEmail;
  _streamDecideActionSurface = streamDecideActionSurface;
  _detectRiskSignals         = detectRiskSignals;
  _emitSSE                   = emitSSE;
  _onMessageReady            = onMessageReady;
}

// Per-user active worker flag and wake-up mechanism
const activeWorkers = new Map(); // userId → unique loop identity
const workerJobs = new Map();
const wakeCallbacks  = new Map(); // userId → () => void

function wakeWorker(userId) {
  const cb = wakeCallbacks.get(userId);
  if (cb) {
    wakeCallbacks.delete(userId);
    cb();
  }
}

async function processNext(userId) {
  const workSignal = accountAccess.signal(userId);
  workSignal.throwIfAborted();
  let pendingRisk = null;
  const messageId = await messageStore.getNextToProcess(userId);
  workSignal.throwIfAborted();
  if (!messageId) return false;

  await messageStore.setAiStatus(userId, messageId, 'processing');
  _emitSSE(userId, { type: 'processing', messageId });

  try {
    const rawMsg = await gmailSync.fetchFullMessage(userId, messageId, { priority: 0 });
    workSignal.throwIfAborted();
    const email  = cleanEmailForAI(rawMsg);

    // The email's own picture, taken from the HTML we already have. Stored,
    // never fetched here: the bytes come through our proxy so the sender
    // cannot time the reader's scroll. Failing to find one is normal and
    // costs the post nothing — it falls back to the sender's hero.
    try {
      // Ranked, then measured. The name of an image never says whether it is
      // a photograph or a 1280x102 masthead strip, so every candidate is
      // fetched and checked until one is actually a picture.
      const candidates = emailImage.pickCandidates(emailImage.extractHtml(rawMsg.payload)) ?? [];
      const picture = await emailImage.resolveBest(candidates);
      if (picture) {
        await messageStore.setImageUrl(userId, messageId, picture);
        // The proxy's URL, never the sender's. Handing the raw one to the
        // device over SSE would undo the entire point of proxying it — the
        // phone would fetch the sender's CDN directly and announce itself.
        const base = process.env.RENDER_EXTERNAL_URL || process.env.PUBLIC_URL;
        if (base) {
          const host = base.replace(/^https?:\/\//, '').replace(/\/$/, '');
          _emitSSE(userId, {
            type: 'field-complete', messageId, field: 'imageUrl',
            value: emailImage.buildImageUrl(host, userId, messageId),
          });
        }
      }
    } catch (err) {
      console.warn(`[worker] image extract failed on ${messageId}: ${err.message}`);
    }

    // The files, as metadata only. An email with a signed contract on it used
    // to look identical to one carrying nothing, and "did they actually send
    // it" is one of the few questions a mail client exists to answer.
    try {
      const files = emailAttachments.extractAttachments(rawMsg.payload);
      if (files.length) await messageStore.setAttachments(userId, messageId, files);
    } catch (err) {
      console.warn(`[worker] attachment scan failed on ${messageId}: ${err.message}`);
    }

    // Save unsubscribe URL immediately — available before AI finishes
    workSignal.throwIfAborted();
    if (email.unsubscribeUrl) {
      await messageStore.setUnsubscribeUrl(userId, messageId, email.unsubscribeUrl);
      _emitSSE(userId, { type: 'field-complete', messageId, field: 'unsubscribeUrl', value: email.unsubscribeUrl });
    }

    // Fraud is checked alongside interpretation rather than after it. The
    // verdict is one non-streaming call and the two summaries are the visible
    // ones, so running it in parallel costs the card nothing — and a scam
    // label that lands after the user has already read the summary has
    // arrived too late to do the only job it has.
    //
    // It never throws: a message the risk check could not reach still gets
    // its card, and still gets it without a POSSIBLE SCAM on it.
    workSignal.throwIfAborted();
    const riskVerdict = pendingRisk = _detectRiskSignals(email, messageId, userId)
      .catch(err => {
        console.warn(`[worker] risk detection failed on ${messageId}: ${err.message}`);
        return null;
      });

    await _streamInterpretEmail(email, messageId, userId);
    workSignal.throwIfAborted();
    await _streamDecideActionSurface(email, messageId, userId);
    await riskVerdict;
    workSignal.throwIfAborted();

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
    // Push delivery cannot turn successful interpretation into an AI failure.
    // Its durable queue retries separately from the paid processing pipeline.
    if (_onMessageReady) Promise.resolve().then(() => _onMessageReady(userId, messageId))
      .catch(err => console.warn('[worker] push handoff failed:', err.message));
    console.log(`[worker] done: ${messageId} (user: ${userId.slice(0, 8)}…)`);
  } catch (err) {
    if (workSignal.aborted) return false;
    console.error(`[worker] error on ${messageId}:`, err.message);
    // Counted, not just marked. A message that fails three times is failing
    // for its own reasons and must stop being re-queued; one that failed
    // because the mailbox credential was broken deserves another go once it
    // is fixed. Without the count those two are indistinguishable, and the
    // difference is whether a retry is free or is a paid model call on loop.
    await messageStore.failAttempt(userId, messageId);
  } finally {
    // A request already handed to the model may finish; disconnect does not
    // confirm while that task is still outstanding.
    if (pendingRisk) await pendingRisk;
  }

  return true;
}

async function workerLoop(userId, identity) {
  console.log(`[worker] loop started for user ${userId.slice(0, 8)}…`);
  while (activeWorkers.get(userId) === identity) {
    const processed = await processNext(userId);
    if (!processed && activeWorkers.get(userId) === identity) {
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
  if (accountAccess.signal(userId).aborted) return;
  if (activeWorkers.get(userId)) return;
  const identity = {};
  activeWorkers.set(userId, identity);
  const job = workerLoop(userId, identity).catch(err => {
    console.error(`[worker] loop crashed for ${userId.slice(0, 8)}…:`, err.message);
    if (activeWorkers.get(userId) === identity) activeWorkers.delete(userId);
  }).finally(() => {
    if (workerJobs.get(userId) === job) workerJobs.delete(userId);
  });
  workerJobs.set(userId, job);
}

function stopWorker(userId) {
  activeWorkers.delete(userId);
  wakeWorker(userId); // unblock any sleep
  return workerJobs.get(userId) ?? Promise.resolve();
}

module.exports = { init, startWorker, stopWorker, wakeWorker };
