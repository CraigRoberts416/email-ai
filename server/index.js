require('dotenv').config();

const fs = require('fs');
const path = require('path');
const express = require('express');
const cors = require('cors');
const OpenAI = require('openai');
const feedStore = require('./feedStore');

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

const app = express();

app.use(cors());
app.use(express.json({ limit: '10mb' }));

// ─── Avatar helpers ───────────────────────────────────────────────────────

const LOGO_DEV_TOKEN = process.env.LOGO_DEV_TOKEN ?? 'pk_bcvjuzCeRt6gzuz5ZoYayg';

const FREE_MAIL_DOMAINS = new Set([
  'gmail.com', 'yahoo.com', 'outlook.com', 'hotmail.com',
  'icloud.com', 'live.com', 'msn.com', 'ymail.com',
]);

function rootDomain(domain) {
  const parts = domain.split('.');
  return parts.slice(-2).join('.');
}

function cleanLinks(links) {
  return links.filter(({ url }) => {
    if (!url || url.length < 15) return false;
    if (/\.(css|png|jpg|jpeg|gif|webp|svg|ico|woff|woff2)(\?|$)/i.test(url)) return false;
    if (/unsubscribe/i.test(url)) return false;
    return true;
  });
}

function resolveAvatarUri(email) {
  const domain = rootDomain(email.sender.domain?.toLowerCase() ?? '');
  if (!domain || FREE_MAIL_DOMAINS.has(domain)) return null;
  return `https://img.logo.dev/${domain}?token=${LOGO_DEV_TOKEN}`;
}

function resolveAvatarFallbackText(email) {
  const source = email.sender.name || email.sender.email || '';
  return source.charAt(0).toUpperCase();
}

// ─── Prompt loader ────────────────────────────────────────────────────────

function loadPrompt(name) {
  return fs.readFileSync(path.join(__dirname, 'prompts', `${name}.txt`), 'utf8');
}

function renderPrompt(template, vars) {
  return Object.entries(vars).reduce((result, [key, value]) => {
    return result.replace(new RegExp(`\\{\\{${key}\\}\\}`, 'g'), () => String(value));
  }, template);
}

const PROMPTS = {
  interpretEmail: loadPrompt('interpret-email'),
  decideActionSurface: loadPrompt('decide-action-surface'),
  sessionRecap: loadPrompt('session-recap'),
};

// ─── XML helpers ─────────────────────────────────────────────────────────
//
// Prompts now output XML-tagged fields instead of JSON, making streaming
// field boundary detection robust and unambiguous.

/**
 * Extract a named field from XML-tagged output (non-streaming).
 * Returns the trimmed content between <fieldName> and </fieldName>, or null.
 */
function parseXmlField(text, fieldName) {
  const open  = `<${fieldName}>`;
  const close = `</${fieldName}>`;
  const start = text.indexOf(open);
  if (start === -1) return null;
  const end = text.indexOf(close, start + open.length);
  if (end === -1) return null;
  return text.slice(start + open.length, end).trim();
}

/**
 * Extract streaming content for a named field from the accumulated output.
 * Returns null if the field's opening tag has not yet appeared.
 * Returns { newChunk, complete, value } otherwise.
 *
 * To avoid emitting partial closing tags as content, we hold back the last
 * (close.length - 1) bytes of the safe window until we know it isn't the
 * start of </fieldName>.
 *
 * @param {string} accum       Full accumulated output so far
 * @param {string} fieldName   XML field name (e.g. "quote")
 * @param {number} alreadySent Number of field-content bytes already sent as chunks
 * @returns {{ newChunk: string|null, complete: boolean, value: string }|null}
 */
function extractStreamingField(accum, fieldName, alreadySent) {
  const open  = `<${fieldName}>`;
  const close = `</${fieldName}>`;

  const startIdx = accum.indexOf(open);
  if (startIdx === -1) return null;

  const contentStart = startIdx + open.length;
  const closeIdx     = accum.indexOf(close, contentStart);

  if (closeIdx !== -1) {
    const value    = accum.slice(contentStart, closeIdx);
    const newChunk = value.slice(alreadySent);
    return { newChunk: newChunk || null, complete: true, value };
  }

  // Field started but closing tag not yet seen.
  // Don't send the last (close.length - 1) chars in case they start the closing tag.
  const safeEnd  = Math.max(contentStart, accum.length - (close.length - 1));
  const available = accum.slice(contentStart, safeEnd);
  const newChunk  = available.slice(alreadySent);
  return { newChunk: newChunk || null, complete: false, value: null };
}

