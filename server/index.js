require('dotenv').config();

require('dd-trace').init({
  llmobs: {
    mlApp: process.env.DD_LLMOBS_ML_APP,
    agentlessEnabled: true,
  },
  site: process.env.DD_SITE,
  env: process.env.DD_ENV || 'dev',
});

const fs      = require('fs');
const path    = require('path');
const { spawn } = require('child_process');
const express = require('express');
const cors    = require('cors');
const OpenAI  = require('openai');

process.env.PLAYWRIGHT_BROWSERS_PATH = process.env.PLAYWRIGHT_BROWSERS_PATH || path.join(__dirname, '.playwright-browsers');

const userStore        = require('./userStore');
const messageStore     = require('./messageStore');
const gmailSync        = require('./gmailSync');
const processingWorker = require('./processingWorker');
const watchManager     = require('./watchManager');
const heroImage        = require('./heroImageGenerator');
const emailImage       = require('./emailImage');
const crypto           = require('crypto');
const { runUnsubscribeAgent } = require('./unsubscribeAgent');
const unsubscribeCopy  = require('./unsubscribeCopy');
const { cleanEmailForAI } = require('./emailCleaner');

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

const { Expo } = require('expo-server-sdk');
const expo = new Expo();

async function sendSilentPush(pushToken) {
  if (!pushToken || !Expo.isExpoPushToken(pushToken)) return;
  try {
    await expo.sendPushNotificationsAsync([{
      to:               pushToken,
      _contentAvailable: true,
      data:             { type: 'new-mail' },
      priority:         'high',
    }]);
  } catch (err) {
    console.warn('[push] send failed:', err.message);
  }
}

const app = express();

// Render terminates TLS at its edge and forwards plain HTTP, so `req.protocol`
// reads "http" and every absolute URL this server builds came out as an http://
// link. iOS App Transport Security refuses those outright — which is why not a
// single hero image ever loaded: each one failed with -1022 before a byte was
// fetched, silently, inside an AsyncImage that has nowhere to report it. The
// picture was generated, stored, resized and then blocked by the scheme.
app.set('trust proxy', true);
app.use(cors());
app.use(express.json({ limit: '10mb' }));

// ─── Text safety ──────────────────────────────────────────────────────────

// Gmail truncates snippets by UTF-16 code unit, which cuts emoji in half and
// leaves an unpaired surrogate. JSON.stringify happily emits it as \uD83D,
// and every strict decoder — including Swift's — rejects the whole payload.
// Two such messages were dropping two cards from every feed response.
function stripLoneSurrogates(value) {
  if (typeof value === 'string') {
    return value
      .replace(/[\uD800-\uDBFF](?![\uDC00-\uDFFF])/g, '')
      .replace(/(^|[^\uD800-\uDBFF])[\uDC00-\uDFFF]/g, '$1');
  }
  if (Array.isArray(value)) return value.map(stripLoneSurrogates);
  if (value && typeof value === 'object') {
    const out = {};
    for (const [key, item] of Object.entries(value)) out[key] = stripLoneSurrogates(item);
    return out;
  }
  return value;
}

// ─── HTML entity decoder ──────────────────────────────────────────────────

function decodeHtmlEntities(text) {
  return text
    .replace(/&nbsp;/gi, ' ').replace(/&amp;/gi, '&').replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>').replace(/&quot;/gi, '"').replace(/&#39;/gi, "'")
    .replace(/\s+/g, ' ').trim();
}

// ─── Sender parser ────────────────────────────────────────────────────────

function parseSenderServer(from) {
  const match  = from.match(/^(.*?)\s*<([^>]+)>$/);
  const email  = match ? match[2].trim() : from.trim();
  const name   = match ? match[1].replace(/^"|"$/g, '').trim() : email;
  const domain = email.split('@')[1] ?? '';
  return { name, email, domain };
}

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

const TONE = fs.readFileSync(path.join(__dirname, 'prompts', 'tone.md'), 'utf8');

function renderPrompt(template, vars) {
  return Object.entries({ tone: TONE, ...vars }).reduce((result, [key, value]) => {
    return result.replace(new RegExp(`\\{\\{${key}\\}\\}`, 'g'), () => String(value));
  }, template);
}

const PROMPTS = {
  interpretEmail:       loadPrompt('interpret-email'),
  decideActionSurface:  loadPrompt('decide-action-surface'),
  sessionRecap:         loadPrompt('session-recap'),
  generateUiCopy:       loadPrompt('generate-ui-copy'),
  discussThread:        loadPrompt('discuss-thread'),
  suggestReply:         loadPrompt('suggest-reply'),
  detectRiskSignals:    loadPrompt('detect-risk-signals'),
};

// ─── XML helpers ──────────────────────────────────────────────────────────

function parseXmlField(text, fieldName) {
  const open  = `<${fieldName}>`;
  const close = `</${fieldName}>`;
  const start = text.indexOf(open);
  if (start === -1) return null;
  const end = text.indexOf(close, start + open.length);
  if (end === -1) return null;
  return text.slice(start + open.length, end).trim();
}

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

  const safeEnd   = Math.max(contentStart, accum.length - (close.length - 1));
  const available = accum.slice(contentStart, safeEnd);
  const newChunk  = available.slice(alreadySent);
  return { newChunk: newChunk || null, complete: false, value: null };
}

// ─── SSE helpers ──────────────────────────────────────────────────────────

const sseClients = new Map(); // userId → Set<res>
const unsubscribeStatuses = new Map(); // userId → Map<messageId, status>
const SSE_KEEPALIVE_MS = 25_000;
const TERMINAL_UNSUBSCRIBE_STATUS_TTL_MS = 30_000;

function getSseClients(userId) {
  if (!sseClients.has(userId)) sseClients.set(userId, new Set());
  return sseClients.get(userId);
}

function getUnsubscribeStatuses(userId) {
  if (!unsubscribeStatuses.has(userId)) unsubscribeStatuses.set(userId, new Map());
  return unsubscribeStatuses.get(userId);
}

function pruneUnsubscribeStatuses(userId) {
  const statuses = getUnsubscribeStatuses(userId);
  const now = Date.now();

  for (const [messageId, status] of statuses) {
    if (unsubscribeCopy.isTerminal(status.step) && now - status.updatedAt > TERMINAL_UNSUBSCRIBE_STATUS_TTL_MS) {
      statuses.delete(messageId);
    }
  }

  if (statuses.size === 0) {
    unsubscribeStatuses.delete(userId);
    // Only once nothing is still running. A run is registered a beat before
    // its first status exists, and dropping the registry in that window would
    // cost it its place in the batch for the rest of its life.
    if (batchIsFinished(unsubscribeRuns.get(userId))) unsubscribeRuns.delete(userId);
  }
  return statuses;
}

// ─── Which sender of the batch ────────────────────────────────────────────
// The client fires one POST per sender, so a "batch" is simply whatever is in
// flight at the same time: `index` is this run's place in that set and `total`
// is its size. The set is dropped once every run in it has resolved, so the
// next unsubscribe starts again at 1 of 1 rather than counting on from this
// morning's sweep.

// userId → { runId, senders: Map<messageId, { index, startedAt, resolved }> }
const unsubscribeRuns = new Map();

function batchIsFinished(batch) {
  return !batch || Array.from(batch.senders.values()).every(sender => sender.resolved);
}

