require('dotenv').config();

const fs = require('fs');
const path = require('path');
const express = require('express');
const cors = require('cors');
const OpenAI = require('openai');

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

// ─── Routes ───────────────────────────────────────────────────────────────

app.post('/interpret-single', async (req, res) => {
  const email = req.body.email;
  if (!email) return res.status(400).json({ error: 'email required' });
  console.log(`[interpret-single] processing ${email.id} "${email.subject}"`);

  let quote = '';
  let summary = 'Unable to summarize email.';
  let action = null;
  let actionUrl = null;

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
  };

  console.log(`[interpret-single] done ${email.id}`);
  res.json({ card });
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