// ─── SSE helpers ──────────────────────────────────────────────────────────

// sseClients: userId → Set<res>
const sseClients = new Map();

function getSseClients(userId) {
  if (!sseClients.has(userId)) sseClients.set(userId, new Set());
  return sseClients.get(userId);
}

function emitSSE(userId, data) {
  const clients  = getSseClients(userId);
  const payload  = `data: ${JSON.stringify(data)}\n\n`;
  for (const res of clients) {
    try { res.write(payload); } catch {}
  }
}

// ─── Per-user serial processing queue ────────────────────────────────────
//
// Cards are processed one at a time per user. This keeps the streaming model
// simple — no concurrent SSE multiplexing needed within a single user's feed.
// The normal case (pre-app-open processing) does not use this queue; it is
// the exception path for emails arriving while the user is in the app.

const userQueues = new Map(); // userId → Promise (tail of chain)

function enqueueProcessing(userId, fn) {
  const tail = userQueues.get(userId) ?? Promise.resolve();
  const next  = tail.then(fn).catch(err => {
    console.error(`[queue] error for user ${userId.slice(0, 8)}…:`, err.message);
  });
  userQueues.set(userId, next);
}

// ─── Streaming AI functions ───────────────────────────────────────────────

/**
 * Stream interpretEmail output for one card.
 * Emits SSE chunk events as tokens arrive, then field-complete when each tag closes.
 * Updates feedStore AI fields as each field completes.
 */
async function streamInterpretEmail(email, cardId, userId) {
  const prompt = renderPrompt(PROMPTS.interpretEmail, {
    senderName:             email.sender.name,
    senderEmail:            email.sender.email,
    senderDomain:           email.sender.domain,
    subject:                email.subject,
    snippet:                email.snippet,
    plainText:              email.body.plainText?.slice(0, 1500) ?? '',
    htmlText:               email.body.htmlText?.slice(0, 1500) ?? '',
    links:                  cleanLinks(email.signals.structuredLinks ?? []).length,
    unsubscribePresent:     email.signals.unsubscribePresent,
    freeMailDomain:         email.signals.freeMailDomain,
    replyToMismatch:        email.signals.replyToMismatch,
    suspiciousSubjectHints: JSON.stringify(email.signals.suspiciousSubjectHints),
    greetingGeneric:        email.signals.greetingGeneric,
    hasAttachments:         email.signals.hasAttachments,
  });

  const stream = await openai.responses.create({
    model:  'gpt-5',
    input:  prompt,
    stream: true,
  });

  let accum       = '';
  const sentUpTo  = { quote: 0, summary: 0 };
  const fieldsDone = { quote: false, summary: false };

  for await (const event of stream) {
    if (event.type !== 'response.output_text.delta') continue;
    accum += event.delta;

    for (const field of ['quote', 'summary']) {
      if (fieldsDone[field]) continue;
      const result = extractStreamingField(accum, field, sentUpTo[field]);
      if (!result) continue;

      if (result.newChunk) {
        emitSSE(userId, { cardId, type: 'chunk', field, chunk: result.newChunk });
        sentUpTo[field] += result.newChunk.length;
      }

      if (result.complete) {
        fieldsDone[field] = true;
        const value = result.value.trim() || null;
        feedStore.updateAiField(userId, cardId, field, value);
        emitSSE(userId, { cardId, type: 'field-complete', field, value });
      }
    }
  }

  // Finalize fields whose closing tags were missing (model truncation safety)
  for (const field of ['quote', 'summary']) {
    if (fieldsDone[field]) continue;
    const open     = `<${field}>`;
    const startIdx = accum.indexOf(open);
    const value    = startIdx !== -1 ? accum.slice(startIdx + open.length).trim() || null : null;
    feedStore.updateAiField(userId, cardId, field, value);
    emitSSE(userId, { cardId, type: 'field-complete', field, value });
  }
}

/**
 * Stream decideActionSurface output for one card.
 * Runs after streamInterpretEmail to enforce deterministic reveal order.
 */