function beginUnsubscribeRun(userId, messageId) {
  let batch = unsubscribeRuns.get(userId);
  if (batchIsFinished(batch)) {
    batch = { runId: `run_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`, senders: new Map() };
    unsubscribeRuns.set(userId, batch);
  }

  const existing = batch.senders.get(messageId);
  if (existing) {
    existing.startedAt = Date.now();
    existing.resolved  = false;
    return existing;
  }

  const sender = { index: batch.senders.size + 1, startedAt: Date.now(), resolved: false };
  batch.senders.set(messageId, sender);
  return sender;
}

function unsubscribeRunContext(userId, messageId) {
  const batch  = unsubscribeRuns.get(userId);
  const sender = batch?.senders.get(messageId);
  if (!sender) return { runId: null, index: 1, total: 1, elapsedMs: 0 };
  return {
    runId:     batch.runId,
    index:     sender.index,
    total:     batch.senders.size,
    elapsedMs: Date.now() - sender.startedAt,
  };
}

function resolveUnsubscribeRun(userId, messageId) {
  const sender = unsubscribeRuns.get(userId)?.senders.get(messageId);
  if (sender) sender.resolved = true;
}

/// A thrown error, sized for the run log's evidence column. It never reaches
/// the tray: a stack-shaped string is the machine talking to itself.
function describeUnsubscribeError(err) {
  const message = String(err?.message ?? '').replace(/\s+/g, ' ').trim();
  if (!message) return 'no detail reported';
  return message.length <= 160 ? message : `${message.slice(0, 159)}…`;
}

/// The sentence that ships. The model writes it; this decides whether it is
/// allowed to. An empty sentence, or one that claims success before the page
/// was read back, loses to the plain static fallback — `done` is the only
/// state allowed to use the word "unsubscribed", and claiming it early is the
/// one lie that kills this feature.
function unsubscribeMessage(step, message, { senderName, fieldLabel }) {
  const fallback = unsubscribeCopy.fallbackMessage(step, { senderName, fieldLabel });
  const text = String(message ?? '').replace(/\s+/g, ' ').trim();
  if (!text) return fallback;
  if (step !== 'done' && unsubscribeCopy.claimsUnsubscribed(text)) return fallback;
  return text;
}

function emitUnsubscribeStatus(userId, data) {
  // The enum drives the tray's shape, its counter and its progress segments,
  // so it has to be deterministic. Anything that is not a member of the closed
  // set is dropped rather than guessed at — the last honest status stays on
  // screen, which is better than a tray that renders a step nobody defined.
  const step = unsubscribeCopy.sanitizeStep(data.step ?? data.status);
  if (!step) {
    console.warn(`[unsubscribe] dropped status with unknown step: ${JSON.stringify(data.step ?? data.status)}`);
    return;
  }

  const { runId, index, total, elapsedMs } = unsubscribeRunContext(userId, data.messageId);
  if (unsubscribeCopy.isTerminal(step)) resolveUnsubscribeRun(userId, data.messageId);

  // The field counter belongs to FILLING and nowhere else — that is where the
  // counter switches from sites to fields, because that is what is visibly
  // happening.
  const fieldScoped = unsubscribeCopy.counterFor(step) === 'field';

  const payload = {
    // Ties every event of one batch together in the run log.
    runId:      data.runId ?? runId,
    messageId:  data.messageId,
    senderName: data.senderName ?? null,
    // `status` is the key the shipped client decodes; `step` is what the
    // contract calls it. Same value under both, so neither has to be wrong.
    status:     step,
    step,
    message:    unsubscribeMessage(step, data.message, { senderName: data.senderName, fieldLabel: data.fieldLabel }),
    index:      data.index ?? index,
    total:      data.total ?? total,
    fieldIndex: fieldScoped ? (data.fieldIndex ?? null) : null,
    fieldTotal: fieldScoped ? (data.fieldTotal ?? null) : null,
    elapsedMs:  data.elapsedMs ?? elapsedMs,
    // What it saw. Shown in the run log, never in the tray.
    evidence:   data.evidence ?? null,
  };

  const statuses = getUnsubscribeStatuses(userId);
  statuses.set(payload.messageId, { ...payload, updatedAt: Date.now() });
  pruneUnsubscribeStatuses(userId);
  emitSSE(userId, { type: 'unsubscribe-status', ...payload });
}

let playwrightInstallPromise = null;

async function ensurePlaywrightChromium() {
  const { chromium } = require('playwright');
  const executablePath = chromium.executablePath();

  if (fs.existsSync(executablePath)) return;
  if (playwrightInstallPromise) return playwrightInstallPromise;

  const cliPath = path.join(__dirname, 'node_modules', '.bin', 'playwright');
  const env = {
    ...process.env,
    PLAYWRIGHT_BROWSERS_PATH: process.env.PLAYWRIGHT_BROWSERS_PATH,
  };

  playwrightInstallPromise = new Promise((resolve, reject) => {
    console.warn(`[playwright] browser missing at ${executablePath} — installing chromium`);

    const child = spawn(cliPath, ['install', 'chromium'], {
      cwd: __dirname,
      env,
      stdio: 'pipe',
    });

    let stderr = '';
    child.stdout.on('data', chunk => process.stdout.write(chunk));
    child.stderr.on('data', chunk => {
      stderr += chunk.toString();
      process.stderr.write(chunk);
    });

    child.on('error', reject);
    child.on('close', code => {
      if (code === 0 && fs.existsSync(executablePath)) {
        resolve();
      } else {
        reject(new Error(stderr.trim() || `playwright install exited with code ${code}`));
      }
    });
  }).finally(() => {
    playwrightInstallPromise = null;
  });

  return playwrightInstallPromise;
}

function emitSSE(userId, rawData) {
  const data = stripLoneSurrogates(rawData);
  const clients = getSseClients(userId);
  const payload = `data: ${JSON.stringify(data)}\n\n`;
  for (const res of clients) {
    try { res.write(payload); } catch {}
  }
}

// ─── Streaming AI functions ───────────────────────────────────────────────
// These update messageStore incrementally as each field streams in.

async function streamInterpretEmail(email, messageId, userId) {
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

  const stream = await openai.responses.create({ model: 'gpt-5', input: prompt, stream: true });

  let accum        = '';
  const sentUpTo   = { quote: 0, summary: 0 };
  const fieldsDone = { quote: false, summary: false };

  for await (const event of stream) {
    if (event.type !== 'response.output_text.delta') continue;
    accum += event.delta;

    for (const field of ['quote', 'summary']) {
      if (fieldsDone[field]) continue;
      const result = extractStreamingField(accum, field, sentUpTo[field]);
      if (!result) continue;

      if (result.newChunk) {
        emitSSE(userId, { messageId, type: 'chunk', field, chunk: result.newChunk });
        sentUpTo[field] += result.newChunk.length;
      }

      if (result.complete) {
        fieldsDone[field] = true;
        const value = result.value.trim() || null;
        await messageStore.setAiField(userId, messageId, field, value);
        emitSSE(userId, { messageId, type: 'field-complete', field, value });
      }
    }
  }

  for (const field of ['quote', 'summary']) {
    if (fieldsDone[field]) continue;
    const open     = `<${field}>`;
    const startIdx = accum.indexOf(open);
    const value    = startIdx !== -1 ? accum.slice(startIdx + open.length).trim() || null : null;
    await messageStore.setAiField(userId, messageId, field, value);
    emitSSE(userId, { messageId, type: 'field-complete', field, value });
  }
}

async function streamDecideActionSurface(email, messageId, userId) {
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

  const stream = await openai.responses.create({ model: 'gpt-5', input: prompt, stream: true });

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
        emitSSE(userId, { messageId, type: 'chunk', field, chunk: result.newChunk });
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
        await messageStore.setAiField(userId, messageId, field, value);
        emitSSE(userId, { messageId, type: 'field-complete', field, value });
      }
    }
  }

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
    await messageStore.setAiField(userId, messageId, field, value);
    emitSSE(userId, { messageId, type: 'field-complete', field, value });
  }
}

