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

/// The named entities that actually turn up in mail. The previous list held
/// six, so a card quoted a sender as saying "&reg; and World of Hyatt
/// accounts are linked" — the entity survived cleaning, went into the model,
/// and came back out inside a quote the product promises is verbatim. A
/// verbatim quote containing markup is worse than a paraphrase, because it
/// claims to be exactly what someone wrote.
const ENTITIES = {
  nbsp: ' ', amp: '&', lt: '<', gt: '>', quot: '"', apos: "'",
  reg: '\u00AE', copy: '\u00A9', trade: '\u2122', deg: '\u00B0',
  hellip: '\u2026', mdash: '\u2014', ndash: '\u2013', minus: '\u2212',
  lsquo: '\u2018', rsquo: '\u2019', ldquo: '\u201C', rdquo: '\u201D',
  sbquo: '\u201A', bdquo: '\u201E', dagger: '\u2020', bull: '\u2022',
  middot: '\u00B7', laquo: '\u00AB', raquo: '\u00BB', euro: '\u20AC',
  pound: '\u00A3', yen: '\u00A5', cent: '\u00A2', sect: '\u00A7',
  para: '\u00B6', times: '\u00D7', divide: '\u00F7', plusmn: '\u00B1',
  frac12: '\u00BD', frac14: '\u00BC', frac34: '\u00BE', eacute: '\u00E9',
  egrave: '\u00E8', agrave: '\u00E0', ccedil: '\u00E7', uuml: '\u00FC',
  ouml: '\u00F6', auml: '\u00E4', szlig: '\u00DF', ntilde: '\u00F1',
  shy: '', zwnj: '', zwj: '', ensp: ' ', emsp: ' ', thinsp: ' ',
};

/// Named and numeric, decimal and hex. Runs last so an entity that decodes to
/// a character is never re-read as markup.
function decodeEntities(text) {
  return text
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) => {
      const code = parseInt(hex, 16);
      return Number.isFinite(code) && code > 0 && code <= 0x10FFFF
        ? String.fromCodePoint(code) : '';
    })
    .replace(/&#(\d+);/g, (_, dec) => {
      const code = Number(dec);
      return Number.isFinite(code) && code > 0 && code <= 0x10FFFF
        ? String.fromCodePoint(code) : '';
    })
    .replace(/&([a-z][a-z0-9]{1,9});/gi, (match, name) => {
      const key = name.toLowerCase();
      return key in ENTITIES ? ENTITIES[key] : match;
    });
}

function cleanHtml(html) {
  return decodeEntities(
    html
      .replace(/<(script|style)[^>]*>[\s\S]*?<\/\1>/gi, '')
      .replace(/<[^>]+>/g, ' ')
  )
    .replace(/\s+/g, ' ')
    .trim();
}

function stripTags(s) {
  return decodeEntities(s.replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
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

module.exports = { cleanEmailForAI, decodeEntities };