async function streamDecideActionSurface(email, cardId, userId) {
  const prompt = renderPrompt(PROMPTS.decideActionSurface, {
    senderName:         email.sender.name,
    senderEmail:        email.sender.email,
    senderDomain:       email.sender.domain,
    subject:            email.subject,
    snippet:            email.snippet,
    plainText:          email.body.plainText?.slice(0, 1500) ?? '',
    htmlText:           email.body.htmlText?.slice(0, 1500) ?? '',
    links:              cleanLinks(email.signals.structuredLinks ?? [])
                          .map(l => l.context
                            ? `${l.text} | context: ${l.context} | url: ${l.url}`
                            : `${l.text} | url: ${l.url}`)
                          .join('\n') || '(none)',
    unsubscribePresent: email.signals.unsubscribePresent,
    hasAttachments:     email.signals.hasAttachments,
  });

  const stream = await openai.responses.create({
    model:  'gpt-5',
    input:  prompt,
    stream: true,
  });

  let accum        = '';
  const sentUpTo   = { action: 0, actionUrl: 0, requiresAttention: 0 };
  const fieldsDone = { action: false, actionUrl: false, requiresAttention: false };

  for await (const event of stream) {
    if (event.type !== 'response.output_text.delta') continue;
    accum += event.delta;

    for (const field of ['action', 'actionUrl', 'requiresAttention']) {
      if (fieldsDone[field]) continue;
      const result = extractStreamingField(accum, field, sentUpTo[field]);
      if (!result) continue;

      if (result.newChunk) {
        emitSSE(userId, { cardId, type: 'chunk', field, chunk: result.newChunk });
        sentUpTo[field] += result.newChunk.length;
      }

      if (result.complete) {
        fieldsDone[field] = true;
        let value;
        if (field === 'requiresAttention') {
          value = result.value.trim().toLowerCase() === 'true';
        } else {
          value = result.value.trim() || null;
        }
        feedStore.updateAiField(userId, cardId, field, value);
        emitSSE(userId, { cardId, type: 'field-complete', field, value });
      }
    }
  }

  // Finalize fields whose closing tags were missing
  for (const field of ['action', 'actionUrl', 'requiresAttention']) {
    if (fieldsDone[field]) continue;
    const open     = `<${field}>`;
    const startIdx = accum.indexOf(open);
    let value;
    if (startIdx !== -1) {
      const raw = accum.slice(startIdx + open.length).trim();
      value = field === 'requiresAttention' ? raw.toLowerCase() === 'true' : raw || null;
    } else {
      value = field === 'requiresAttention' ? false : null;
    }
    feedStore.updateAiField(userId, cardId, field, value);
    emitSSE(userId, { cardId, type: 'field-complete', field, value });
  }
}

// ─── Non-streaming AI helpers (for /interpret-single) ────────────────────
//
// These parse the XML-tagged output synchronously, keeping the existing
// /interpret-single endpoint functional for the legacy runSync flow.

async function interpretEmail(email) {
  const prompt = renderPrompt(PROMPTS.interpretEmail, {
    senderName:             email.sender.name,
    senderEmail:            email.sender.email,
    senderDomain:           email.sender.domain,
    subject:                email.subject,
    snippet:                email.snippet,
    plainText:              email.body.plainText?.slice(0, 1500) ?? '',
    htmlText:               email.body.htmlText?.slice(0, 1500) ?? '',
    links:                  cleanLinks(email.signals.structuredLinks ?? []).length,
    unsubscribePresent:     email.signals.unsubscribePresent,
    freeMailDomain:         email.signals.freeMailDomain,
    replyToMismatch:        email.signals.replyToMismatch,
    suspiciousSubjectHints: JSON.stringify(email.signals.suspiciousSubjectHints),
    greetingGeneric:        email.signals.greetingGeneric,
    hasAttachments:         email.signals.hasAttachments,
  });

  const response = await openai.responses.create({ model: 'gpt-5', input: prompt });
  const text = response.output_text;
  return {
    quote:   parseXmlField(text, 'quote') || null,
    summary: parseXmlField(text, 'summary') ?? 'Unable to summarize email.',
  };
}