// ─── Risk signals ─────────────────────────────────────────────────────────
// The card prints one kicker — POSSIBLE SCAM — and the explainer screen prints
// the evidence, because a label that only flags teaches nothing while a label
// that shows its working teaches the user to spot the next one themselves.

const RISK_LEVELS = new Set(['none', 'possible_scam']);

// A closed label set, so the explainer's mono column stays a column. A label
// the model made up is dropped with its line.
const RISK_EVIDENCE_LABELS = new Set(['THE DOMAIN', 'THE LINK', 'THE ADDRESS', 'THE DEADLINE', 'THE ASK']);

function parseRiskEvidence(raw) {
  if (!raw) return [];
  const seen = new Set();
  return String(raw)
    .split('\n')
    .map(line => {
      const separator = line.indexOf('::');
      if (separator === -1) return null;
      const label = line.slice(0, separator).trim().toUpperCase();
      const text  = line.slice(separator + 2).replace(/\s+/g, ' ').trim();
      if (!RISK_EVIDENCE_LABELS.has(label) || !text || seen.has(label)) return null;
      seen.add(label);
      return { label, text };
    })
    .filter(Boolean)
    .slice(0, 3);
}

async function detectRiskSignals(email, messageId, userId) {
  const prompt = renderPrompt(PROMPTS.detectRiskSignals, {
    senderName:             email.sender.name,
    senderEmail:            email.sender.email,
    senderDomain:           email.sender.domain,
    replyTo:                email.sender.replyTo ?? '(none)',
    subject:                email.subject,
    snippet:                email.snippet,
    plainText:              email.body.plainText?.slice(0, 1500) ?? '',
    htmlText:               email.body.htmlText?.slice(0, 1500) ?? '',
    // Unlike everywhere else, the links go in unfiltered and with their URLs
    // intact: a mismatch between what a link says and where it goes is the
    // single most checkable piece of evidence there is, and cleanLinks throws
    // exactly that away.
    links:                  (email.signals.structuredLinks ?? [])
                              .slice(0, 25)
                              .map(l => `- "${l.text}" → ${l.url}`)
                              .join('\n') || '(none)',
    freeMailDomain:         email.signals.freeMailDomain,
    replyToMismatch:        email.signals.replyToMismatch,
    suspiciousSubjectHints: JSON.stringify(email.signals.suspiciousSubjectHints),
    greetingGeneric:        email.signals.greetingGeneric,
    unsubscribePresent:     email.signals.unsubscribePresent,
    hasAttachments:         email.signals.hasAttachments,
  });

  let level    = 'none';
  let evidence = [];

  try {
    const response = await openai.responses.create({ model: 'gpt-5', input: prompt });
    const text = response.output_text ?? '';

    const rawLevel = (parseXmlField(text, 'riskLevel') ?? '').trim().toLowerCase().replace(/[^a-z_]/g, '');
    if (RISK_LEVELS.has(rawLevel)) level = rawLevel;

    if (level === 'possible_scam') {
      evidence = parseRiskEvidence(parseXmlField(text, 'riskEvidence'));
      // The verdict does not survive without the evidence. A flag we cannot
      // explain is exactly the false positive on a real bank that the prompt
      // spends half its length trying to prevent.
      if (evidence.length === 0) {
        console.warn(`[risk] ${messageId}: possible_scam with no parseable evidence — downgraded to none`);
        level = 'none';
      }
    }
  } catch (err) {
    // Unsure is not a flag, and neither is offline. A failed call means the
    // card says nothing, never that it says POSSIBLE SCAM.
    console.warn(`[risk] detection failed for ${messageId}: ${err.message}`);
    level    = 'none';
    evidence = [];
  }

  await messageStore.setRiskVerdict(userId, messageId, { level, evidence });
  // The client's field-complete envelope decodes `value` as a string, so the
  // verdict goes over the wire and the evidence rides the card — sending an
  // array here would make the whole event undecodable and the label would
  // simply never arrive.
  emitSSE(userId, { messageId, type: 'field-complete', field: 'riskLevel', value: level });

  return { level, evidence };
}

// ─── Auth ─────────────────────────────────────────────────────────────────

// Cache token → { userId, expiresAt } to avoid hitting Google on every request.
// TTL is 5 minutes — well within OAuth token lifetimes.
const tokenCache = new Map();
const TOKEN_CACHE_TTL = 5 * 60 * 1000;

async function resolveUserId(req) {
  const auth  = req.headers['authorization'] ?? '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!token) return null;

  const cached = tokenCache.get(token);
  if (cached && Date.now() < cached.expiresAt) return cached.userId;

  try {
    const r = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!r.ok) return null;
    const { sub } = await r.json();
    if (!sub) return null;
    tokenCache.set(token, { userId: sub, expiresAt: Date.now() + TOKEN_CACHE_TTL });
    return sub;
  } catch {
    return null;
  }
}

async function resolveUserProfile(req) {
  const auth  = req.headers['authorization'] ?? '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!token) return null;

  try {
    const r = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!r.ok) return null;
    const profile = await r.json();
    return { token, profile };
  } catch {
    return null;
  }
}

// ─── Routes ───────────────────────────────────────────────────────────────

// Register user — stores tokens, starts initial sync + worker + watch
app.post('/auth/register', async (req, res) => {
  const auth        = req.headers['authorization'] ?? '';
  const accessToken = auth.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!accessToken) return res.status(401).json({ error: 'unauthorized' });

  const { refreshToken, expiresAt } = req.body;
  if (!refreshToken) return res.status(400).json({ error: 'refreshToken required' });

  try {
    // Resolve userId and email from Google
    const userinfoRes = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (!userinfoRes.ok) return res.status(401).json({ error: 'invalid token' });
    const { sub: userId, email } = await userinfoRes.json();

    // Check before upsert — presence of onboarding_history_id means this user
    // has already been through first-time bootstrap.
    const existingUser = await userStore.getUser(userId);
    const isNewUser = !existingUser?.onboarding_history_id;

    // Get current Gmail historyId for the onboarding cutoff (only needed for new users,
    // but we fetch it regardless so we always have a fresh historyId to store as onboarding anchor)
    const profileRes = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/profile', {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    const profileJson = await profileRes.json();
    const onboardingHistoryId = profileJson.historyId ?? null;

    // Store user + tokens in DB (upsert preserves existing onboarding_history_id via COALESCE)
    await userStore.upsertUser(userId, {
      email,
      accessToken,
      refreshToken,
      tokenExpiry: expiresAt ?? (Date.now() + 3600_000),
      onboardingHistoryId,
    });

    // Set history_id as incremental sync starting point, only if not already set
    if (onboardingHistoryId) {
      const { query } = require('./db');
      await query(
        'UPDATE users SET history_id = $2 WHERE user_id = $1 AND history_id IS NULL',
        [userId, onboardingHistoryId]
      );
    }

    if (isNewUser) {
      // First-time bootstrap: pull backlog and register Gmail push watch.
      // These must only run once — subsequent opens attach to the existing state.
      console.log(`[register] new user ${userId.slice(0, 8)}… — running full bootstrap, historyId: ${onboardingHistoryId}`);
      gmailSync.initialSync(userId).catch(err =>
        console.error('[register] initialSync error:', err.message)
      );
      watchManager.registerWatch(userId).catch(err =>
        console.warn('[register] watch registration error:', err.message)
      );
    } else {
      console.log(`[register] returning user ${userId.slice(0, 8)}… — tokens updated, catching up on missed mail`);
      // Catch up before returning so All Mail reflects the current mailbox
      // when the app loads after downtime or an expired history cursor.
      let newUnreadIds = [];
      try {
        ({ newUnreadIds } = await gmailSync.incrementalSync(userId));
      } catch (syncErr) {
        console.error('[register] incrementalSync error:', syncErr.message);
      }

      if (newUnreadIds.length > 0) {
        const records = await Promise.all(newUnreadIds.map(messageId => messageStore.getMessage(userId, messageId)));
        for (const record of records) {
          if (!record) continue;
          emitSSE(userId, {
            type:               'message-added',
            messageId:          record.messageId,
            threadId:           record.threadId,
            labelIds:           record.labelIds,
            subject:            record.subject,
            fromName:           record.fromName,
            fromEmail:          record.fromEmail,
            snippet:            record.snippet,
            internalDate:       record.internalDate,
            postCutoff:         record.postCutoff,
            aiStatus:           record.aiStatus,
            avatarUri:          resolveAvatarUri({ sender: { domain: record.fromEmail.split('@')[1] ?? '' } }),
            avatarFallbackText: (record.fromName || record.fromEmail || '?').charAt(0).toUpperCase(),
          });
        }
        processingWorker.wakeWorker(userId);
      }

      // Re-register watch if it has expired or is about to.
      watchManager.renewAllExpiring().catch(err =>
        console.warn('[register] watch renewal error:', err.message)
      );
    }

    // Always ensure the worker is running. startWorker is a no-op if the worker
    // is already active for this user (guarded by the in-memory activeWorkers Map).
    processingWorker.startWorker(userId);

    res.json({ success: true, userId });
  } catch (err) {
    console.error('[register] error:', err.message);
    res.status(500).json({ error: 'registration failed' });
  }
});

