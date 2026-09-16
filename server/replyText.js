// What somebody actually said this time.
//
// An email body is not a message. It is a message followed by every previous
// message in the thread, quoted. In a feed of bubbles that means the entire
// conversation appears inside every turn of it, growing each time — which is
// exactly why a reading pane collapses the quoted part behind a control.
//
// ONE RULE: cut what is a copy of another message in this thread. Keep
// everything the sender's own message contains.
//
// So signatures stay, and so does "Sent from my iPhone". They are noise, but
// they are not duplicates, and the cost of guessing wrong in the other
// direction is deleting something a person wrote. When nothing matches, the
// whole body is returned.

const { decodeEntities } = require('./emailCleaner');

/// Where a reply stops being new text and starts repeating the thread. Each of
/// these begins a quoted history in some mail client's house style.
const QUOTE_STARTS = [
  // "On Tue, Sep 15, 2026 at 4:32 PM Craig Roberts <c@x.com> wrote:"
  //
  // `[\s\S]` and not `.` — Gmail hard-wraps this marker at 78 columns, so in
  // real mail it routinely arrives as two lines with the break falling
  // wherever the address happens to end. A `.` stops at the newline and the
  // marker goes unrecognised, which is how a whole quoted thread survives into
  // a bubble. Lazy and length-bounded so it still matches the nearest `wrote:`
  // rather than running down the page.
  /^[ \t]*On [\s\S]{5,200}?\bwrote:[ \t]*$/im,
  // The German, French and Spanish equivalents.
  /^[ \t]*(Am|Le|El) [\s\S]{5,200}?\s(schrieb|a écrit|escribió):[ \t]*$/im,
  /^\s*-{2,}\s*Original Message\s*-{2,}\s*$/im,
  /^\s*-{2,}\s*Forwarded message\s*-{2,}\s*$/im,
  /^\s*_{5,}\s*$/m,
  // Outlook's block, which is the quoted message's headers rather than a
  // sentence introducing them.
  /^\s*From:\s.+\n(\s*(Sent|Date|To|Cc|Subject):\s.*\n){1,4}/im,
];

function stripHtml(html) {
  return decodeEntities(
    html
      .replace(/<(script|style)[^>]*>[\s\S]*?<\/\1>/gi, '')
      // Block boundaries become newlines so paragraphs survive as paragraphs.
      .replace(/<\/(p|div|tr|li|h[1-6]|blockquote)>/gi, '\n')
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<[^>]+>/g, '')
  );
}

function decodeBody(data) {
  if (!data) return '';
  return Buffer.from(data.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8');
}

function findPart(payload, mimeType) {
  if (!payload) return '';
  if (payload.mimeType === mimeType && payload.body?.data) return decodeBody(payload.body.data);
  for (const part of payload.parts ?? []) {
    const found = findPart(part, mimeType);
    if (found) return found;
  }
  return '';
}

/**
 * One message's own text, with the thread it quotes removed.
 *
 * Plain text is preferred over HTML: the sender's mail client already produced
 * a text rendering of their own message, and it is a better one than tag
 * stripping will produce.
 */
function newText(payload) {
  const plain = findPart(payload, 'text/plain');
  const raw = plain || stripHtml(findPart(payload, 'text/html'));
  if (!raw) return '';

  let text = raw.replace(/\r\n/g, '\n');

  // Cut at whichever quote marker comes first.
  let cut = text.length;
  for (const pattern of QUOTE_STARTS) {
    const match = pattern.exec(text);
    if (match && match.index < cut) cut = match.index;
  }
  text = text.slice(0, cut);

  // A run of ">" lines is quoted material wherever it appears, including
  // before any marker — some clients quote without announcing it.
  text = text
    .split('\n')
    .filter(line => !/^\s*>/.test(line))
    .join('\n');

  return text
    .replace(/\n{3,}/g, '\n\n')
    .replace(/[ \t]+$/gm, '')
    .trim();
}

module.exports = { newText, stripHtml };