async function decideActionSurface(email) {
  const prompt = renderPrompt(PROMPTS.decideActionSurface, {
    senderName:         email.sender.name,
    senderEmail:        email.sender.email,
    senderDomain:       email.sender.domain,
    subject:            email.subject,
    snippet:            email.snippet,
    plainText:          email.body.plainText?.slice(0, 1500) ?? '',
    htmlText:           email.body.htmlText?.slice(0, 1500) ?? '',
    links:              cleanLinks(email.signals.structuredLinks ?? [])
                          .map(l => l.context
                            ? `${l.text} | context: ${l.context} | url: ${l.url}`
                            : `${l.text} | url: ${l.url}`)
                          .join('\n') || '(none)',
    unsubscribePresent: email.signals.unsubscribePresent,
    hasAttachments:     email.signals.hasAttachments,
  });

  const response = await openai.responses.create({ model: 'gpt-5', input: prompt });
  const text     = response.output_text;
  const requiresAttentionStr = parseXmlField(text, 'requiresAttention') ?? 'false';
  return {
    action:             parseXmlField(text, 'action') || null,
    actionUrl:          parseXmlField(text, 'actionUrl') || null,
    requiresAttention:  requiresAttentionStr.trim().toLowerCase() === 'true',
  };
}

// ─── Auth ─────────────────────────────────────────────────────────────────

async function resolveUserId(req) {
  const auth  = req.headers['authorization'] ?? '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!token) return null;
  try {
    const r = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!r.ok) return null;
    const { sub } = await r.json();
    return sub ?? null;
  } catch {
    return null;
  }
}

// ─── Routes ───────────────────────────────────────────────────────────────

app.post('/interpret-single', async (req, res) => {
  const email = req.body.email;
  if (!email) return res.status(400).json({ error: 'email required' });
  console.log(`[interpret-single] processing ${email.id} "${email.subject}"`);

  let quote   = '';
  let summary = 'Unable to summarize email.';
  let action  = null;
  let actionUrl = null;
  let requiresAttention = false;

  const [interpretResult, actionResult] = await Promise.allSettled([
    interpretEmail(email),
    decideActionSurface(email),
  ]);

  if (interpretResult.status === 'fulfilled') {
    quote   = interpretResult.value.quote   ?? '';
    summary = interpretResult.value.summary ?? 'Unable to summarize email.';
  } else {
    console.error(`[interpret-single] interpretEmail failed for ${email.id}:`, interpretResult.reason?.message);
  }

  if (actionResult.status === 'fulfilled') {
    action            = actionResult.value.action            ?? null;
    actionUrl         = actionResult.value.actionUrl         ?? null;
    requiresAttention = actionResult.value.requiresAttention === true;
  } else {
    console.error(`[interpret-single] decideActionSurface failed for ${email.id}:`, actionResult.reason?.message);
  }

  const card = {
    id: email.id,
    senderName: email.sender.name,
    senderEmail: email.sender.email,
    subject: email.subject,
    date: email.date,
    threadId: email.threadId,
    avatarUri: resolveAvatarUri(email),
    avatarFallbackText: resolveAvatarFallbackText(email),
    quote,
    summary,
    action,
    actionUrl,
    requiresAttention,
  };

  console.log(`[interpret-single] done ${email.id}`);
  res.json({ card });
});

app.post('/session-recap', async (req, res) => {
  const { cards, userName, timeOfDay } = req.body;
  if (!Array.isArray(cards)) return res.status(400).json({ error: 'cards required' });

  const totalInView    = cards.length;
  const attentionCards = cards.filter(c => c.requiresAttention === true);
  const requireAttention = attentionCards.length;

  const formatCards = (arr) =>
    arr.map(c =>
      `- From: ${c.senderName} | Subject: ${c.subject} | Summary: ${c.summary}${c.action ? ` | Action: ${c.action}` : ''}`
    ).join('\n') || '(none)';

  const prompt = renderPrompt(PROMPTS.sessionRecap, {
    timeOfDay:    timeOfDay ?? 'morning',
    userName:     userName  ?? '',
    totalInView,
    requireAttention,
    attentionCards: formatCards(attentionCards),
    contextCards:   formatCards(cards),
  });

  try {
    const response = await openai.responses.create({ model: 'gpt-5', input: prompt });
    const recap    = JSON.parse(response.output_text);
    recap.totalInView    = totalInView;
    recap.requireAttention = requireAttention;
    res.json({ recap });
  } catch (err) {
    console.error('[session-recap] failed:', err.message);
    res.status(500).json({ error: 'recap failed' });
  }
});

// ─── Feed ─────────────────────────────────────────────────────────────────

app.get('/feed', async (req, res) => {
  const userId = await resolveUserId(req);
  if (!userId) return res.status(401).json({ error: 'unauthorized' });
  res.json(feedStore.getFeed(userId));
});