// Store push token for a user
app.post('/auth/push-token', async (req, res) => {
  const userId = await resolveUserId(req);
  if (!userId) return res.status(401).json({ error: 'unauthorized' });
  const { pushToken } = req.body;
  if (!pushToken) return res.status(400).json({ error: 'pushToken required' });
  try {
    await userStore.updatePushToken(userId, pushToken);
    res.json({ success: true });
  } catch (err) {
    console.error('[push-token] error:', err.message);
    res.status(500).json({ error: 'failed to store push token' });
  }
});

// Mail Feed — unread messages, prioritized
app.get('/feed', async (req, res) => {
  const userId = await resolveUserId(req);
  if (!userId) return res.status(401).json({ error: 'unauthorized' });

  try {
    const messages = await messageStore.getUnread(userId);

    // Collect unique sender domains and look up cached hero assets in parallel.
    // Missing ones trigger fire-and-forget generation so the next /feed response
    // (or a pull-to-refresh) will return the image once ready.
    const domainToSender = new Map();
    for (const m of messages) {
      const domain = (m.fromEmail.split('@')[1] ?? '').toLowerCase();
      if (!domain) continue;
      if (!domainToSender.has(domain)) domainToSender.set(domain, m.fromName || domain);
    }

    const heroByDomain = new Map();
    await Promise.all(Array.from(domainToSender.keys()).map(async domain => {
      // Decoration must never be load-bearing. A missing image, a cold cache,
      // or an absent table costs this sender its picture and nothing else —
      // the mail underneath already exists and is not the AI's to withhold.
      try {
        const senderName = domainToSender.get(domain);
        const cached = await heroImage.getCachedAsset(domain);
        if (cached) {
          heroByDomain.set(domain, cached);
        } else {
          heroImage.ensureHeroAsset(openai, domain, senderName);
        }
      } catch (err) {
        console.warn(`[hero] skipped ${domain}: ${err.message}`);
      }
    }));

    const cards = messages.map(m => {
      const domain = (m.fromEmail.split('@')[1] ?? '').toLowerCase();
      const cached = heroByDomain.get(domain) ?? null;
      return {
        ...m,
        avatarUri:          resolveAvatarUri({ sender: { domain } }),
        avatarFallbackText: (m.fromName || m.fromEmail || '?').charAt(0).toUpperCase(),
        unsubscribeUrl:     m.unsubscribeUrl ?? null,
        // The card prints the verdict; the explainer screen prints the
        // evidence. Both travel together so tapping through never has to
        // wait on a second request to answer "why".
        riskLevel:          m.riskLevel ?? 'none',
        riskEvidence:       m.riskEvidence ?? [],
        heroImageUrl:       cached ? heroImage.buildHeroImageUrl(req, domain) : null,
        heroImageBgColor:   cached?.bgColor ?? null,
        // The message's own picture, proxied. Present only when the email
        // actually carried one worth showing — the card falls back to the
        // sender's hero rather than inventing something.
        imageUrl:           m.imageUrl ? emailImage.buildImageUrl(req.get('host'), userId, m.messageId) : null,
      };
    });

    res.json(stripLoneSurrogates({ cards }));
  } catch (err) {
    console.error('[feed] error:', err.message);
    res.status(500).json({ error: 'feed failed' });
  }
});

// Message body — returns the full email body (plain text + raw HTML).
// Used by the detail screen to render the actual message, not just the snippet.
app.get('/messages/:messageId/body', async (req, res) => {
  const userId = await resolveUserId(req);
  if (!userId) return res.status(401).json({ error: 'unauthorized' });

  const { messageId } = req.params;
  try {
    const rawMsg = await gmailSync.fetchFullMessage(userId, messageId);

    // Extract plain text + raw HTML directly so the client can choose how to
    // render. cleanEmailForAI strips all tags and collapses whitespace, which
    // is useful for AI but destroys paragraph breaks for display.
    function decodeBody(data) {
      if (!data) return '';
      return Buffer.from(data.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8');
    }
    function extractBody(payload, mimeType) {
      if (!payload) return '';
      if (payload.mimeType === mimeType && payload.body?.data) return decodeBody(payload.body.data);
      for (const part of payload.parts ?? []) {
        const result = extractBody(part, mimeType);
        if (result) return result;
      }
      return '';
    }

    const plainText = extractBody(rawMsg.payload, 'text/plain');
    const htmlRaw   = extractBody(rawMsg.payload, 'text/html');

    res.json({ plainText, htmlRaw });
  } catch (err) {
    console.error('[message-body] error:', err.message);
    res.status(500).json({ error: 'failed to load message body' });
  }
});

// The email's own picture, fetched by us and never by the reader.
//
// This is the whole reason the feed can show what a message is actually about.
// Pointing an <img> at the sender's CDN would hand them a timestamped read
// receipt for every post scrolled past — strictly worse than opening the mail,
// which this product already refuses to leak. Here the sender sees one request
// from a server, with no user agent, no cookie, and no relationship to when
// anyone looked.
//
// The message id is the capability: you have to already be able to see the
// message to name it, and the URL is only ever handed out to its owner.
const emailImageCache = new Map();
const EMAIL_IMAGE_WIDTH = 900;
const EMAIL_IMAGE_MAX_BYTES = 12 * 1024 * 1024;

app.get('/messages/:messageId/image', async (req, res) => {
  const { messageId } = req.params;
  const token = typeof req.query.t === 'string' ? req.query.t : '';

  try {
    // Either proof works: a signed URL (what the feed hands out) or a Bearer
    // token (what an API client would send).
    let userId = await resolveUserId(req);
    if (!userId && token) {
      const owners = await messageStore.getMessageOwners(messageId);
      userId = owners.find(id => {
        const expected = emailImage.signImage(id, messageId);
        return expected.length === token.length &&
          crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(token));
      }) ?? null;
    }
    if (!userId) return res.status(401).end();

    const key = `${userId}:${messageId}`;
    if (emailImageCache.has(key)) {
      const hit = emailImageCache.get(key);
      res.setHeader('Content-Type', hit.mime);
      res.setHeader('Cache-Control', 'private, max-age=604800, immutable');
      return res.send(hit.bytes);
    }

    const record = await messageStore.getMessage(userId, messageId);
    if (!record?.imageUrl) return res.status(404).end();

    const upstream = await fetch(record.imageUrl, {
      redirect: 'follow',
      signal: AbortSignal.timeout(8000),
      // No cookies, no referrer, nothing that identifies a person.
      headers: { 'User-Agent': 'DecisionInbox/1.0 (+image-proxy)' },
    });
    if (!upstream.ok) return res.status(404).end();

    const type = upstream.headers.get('content-type') ?? '';
    if (!type.startsWith('image/')) return res.status(415).end();

    const raw = Buffer.from(await upstream.arrayBuffer());
    if (raw.length > EMAIL_IMAGE_MAX_BYTES) return res.status(413).end();

    let bytes = raw;
    let mime = type;
    try {
      const sharp = require('sharp');
      bytes = await sharp(raw)
        .resize(EMAIL_IMAGE_WIDTH, null, { withoutEnlargement: true })
        .webp({ quality: 80 })
        .toBuffer();
      mime = 'image/webp';
    } catch (err) {
      // An animated GIF or an SVG we cannot re-encode still deserves to show.
      console.warn(`[email-image] resize failed for ${messageId}: ${err.message}`);
    }

    emailImageCache.set(key, { bytes, mime });
    res.setHeader('Content-Type', mime);
    res.setHeader('Cache-Control', 'private, max-age=604800, immutable');
    res.send(bytes);
  } catch (err) {
    // A picture is decoration. It must never be able to fail a request the
    // reader made for their mail.
    console.warn('[email-image] error:', err.message);
    res.status(404).end();
  }
});

