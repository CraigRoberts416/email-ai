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

// Priority: person photo (not yet wired) → company logo → null
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

// ─── AI helper ────────────────────────────────────────────────────────────

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

  const response = await openai.responses.create({
    model: 'gpt-5',
    input: prompt,
  });

  return JSON.parse(response.output_text);
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

  const response = await openai.responses.create({
    model: 'gpt-5',
    input: prompt,
  });

  return JSON.parse(response.output_text);
}

// ─── Auth ─────────────────────────────────────────────────────────────────
// Validates the Google access token sent by the client and returns a stable
// userId (the Google `sub` claim). One userinfo call per request — acceptable
// for Step 1. Add server-side token caching in Step 2.

async function resolveUserId(req) {
  const auth = req.headers['authorization'] ?? '';
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

  let quote = '';
  let summary = 'Unable to summarize email.';
  let action = null;
  let actionUrl = null;
  let requiresAttention = false;

  const [interpretResult, actionResult] = await Promise.allSettled([
    interpretEmail(email),
    decideActionSurface(email),
  ]);

  if (interpretResult.status === 'fulfilled') {
    quote = interpretResult.value.quote ?? '';
    summary = interpretResult.value.summary ?? 'Unable to summarize email.';
  } else {
    console.error(`[interpret-single] interpretEmail failed for ${email.id}:`, interpretResult.reason?.message);
  }

  if (actionResult.status === 'fulfilled') {
    action = actionResult.value.action ?? null;
    actionUrl = actionResult.value.actionUrl ?? null;
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

  // Single source: all three values derived from the same cards array
  const totalInView = cards.length;
  const attentionCards = cards.filter(c => c.requiresAttention === true);
  const requireAttention = attentionCards.length;

  const formatCards = (arr) =>
    arr.map(c =>
      `- From: ${c.senderName} | Subject: ${c.subject} | Summary: ${c.summary}${c.action ? ` | Action: ${c.action}` : ''}`
    ).join('\n') || '(none)';

  const prompt = renderPrompt(PROMPTS.sessionRecap, {
    timeOfDay: timeOfDay ?? 'morning',
    userName: userName ?? '',
    totalInView,
    requireAttention,
    attentionCards: formatCards(attentionCards),
    contextCards: formatCards(cards),
  });

  try {
    const response = await openai.responses.create({ model: 'gpt-5', input: prompt });
    const recap = JSON.parse(response.output_text);
    recap.totalInView = totalInView;
    recap.requireAttention = requireAttention;
    res.json({ recap });
  } catch (err) {
    console.error('[session-recap] failed:', err.message);
    res.status(500).json({ error: 'recap failed' });
  }
});

// ─── Feed ─────────────────────────────────────────────────────────────────
//
// SLICE: Step 1 — Render-backed, user-scoped feed.
// Returns all cards for the user (pending + ready) plus their session recap.
// Seen-state filtering (unseen-only feed) is not yet implemented — Step 3.

app.get('/feed', async (req, res) => {
  const userId = await resolveUserId(req);
  if (!userId) return res.status(401).json({ error: 'unauthorized' });
  res.json(feedStore.getFeed(userId));
});

// ─── Dev ingestion bridge ──────────────────────────────────────────────────
//
// DEV ONLY. This endpoint exists solely to test the skeleton → ready flow
// against the real Render backend without needing Gmail Pub/Sub wired up.
//
// Usage (curl):
//   curl -X POST https://email-ai-server.onrender.com/dev/ingest \
//     -H "Authorization: Bearer <google_access_token>" \
//     -H "Content-Type: application/json" \
//     -d '{"email": { <cleaned email object> }}'
//
// Production ingestion path (Step 2): Gmail Pub/Sub push → POST /pubsub-push
// This endpoint should be removed or gated behind NODE_ENV before launch.
//
// TODO (Step 2): Extract buildRecap() as a direct function so this no longer
// calls /session-recap over HTTP. The self-call below is a temporary bridge.

app.post('/dev/ingest', async (req, res) => {
  const userId = await resolveUserId(req);
  if (!userId) return res.status(401).json({ error: 'unauthorized' });

  const { email } = req.body;
  if (!email) return res.status(400).json({ error: 'email required' });

  const id = `dev-${Date.now()}`;
  feedStore.addPending(userId, id);
  console.log(`[dev/ingest] pending → ${id} (user: ${userId.slice(0, 8)}…)`);

  // Respond immediately — card is now visible as a skeleton on the client
  res.json({ id, status: 'pending' });

  // Async: run real AI processing, then resolve the card
  (async () => {
    try {
      const [interpretResult, actionResult] = await Promise.allSettled([
        interpretEmail(email),
        decideActionSurface(email),
      ]);

      const quote   = interpretResult.status === 'fulfilled' ? (interpretResult.value.quote   ?? '') : '';
      const summary = interpretResult.status === 'fulfilled' ? (interpretResult.value.summary ?? '') : '';
      const action          = actionResult.status === 'fulfilled' ? (actionResult.value.action          ?? null)  : null;
      const actionUrl       = actionResult.status === 'fulfilled' ? (actionResult.value.actionUrl       ?? null)  : null;
      const requiresAttention = actionResult.status === 'fulfilled' ? (actionResult.value.requiresAttention === true) : false;

      const card = {
        id,
        senderName:         email.sender.name,
        senderEmail:        email.sender.email,
        subject:            email.subject,
        date:               email.date ?? String(Date.now()),
        threadId:           email.threadId ?? null,
        threadMessageCount: 1,
        avatarUri:          resolveAvatarUri(email),
        avatarFallbackText: resolveAvatarFallbackText(email),
        quote,
        summary,
        action,
        actionUrl,
        requiresAttention,
      };

      feedStore.markReady(userId, id, card);
      console.log(`[dev/ingest] ready   → ${id}`);

      // Update the user's recap from their current ready cards.
      // TODO (Step 2): replace this HTTP self-call with a direct buildRecap() function.
      const { cards: currentCards } = feedStore.getFeed(userId);
      const readyCards = currentCards.filter(c => c.status === 'ready' && c.data);
      if (readyCards.length > 0) {
        try {
          const recapRes = await fetch(`http://localhost:${PORT}/session-recap`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              cards: readyCards.map(c => ({
                senderName: c.data.senderName,
                subject:    c.data.subject,
                summary:    c.data.summary,
                action:     c.data.action,
                requiresAttention: c.data.requiresAttention,
              })),
              userName:   '',
              timeOfDay:  (() => { const h = new Date().getHours(); return h < 12 ? 'morning' : h < 17 ? 'afternoon' : 'evening'; })(),
            }),
          });
          const { recap } = await recapRes.json();
          feedStore.setRecap(userId, recap);
        } catch (err) {
          console.warn('[dev/ingest] recap update failed:', err.message);
        }
      }
    } catch (err) {
      console.error('[dev/ingest] AI processing failed:', err.message);
    }
  })();
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
  // Mock ingestion removed. Ingestion is now triggered via POST /dev/ingest
  // during this transition slice, and will be replaced by Gmail Pub/Sub in Step 2.
});