// ─── SSE endpoint ─────────────────────────────────────────────────────────
//
// Clients connect once and receive real-time card events:
//   { cardId, type: 'pending', ...staticFields }  — new card added
//   { cardId, type: 'chunk',  field, chunk }       — streaming token for a field
//   { cardId, type: 'field-complete', field, value } — field fully resolved
//   { cardId, type: 'ready' }                      — all AI fields done

app.get('/feed/events', async (req, res) => {
  const userId = await resolveUserId(req);
  if (!userId) return res.status(401).end();

  res.setHeader('Content-Type',  'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection',    'keep-alive');
  res.flushHeaders();

  getSseClients(userId).add(res);
  console.log(`[sse] client connected (user: ${userId.slice(0, 8)}…) total: ${getSseClients(userId).size}`);

  req.on('close', () => {
    getSseClients(userId).delete(res);
    console.log(`[sse] client disconnected (user: ${userId.slice(0, 8)}…) remaining: ${getSseClients(userId).size}`);
  });
});

// ─── Dev ingestion bridge ──────────────────────────────────────────────────
//
// DEV ONLY. Accepts a cleaned email object and runs it through the full
// streaming pipeline: addPending (SSE → client shows static card immediately),
// then serial AI processing (SSE → client fields stream in as tokens arrive).
//
// Production ingestion path (Step 2): Gmail Pub/Sub push → POST /pubsub-push

app.post('/dev/ingest', async (req, res) => {
  const userId = await resolveUserId(req);
  if (!userId) return res.status(401).json({ error: 'unauthorized' });

  const { email } = req.body;
  if (!email) return res.status(400).json({ error: 'email required' });

  const id = `dev-${Date.now()}`;

  const staticFields = {
    emailDate:          email.date,
    emailId:            email.id,
    senderName:         email.sender.name,
    senderEmail:        email.sender.email,
    subject:            email.subject,
    date:               email.date ?? String(Date.now()),
    threadId:           email.threadId ?? null,
    threadMessageCount: 1,
    avatarUri:          resolveAvatarUri(email),
    avatarFallbackText: resolveAvatarFallbackText(email),
  };

  feedStore.addPending(userId, id, staticFields);

  // Notify SSE clients: card exists with static fields — show partial card immediately
  emitSSE(userId, { cardId: id, type: 'pending', ...staticFields });

  console.log(`[dev/ingest] pending → ${id} (user: ${userId.slice(0, 8)}…)`);

  // Respond immediately — client has everything it needs to show the card
  res.json({ id, status: 'pending' });

  // Enqueue AI processing — serial per user, so only one card streams at a time
  enqueueProcessing(userId, async () => {
    try {
      // interpretEmail first → quote + summary stream in
      await streamInterpretEmail(email, id, userId);
      // decideActionSurface second → action fields stream in after quote/summary
      await streamDecideActionSurface(email, id, userId);

      feedStore.markReady(userId, id);
      emitSSE(userId, { cardId: id, type: 'ready' });
      console.log(`[dev/ingest] ready   → ${id}`);

      // Update the session recap from all current ready cards
      // TODO (Step 2): extract buildRecap() to avoid this HTTP self-call
      const { cards: currentCards } = feedStore.getFeed(userId);
      const readyCards = currentCards.filter(c => c.status === 'ready');
      if (readyCards.length > 0) {
        try {
          const recapRes = await fetch(`http://localhost:${PORT}/session-recap`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              cards: readyCards.map(c => ({
                senderName:         c.senderName,
                subject:            c.subject,
                summary:            c.summary,
                action:             c.action,
                requiresAttention:  c.requiresAttention,
              })),
              userName:  '',
              timeOfDay: (() => { const h = new Date().getHours(); return h < 12 ? 'morning' : h < 17 ? 'afternoon' : 'evening'; })(),
            }),
          });
          const { recap } = await recapRes.json();
          feedStore.setRecap(userId, recap);
        } catch (err) {
          console.warn('[dev/ingest] recap update failed:', err.message);
        }
      }
    } catch (err) {
      console.error(`[dev/ingest] AI processing failed for ${id}:`, err.message);
    }
  });
});

app.get('/test-ai', async (req, res) => {
  try {
    const response = await openai.responses.create({
      model: 'gpt-5',
      input: 'Say "AI is working"',
    });
    res.json({ success: true, output: response.output_text });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