// Hero image — streams cached per-domain image bytes from DB
// Hero images are generated at full size and stored that way, which is right
// for the archive and wrong for the wire: they run 1.6-2.9 MB as PNG. A phone
// asked for one and got a multi-megabyte download, so the thread showed the
// extracted colour and never the picture — on cellular it would never arrive
// at all. Resized and re-encoded on the way out, cached in memory because the
// source never changes.
const heroVariants = new Map();
const HERO_WIDTH = 900;

app.get('/hero-image/:domain', async (req, res) => {
  try {
    const { domain } = req.params;
    if (heroVariants.has(domain)) {
      const hit = heroVariants.get(domain);
      res.setHeader('Content-Type', hit.mime);
      res.setHeader('Cache-Control', 'public, max-age=604800, immutable');
      return res.send(hit.bytes);
    }

    const asset = await heroImage.getCachedImageBytes(domain);
    if (!asset) return res.status(404).end();

    let bytes = asset.bytes;
    let mime = asset.mime || 'image/png';
    try {
      const sharp = require('sharp');
      bytes = await sharp(asset.bytes)
        .resize(HERO_WIDTH, null, { withoutEnlargement: true })
        .webp({ quality: 82 })
        .toBuffer();
      mime = 'image/webp';
    } catch (err) {
      // A failed re-encode costs bandwidth, not the image. Serve the original.
      console.warn(`[hero-image] resize failed for ${domain}: ${err.message}`);
    }

    heroVariants.set(domain, { bytes, mime });
    res.setHeader('Content-Type', mime);
    res.setHeader('Cache-Control', 'public, max-age=604800, immutable');
    res.send(bytes);
  } catch (err) {
    console.error('[hero-image] error:', err.message);
    res.status(500).end();
  }
});

// SSE endpoint
app.get('/feed/events', async (req, res) => {
  const userId = await resolveUserId(req);
  if (!userId) return res.status(401).end();

  res.setHeader('Content-Type',  'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection',    'keep-alive');
  res.flushHeaders();
  res.write(': connected\n\n');

  getSseClients(userId).add(res);
  console.log(`[sse] connected (user: ${userId.slice(0, 8)}…) total: ${getSseClients(userId).size}`);

  for (const status of pruneUnsubscribeStatuses(userId).values()) {
    try {
      res.write(`data: ${JSON.stringify({ type: 'unsubscribe-status', ...status })}\n\n`);
    } catch {}
  }

  const heartbeat = setInterval(() => {
    try { res.write(': keepalive\n\n'); } catch {}
  }, SSE_KEEPALIVE_MS);

  req.on('close', () => {
    clearInterval(heartbeat);
    getSseClients(userId).delete(res);
    console.log(`[sse] disconnected (user: ${userId.slice(0, 8)}…) remaining: ${getSseClients(userId).size}`);
  });
});

// All Mail — full paginated inventory
app.get('/all-mail', async (req, res) => {
  const userId = await resolveUserId(req);
  if (!userId) return res.status(401).json({ error: 'unauthorized' });

  try {
    const cursor = req.query.cursor ? Number(req.query.cursor) : undefined;
    const { records, nextCursor } = await messageStore.getAll(userId, { limit: 50, cursor });

    const domainToSender = new Map();
    for (const m of records) {
      const domain = (m.fromEmail.split('@')[1] ?? '').toLowerCase();
      if (!domain) continue;
      if (!domainToSender.has(domain)) domainToSender.set(domain, m.fromName || domain);
    }

    const heroByDomain = new Map();
    await Promise.all(Array.from(domainToSender.keys()).map(async domain => {
      // Decoration must never be load-bearing. A missing image, a cold cache,
      // or an absent table costs this sender its picture and nothing else —
      // the mail underneath already exists and is not the AI's to withhold.
      try {
        const senderName = domainToSender.get(domain);
        const cached = await heroImage.getCachedAsset(domain);
        if (cached) {
          heroByDomain.set(domain, cached);
        } else {
          heroImage.ensureHeroAsset(openai, domain, senderName);
        }
      } catch (err) {
        console.warn(`[hero] skipped ${domain}: ${err.message}`);
      }
    }));

    const cards = records.map(m => {
      const domain = (m.fromEmail.split('@')[1] ?? '').toLowerCase();
      const cached = heroByDomain.get(domain) ?? null;
      return {
        ...m,
        avatarUri:          resolveAvatarUri({ sender: { domain } }),
        avatarFallbackText: (m.fromName || m.fromEmail || '?').charAt(0).toUpperCase(),
        interpreted:        m.aiStatus === 'done',
        unsubscribeUrl:     m.unsubscribeUrl ?? null,
        riskLevel:          m.riskLevel ?? 'none',
        riskEvidence:       m.riskEvidence ?? [],
        heroImageUrl:       cached ? heroImage.buildHeroImageUrl(req, domain) : null,
        heroImageBgColor:   cached?.bgColor ?? null,
        // The message's own picture, proxied. Present only when the email
        // actually carried one worth showing — the card falls back to the
        // sender's hero rather than inventing something.
        imageUrl:           m.imageUrl ? emailImage.buildImageUrl(req.get('host'), userId, m.messageId) : null,
      };
    });

    res.json(stripLoneSurrogates({ cards, nextCursor }));
  } catch (err) {
    console.error('[all-mail] error:', err.message);
    res.status(500).json({ error: 'all-mail failed' });
  }
});

