// ─── Email body extractor + AI input builder ──────────────────────────────
// Ports the client-side cleanEmailForAI to server-side Node.js.
// Used by the processing worker when fetching full messages for AI.

const FREE_MAIL_DOMAINS = new Set([
  'gmail.com', 'yahoo.com', 'outlook.com', 'hotmail.com',
  'icloud.com', 'live.com', 'msn.com', 'ymail.com',
]);

const SUSPICIOUS_SUBJECT_PATTERNS = [
  { label: 'urgency',  pattern: /urgent|immediately|action required|act now|response required/i },
  { label: 'threat',   pattern: /suspended|account.*(closed|terminated|locked|disabled)/i },
  { label: 'prize',    pattern: /you('ve| have) won|winner|claim your (prize|reward|gift)/i },
  { label: 'verify',   pattern: /verify your (account|identity|email|information)/i },
  { label: 'unusual',  pattern: /unusual (activity|sign.?in|access)/i },
];

const GENERIC_GREETING = /^(dear (customer|user|account holder|member|friend|sir|madam)|hello (there|friend)|greetings)/i;

function getHeader(headers, name) {
  return headers.find(h => h.name.toLowerCase() === name.toLowerCase())?.value ?? '';
}

function decodeBody(data) {
  if (!data) return '';
  return Buffer.from(data.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8');
}

function extractBody(payload, mimeType) {
  if (!payload) return '';
  if (payload.mimeType === mimeType && payload.body?.data) {
    return decodeBody(payload.body.data);
  }
  for (const part of payload.parts ?? []) {
    const result = extractBody(part, mimeType);
    if (result) return result;
  }
  return '';
}

function cleanHtml(html) {
  return html
    .replace(/<(script|style)[^>]*>[\s\S]*?<\/\1>/gi, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/\s+/g, ' ')
    .trim();
}

function stripTags(s) {
  return s.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
}

function extractStructuredLinks(html) {
  const results = [];
  const seen = new Set();
  const anchorRegex = /<a[^>]+href="(https?:\/\/[^"]+)"[^>]*>([\s\S]*?)<\/a>/gi;
  let match;
  while ((match = anchorRegex.exec(html)) !== null) {
    const url = match[1];
    if (seen.has(url)) continue;
    seen.add(url);
    const text = stripTags(match[2]);
    if (!text || text.length < 2) continue;
    const start = Math.max(0, match.index - 100);
    const end = Math.min(html.length, match.index + match[0].length + 100);
    const surrounding = stripTags(html.slice(start, end));
    const contextRaw = surrounding.replace(text, '').trim().slice(0, 120);
    const context = contextRaw.length > 4 ? contextRaw : null;
    results.push({ text, url, context });
  }
  return results;
}

function hasAttachmentParts(payload) {
  if (!payload) return false;
  if (payload.filename && payload.filename.length > 0) return true;
  for (const part of payload.parts ?? []) {
    if (hasAttachmentParts(part)) return true;
  }
  return false;
}

function parseSender(from) {
  const match = from.match(/^(.*?)\s*<([^>]+)>$/);
  const email = match ? match[2].trim() : from.trim();
  const name  = match ? match[1].replace(/^"|"$/g, '').trim() : email;
  const domain = email.split('@')[1] ?? '';
  return { name, email, domain };
}

function extractUnsubscribeUrl(headers) {
  const raw = getHeader(headers, 'List-Unsubscribe');
  if (!raw) return null;
  // Header can contain multiple entries like: <https://...>, <mailto:...>
  // Prefer the https URL; fall back to mailto
  const httpsMatch = raw.match(/<(https?:\/\/[^>]+)>/i);
  if (httpsMatch) return httpsMatch[1];
  const mailtoMatch = raw.match(/<(mailto:[^>]+)>/i);
  if (mailtoMatch) return mailtoMatch[1];
  return null;
}

function cleanEmailForAI(msg) {
  const headers    = msg.payload?.headers ?? [];
  const from       = getHeader(headers, 'From');
  const sender     = parseSender(from);
  const replyToRaw = getHeader(headers, 'Reply-To');
  const replyTo    = replyToRaw ? parseSender(replyToRaw).email : null;
  const replyToDomain = replyTo ? (replyTo.split('@')[1] ?? '') : null;
  const subject    = getHeader(headers, 'Subject');
  const plainText  = extractBody(msg.payload, 'text/plain');
  const htmlRaw    = extractBody(msg.payload, 'text/html');
  const htmlText   = cleanHtml(htmlRaw);
  const structuredLinks = extractStructuredLinks(htmlRaw);
  const readableText = (plainText || htmlText).trimStart();
  const links = structuredLinks.map(l => l.url);

  const unsubscribeUrl     = extractUnsubscribeUrl(headers);
  const unsubscribePresent =
    !!unsubscribeUrl ||
    /unsubscribe/i.test(plainText) ||
    /unsubscribe/i.test(htmlRaw);

  const freeMailDomain = FREE_MAIL_DOMAINS.has(sender.domain.toLowerCase());

  const replyToMismatch =
    !!replyTo && !!replyToDomain &&
    replyToDomain.toLowerCase() !== sender.domain.toLowerCase();

  const suspiciousSubjectHints = SUSPICIOUS_SUBJECT_PATTERNS
    .filter(({ pattern }) => pattern.test(subject))
    .map(({ label }) => label);

  const greetingGeneric = GENERIC_GREETING.test(readableText.slice(0, 80));
  const hasAttachments  = hasAttachmentParts(msg.payload);

  return {
    id:             msg.id,
    threadId:       msg.threadId,
    sender:         { ...sender, replyTo },
    subject,
    date:           msg.internalDate ?? getHeader(headers, 'Date'),
    snippet:        msg.snippet ?? '',
    unsubscribeUrl: unsubscribeUrl ?? null,
    body:           { plainText, htmlText },
    signals: {
      links,
      structuredLinks,
      unsubscribePresent,
      freeMailDomain,
      replyToMismatch,
      suspiciousSubjectHints,
      greetingGeneric,
      hasAttachments,
    },
  };
}

module.exports = { cleanEmailForAI };