// Mark message as read — removes UNREAD label via Gmail API + updates DB
app.patch('/messages/:messageId/read', async (req, res) => {
  const userId = await resolveUserId(req);
  if (!userId) return res.status(401).json({ error: 'unauthorized' });

  const { messageId } = req.params;

  try {
    const accessToken = await userStore.getValidAccessToken(userId);

    // Call Gmail API to remove UNREAD label
    const gmailRes = await fetch(
      `https://gmail.googleapis.com/gmail/v1/users/me/messages/${messageId}/modify`,
      {
        method:  'POST',
        headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body:    JSON.stringify({ removeLabelIds: ['UNREAD'] }),
      }
    );

    if (!gmailRes.ok) {
      const err = await gmailRes.json().catch(() => ({}));
      console.error('[read] Gmail modify failed:', JSON.stringify(err));
      return res.status(502).json({ error: 'Gmail modify failed' });
    }

    // Update local DB
    const existing = await messageStore.getMessage(userId, messageId);
    if (existing) {
      const newLabels = existing.labelIds.filter(l => l !== 'UNREAD');
      await messageStore.updateLabelIds(userId, messageId, newLabels);
    }

    // Notify SSE clients
    emitSSE(userId, { type: 'message-read', messageId });

    res.json({ success: true });
  } catch (err) {
    console.error('[read] error:', err.message);
    res.status(500).json({ error: 'mark-read failed' });
  }
});

// Pub/Sub push webhook — receives Gmail push notifications
app.post('/webhooks/gmail', async (req, res) => {
  // Respond 200 immediately so Pub/Sub doesn't retry
  res.sendStatus(200);

  try {
    // Verify JWT from Google (Authorization: Bearer <token>)
    const authHeader = req.headers['authorization'] ?? '';
    const jwt        = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;

    if (jwt && process.env.GOOGLE_PUBSUB_AUDIENCE) {
      try {
        const { OAuth2Client } = require('google-auth-library');
        const client = new OAuth2Client();
        await client.verifyIdToken({
          idToken:  jwt,
          audience: process.env.GOOGLE_PUBSUB_AUDIENCE,
        });
      } catch (verifyErr) {
        console.warn('[webhook] JWT verification failed:', verifyErr.message);
        return; // drop unverified push
      }
    }

    // Decode the Pub/Sub message
    const messageData = req.body?.message?.data;
    if (!messageData) return;

    const decoded = JSON.parse(Buffer.from(messageData, 'base64').toString('utf8'));
    const { emailAddress, historyId } = decoded;

    if (!emailAddress) return;

    // Look up user by email
    const user = await userStore.getUserByEmail(emailAddress);
    if (!user) {
      console.log(`[webhook] unknown email: ${emailAddress}`);
      return;
    }

    const userId = user.user_id;
    console.log(`[webhook] push for user ${userId.slice(0, 8)}… historyId: ${historyId}`);

    // Run incremental sync
    const { newUnreadIds } = await gmailSync.incrementalSync(userId);

    // Emit SSE for newly arrived messages
    for (const messageId of newUnreadIds) {
      const record = await messageStore.getMessage(userId, messageId);
      if (record) {
        emitSSE(userId, {
          type:               'message-added',
          messageId:          record.messageId,
          threadId:           record.threadId,
          labelIds:           record.labelIds,
          subject:            record.subject,
          fromName:           record.fromName,
          fromEmail:          record.fromEmail,
          snippet:            record.snippet,
          internalDate:       record.internalDate,
          postCutoff:         record.postCutoff,
          aiStatus:           record.aiStatus,
          avatarUri:          resolveAvatarUri({ sender: { domain: record.fromEmail.split('@')[1] ?? '' } }),
          avatarFallbackText: (record.fromName || record.fromEmail || '?').charAt(0).toUpperCase(),
        });
      }
    }

    // Wake the worker immediately for new unread mail
    if (newUnreadIds.length > 0) {
      processingWorker.wakeWorker(userId);
      // Silent push to wake the app in background so the feed cache stays fresh
      sendSilentPush(user.push_token);
    }
  } catch (err) {
    console.error('[webhook] processing error:', err.message);
  }
});

// Legacy endpoints kept for compatibility
app.post('/interpret-single', async (req, res) => {
  const email = req.body.email;
  if (!email) return res.status(400).json({ error: 'email required' });

  const [interpretResult, actionResult] = await Promise.allSettled([
    (async () => {
      const prompt = renderPrompt(PROMPTS.interpretEmail, {
        senderName: email.sender.name, senderEmail: email.sender.email,
        senderDomain: email.sender.domain, subject: email.subject,
        snippet: email.snippet,
        plainText: email.body.plainText?.slice(0, 1500) ?? '',
        htmlText: email.body.htmlText?.slice(0, 1500) ?? '',
        links: cleanLinks(email.signals.structuredLinks ?? []).length,
        unsubscribePresent: email.signals.unsubscribePresent,
        freeMailDomain: email.signals.freeMailDomain,
        replyToMismatch: email.signals.replyToMismatch,
        suspiciousSubjectHints: JSON.stringify(email.signals.suspiciousSubjectHints),
        greetingGeneric: email.signals.greetingGeneric,
        hasAttachments: email.signals.hasAttachments,
      });
      const response = await openai.responses.create({ model: 'gpt-5', input: prompt });
      const text = response.output_text;
      return { quote: parseXmlField(text, 'quote') || null, summary: parseXmlField(text, 'summary') ?? '' };
    })(),
    (async () => {
      const prompt = renderPrompt(PROMPTS.decideActionSurface, {
        senderName: email.sender.name, senderEmail: email.sender.email,
        senderDomain: email.sender.domain, subject: email.subject,
        snippet: email.snippet,
        plainText: email.body.plainText?.slice(0, 1500) ?? '',
        htmlText: email.body.htmlText?.slice(0, 1500) ?? '',
        links: cleanLinks(email.signals.structuredLinks ?? []).map(l => l.context ? `${l.text} | context: ${l.context} | url: ${l.url}` : `${l.text} | url: ${l.url}`).join('\n') || '(none)',
        unsubscribePresent: email.signals.unsubscribePresent,
        hasAttachments: email.signals.hasAttachments,
      });
      const response = await openai.responses.create({ model: 'gpt-5', input: prompt });
      const text = response.output_text;
      return {
        action: parseXmlField(text, 'action') || null,
        actionUrl: parseXmlField(text, 'actionUrl') || null,
        requiresAttention: (parseXmlField(text, 'requiresAttention') ?? 'false').trim().toLowerCase() === 'true',
      };
    })(),
  ]);

  const interp = interpretResult.status === 'fulfilled' ? interpretResult.value : { quote: null, summary: '' };
  const action = actionResult.status  === 'fulfilled' ? actionResult.value  : { action: null, actionUrl: null, requiresAttention: false };

  res.json({ card: {
    id: email.id,
    senderName: email.sender.name, senderEmail: email.sender.email,
    subject: email.subject, date: email.date, threadId: email.threadId,
    avatarUri: resolveAvatarUri(email), avatarFallbackText: resolveAvatarFallbackText(email),
    ...interp, ...action,
  }});
});

app.post('/session-recap', async (req, res) => {
  const { cards, userName, timeOfDay } = req.body;
  if (!Array.isArray(cards)) return res.status(400).json({ error: 'cards required' });

  const totalInView    = cards.length;
  const attentionCards = cards.filter(c => c.requiresAttention === true);
  const requireAttention = attentionCards.length;
  const formatCards = (arr) =>
    arr.map(c => `- From: ${c.fromName || c.fromEmail} | Subject: ${c.subject} | Summary: ${c.summary ?? c.snippet}${c.action ? ` | Action: ${c.action}` : ''}`).join('\n') || '(none)';

  const prompt = renderPrompt(PROMPTS.sessionRecap, {
    timeOfDay: timeOfDay ?? 'morning', userName: userName ?? '',
    totalInView, requireAttention,
    attentionCards: formatCards(attentionCards),
    contextCards:   formatCards(cards),
  });

  try {
    const response = await openai.responses.create({ model: 'gpt-5', input: prompt });
    const recap    = JSON.parse(response.output_text);
    recap.totalInView = totalInView;
    recap.requireAttention = requireAttention;
    res.json({ recap });
  } catch (err) {
    console.error('[session-recap] failed:', err.message);
    res.status(500).json({ error: 'recap failed' });
  }
});

app.get('/test-ai', async (req, res) => {
  try {
    const response = await openai.responses.create({ model: 'gpt-5', input: 'Say "AI is working"' });
    res.json({ success: true, output: response.output_text });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Unsubscribe — launch headless browser to complete unsubscribe flow
app.post('/unsubscribe', async (req, res) => {
  const userId = await resolveUserId(req);
  if (!userId) return res.status(401).json({ error: 'unauthorized' });

  const { messageId, unsubscribeUrl: directUnsubscribeUrl, senderName: directSenderName } = req.body;
  if (!messageId) return res.status(400).json({ error: 'messageId required' });

  let record = null;
  try {
    record = await messageStore.getMessage(userId, messageId);
  } catch (err) {
    console.warn('[unsubscribe] message lookup failed, falling back to request payload:', err.message);
  }

  const unsubscribeUrl = record?.unsubscribeUrl || directUnsubscribeUrl;
  const senderName = directSenderName || record?.fromName || record?.fromEmail || 'Sender';
  if (!unsubscribeUrl) return res.status(400).json({ error: 'no unsubscribe URL for this message' });

  // Registered before the first emit so `index` / `total` are populated from
  // the very first event the tray receives.
  beginUnsubscribeRun(userId, messageId);
  emitUnsubscribeStatus(userId, { messageId, senderName, step: 'queued', message: null });

  // Acknowledge immediately — status updates flow via SSE
  res.json({ success: true });

  let user = null;
  try {
    user = await userStore.getUser(userId);
  } catch (err) {
    console.warn('[unsubscribe] user lookup failed, continuing without DB user:', err.message);
  }

  const authProfile = await resolveUserProfile(req);
  const requestAccessToken = authProfile?.token ?? null;
  const userEmail = authProfile?.profile?.email || user?.email || '';

  const emit = (step, message, extra = {}) =>
    emitUnsubscribeStatus(userId, { messageId, senderName, step, message, ...extra });

  // `failed` is the retryable outcome, and the contract says it is auto-retried
  // once before the user ever sees it. So the first failure is swallowed here.
  // `no_link` and `needs_you` are not retried: they are standing facts about
  // their page, and running at them again would only be wrong twice.
  const runTwiceIfItFails = async (attempt) => {
    let result = await attempt();
    if (result.step !== 'failed') return result;

    console.warn(`[unsubscribe] first attempt failed for ${senderName}, retrying once`);
    emit('navigating', 'Trying that again', { evidence: `retry after: ${result.evidence ?? 'no detail'}` });
    return attempt();
  };

  // Handle mailto: unsubscribe (send an email, no browser needed)
  if (unsubscribeUrl.startsWith('mailto:')) {
    const sendUnsubscribeMail = async () => {
      emit('navigating', 'Sending the mail they ask for');
      try {
        const accessToken = requestAccessToken || await userStore.getValidAccessToken(userId);
        const mailto = new URL(unsubscribeUrl);
        const to     = mailto.pathname;
        const subject = mailto.searchParams.get('subject') ?? 'Unsubscribe';
        const raw = [
          `To: ${to}`,
          `Subject: ${subject}`,
          'Content-Type: text/plain',
          '',
          'Unsubscribe',
        ].join('\r\n');
        const encoded = Buffer.from(raw).toString('base64url');
        const gmailRes = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/messages/send', {
          method:  'POST',
          headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
          body:    JSON.stringify({ raw: encoded }),
        });
        if (!gmailRes.ok) throw new Error(`gmail send failed (${gmailRes.status})`);
        // There is no page to read back here, so the sentence says what was
        // actually done and stops short of claiming they confirmed anything.
        return { step: 'done', message: 'Sent it to their unsubscribe address', evidence: `mailto:${to}` };
      } catch (err) {
        console.error('[unsubscribe] mailto error:', err.message);
        return { step: 'failed', message: null, evidence: describeUnsubscribeError(err) };
      }
    };

    const result = await runTwiceIfItFails(sendUnsubscribeMail);
    emit(result.step, result.message, { evidence: result.evidence ?? null });
    return;
  }

  // Handle https: unsubscribe via Playwright
  let browser;
  try {
    await ensurePlaywrightChromium();
    const { chromium } = require('playwright');
    browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'] });

    const result = await runTwiceIfItFails(() =>
      runUnsubscribeAgent({ browser, unsubscribeUrl, userEmail, emit, openai, senderName })
        .catch(err => {
          console.error('[unsubscribe] agent error:', err.message);
          return { step: 'failed', message: null, evidence: describeUnsubscribeError(err) };
        }));

    emit(result.step, result.message, { evidence: result.evidence ?? null });
  } catch (err) {
    console.error('[unsubscribe] browser error:', err.message);
    emit('failed', null, { evidence: describeUnsubscribeError(err) });
  } finally {
    if (browser) await browser.close().catch(() => {});
  }
});

app.get('/unsubscribe/:messageId/status', async (req, res) => {
  const userId = await resolveUserId(req);
  if (!userId) return res.status(401).json({ error: 'unauthorized' });

  const { messageId } = req.params;
  const status = pruneUnsubscribeStatuses(userId).get(messageId);
  if (!status) return res.status(404).json({ error: 'status not found' });

  const { updatedAt, ...payload } = status;
  res.json(payload);
});

// ─── UI copy ──────────────────────────────────────────────────────────────

const uiCopyCache = new Map(); // userId → copy object

// Discuss — answer a question about one specific email the user is looking at
app.post('/discuss', async (req, res) => {
  const userId = await resolveUserId(req);
  if (!userId) return res.status(401).json({ error: 'unauthorized' });

  const { messageId, question } = req.body;
  if (!messageId || !question) return res.status(400).json({ error: 'messageId and question required' });

  try {
    const record = await messageStore.getMessage(userId, messageId);
    if (!record) return res.status(404).json({ error: 'message not found' });

    // The body is fetched fresh rather than stored: a question about an email
    // deserves the whole email, and we keep only enough to build the feed.
    let body = record.snippet ?? '';
    try {
      const raw = await gmailSync.fetchFullMessage(userId, messageId);
      body = cleanEmailForAI(raw).body?.plainText?.slice(0, 6000) || body;
    } catch (err) {
      console.warn('[discuss] body fetch failed, using snippet:', err.message);
    }

    const prompt = renderPrompt(PROMPTS.discussThread, {
      fromName: record.fromName ?? '', fromEmail: record.fromEmail ?? '',
      subject: record.subject ?? '', receivedAt: new Date(Number(record.internalDate)).toISOString(),
      body,
      quote: record.quote ?? '(none)', summary: record.summary ?? '(none)',
      question: String(question).slice(0, 500),
    });

    const response = await openai.responses.create({ model: 'gpt-5', input: prompt });
    res.json({ answer: response.output_text.trim() });
  } catch (err) {
    console.error('[discuss] error:', err.message);
    res.status(500).json({ error: 'discuss failed' });
  }
});

// Suggested reply — offered to the composer, never sent
app.post('/suggest-reply', async (req, res) => {
  const userId = await resolveUserId(req);
  if (!userId) return res.status(401).json({ error: 'unauthorized' });

  const { messageId } = req.body;
  if (!messageId) return res.status(400).json({ error: 'messageId required' });

  try {
    const record = await messageStore.getMessage(userId, messageId);
    if (!record) return res.status(404).json({ error: 'message not found' });

    let body = record.snippet ?? '';
    try {
      const raw = await gmailSync.fetchFullMessage(userId, messageId);
      body = cleanEmailForAI(raw).body?.plainText?.slice(0, 6000) || body;
    } catch (err) {
      console.warn('[suggest-reply] body fetch failed, using snippet:', err.message);
    }

    const prompt = renderPrompt(PROMPTS.suggestReply, {
      fromName: record.fromName ?? '', fromEmail: record.fromEmail ?? '',
      subject: record.subject ?? '', body,
      quote: record.quote ?? '(none)', summary: record.summary ?? '(none)',
    });

    const response = await openai.responses.create({ model: 'gpt-5', input: prompt });
    res.json({ draft: response.output_text.trim() });
  } catch (err) {
    console.error('[suggest-reply] error:', err.message);
    res.status(500).json({ error: 'suggest failed' });
  }
});

app.get('/ui-copy', async (req, res) => {
  const userId = await resolveUserId(req);
  if (!userId) return res.status(401).json({ error: 'unauthorized' });

  if (uiCopyCache.has(userId)) return res.json(uiCopyCache.get(userId));

  try {
    const prompt = renderPrompt(PROMPTS.generateUiCopy, {});
    const response = await openai.responses.create({ model: 'gpt-5', input: prompt });
    const copy = JSON.parse(response.output_text);
    uiCopyCache.set(userId, copy);
    res.json(copy);
  } catch (err) {
    console.error('[ui-copy] failed:', err.message);
    res.status(500).json({ error: 'ui-copy failed' });
  }
});

// ─── Unsubscribe URL backfill ─────────────────────────────────────────────
// Runs once per user on startup. Fetches only the List-Unsubscribe header
// (metadata format) for any existing message that has no unsubscribe_url yet.

const { extractUnsubscribeUrl: _extractUnsubscribeUrl } = (() => {
  // Inline the same header parser from emailCleaner so we don't circular-import
  function extractUnsubscribeUrl(raw) {
    if (!raw) return null;
    const httpsMatch = raw.match(/<(https?:\/\/[^>]+)>/i);
    if (httpsMatch) return httpsMatch[1];
    const mailtoMatch = raw.match(/<(mailto:[^>]+)>/i);
    if (mailtoMatch) return mailtoMatch[1];
    return null;
  }
  return { extractUnsubscribeUrl };
})();

async function runUnsubscribeBackfill(userId) {
  try {
    const messageIds = await messageStore.getMessageIdsNeedingUnsubscribeBackfill(userId);
    if (messageIds.length === 0) return;

    console.log(`[backfill] ${messageIds.length} messages to check for unsubscribe URLs (user: ${userId.slice(0, 8)}…)`);

    const accessToken = await userStore.getValidAccessToken(userId);
    const BATCH = 20;
    let found = 0;

    for (let i = 0; i < messageIds.length; i += BATCH) {
      const slice = messageIds.slice(i, i + BATCH);
      await Promise.all(slice.map(async (messageId) => {
        try {
          const res = await fetch(
            `https://gmail.googleapis.com/gmail/v1/users/me/messages/${messageId}?format=metadata&metadataHeaders=List-Unsubscribe`,
            { headers: { Authorization: `Bearer ${accessToken}` } }
          );
          if (!res.ok) return;
          const msg = await res.json();
          const headers = msg.payload?.headers ?? [];
          const raw = headers.find(h => h.name.toLowerCase() === 'list-unsubscribe')?.value ?? '';
          const url = _extractUnsubscribeUrl(raw);
          // Write NULL explicitly so we don't re-check this message next time
          await messageStore.setUnsubscribeUrl(userId, messageId, url ?? '');
          if (url) found++;
        } catch { /* skip individual failures */ }
      }));
      // Brief pause between batches to avoid rate limits
      if (i + BATCH < messageIds.length) {
        await new Promise(r => setTimeout(r, 200));
      }
    }

    console.log(`[backfill] done — ${found} unsubscribe URLs found (user: ${userId.slice(0, 8)}…)`);
  } catch (err) {
    console.error(`[backfill] error for user ${userId.slice(0, 8)}…:`, err.message);
  }
}

/// Gives posts that were interpreted before image extraction existed the
/// picture their email was already carrying. Without this, only mail arriving
/// from now on would ever show one, and the feed would stay half-decorated
/// indefinitely.
///
/// The empty string is written when nothing is found, so a message is examined
/// once and never again — the same trick the unsubscribe backfill uses. A
/// message with no picture is a fact worth remembering.
async function runImageBackfill(userId) {
  try {
    const messageIds = await messageStore.getMessageIdsNeedingImageBackfill(userId);
    if (messageIds.length === 0) return;

    console.log(`[image-backfill] ${messageIds.length} message(s) to check (user: ${userId.slice(0, 8)}…)`);
    const BATCH = 10;
    let found = 0;

    for (let i = 0; i < messageIds.length; i += BATCH) {
      const slice = messageIds.slice(i, i + BATCH);
      await Promise.all(slice.map(async (messageId) => {
        try {
          const rawMsg = await gmailSync.fetchFullMessage(userId, messageId);
          const picture = emailImage.pickHeroImage(emailImage.extractHtml(rawMsg.payload));
          await messageStore.setImageUrl(userId, messageId, picture ?? '');
          if (picture) found++;
        } catch { /* one message's picture is never worth failing the pass */ }
      }));
      // Gmail's per-user rate limit is the real constraint here, not ours.
      if (i + BATCH < messageIds.length) await new Promise(r => setTimeout(r, 400));
    }

    console.log(`[image-backfill] done — ${found} picture(s) found (user: ${userId.slice(0, 8)}…)`);
  } catch (err) {
    console.error(`[image-backfill] error for user ${userId.slice(0, 8)}…:`, err.message);
  }
}

// ─── Bootstrap ────────────────────────────────────────────────────────────

processingWorker.init({ streamInterpretEmail, streamDecideActionSurface, detectRiskSignals, emitSSE });
watchManager.startWatchRenewalCron();

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);

  // Resume workers and renew expiring watches for all existing users.
  // This ensures that after a cold start, processing and push notifications
  // are restored without waiting for an app open to trigger /auth/register.
  userStore.getAllUsers().then(users => {
    if (users.length === 0) return;
    console.log(`[startup] resuming workers for ${users.length} user(s)`);
    for (const user of users) {
      processingWorker.startWorker(user.user_id);
      // Non-blocking backfill — runs in background, doesn't block startup
      runImageBackfill(user.user_id).catch(err =>
        console.error('[startup] image backfill error:', err.message)
      );
      runUnsubscribeBackfill(user.user_id).catch(err =>
        console.error('[startup] backfill error:', err.message)
      );
    }
    watchManager.renewAllExpiring().catch(err =>
      console.error('[startup] watch renewal failed:', err.message)
    );
  }).catch(err => {
    console.error('[startup] startup resume failed:', err.message);
  });
});
