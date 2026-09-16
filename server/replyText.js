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
  // A text/plain part is not a promise that the part is text. Retailers
  // routinely paste the HTML build into it — one sender's "plain" body opened
  // `<p>Hi CRAIG,</p><br><br>` and that is what reached the list row. Trust
  // the declared type, but check it.
  const looksLikeHtml = /<\/?(p|br|div|table|td|tr|span|a|img|h[1-6])\b[^>]*>/i.test(plain);
  const raw = plain && !looksLikeHtml
    ? plain
    : stripHtml(plain || findPart(payload, 'text/html'));
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
  //
  // A line that is nothing but a bracketed bare URL goes with them. That is
  // the footnote an HTML-to-text converter leaves behind, and a link tracker
  // leaves two — the sender's real link, then a 70-character rewrite of the
  // same destination on the line below it. The same rule applies: it is a copy
  // of the link directly above, so it is not the sender saying anything twice.
  const kept = text
    .split('\n')
    .filter(line => !/^\s*>/.test(line))
    .filter(line => !/^\s*[[<]\s*(https?:\/\/|mailto:|data:)\S*\s*[\]>]\s*$/i.test(line));

  // Unless that was the whole message. Somebody who sends one link in
  // brackets and nothing else has still sent something.
  if (kept.join('').trim()) text = kept.join('\n');

  // The same footnote, wedged mid-sentence — but only when it repeats the
  // link directly before it.
  //
  // `https://calendly.com/vikram-1980 <https://znsrc.com/c/jfkcfhhxlt>` is a
  // tracker's rewrite of the URL it follows, and cutting it loses nothing.
  // A bare `<https://example.com/spec>` with no URL before it is somebody
  // citing a source in the RFC style, and cutting that leaves "See for
  // details." — deleting what a person sent, which is the error this file
  // exists to avoid. Same rule as everywhere else: remove copies, keep
  // originals.
  text = text
    .replace(/(https?:\/\/\S+)[ \t]*<\s*(?:https?:\/\/|mailto:)[^>\s]*\s*>/gi, '$1')
    .replace(/[ \t]{2,}/g, ' ');

  return unwrap(text)
    .replace(/\n{3,}/g, '\n\n')
    .replace(/[ \t]+$/gm, '')
    .trim();
}

/// Undo the sender's line wrapping.
///
/// Plain-text email is hard-wrapped at about 75 columns, which was right when
/// it was read in a terminal and is wrong in a bubble 272 points wide: the
/// text wraps once for the phone and again where the sender's client broke it,
/// so "Please also see the Token 101 / attached that I promised you." splits
/// mid-sentence for no reason a reader can see.
///
/// A long line is a wrapped line. A short one was broken on purpose — a
/// signature, an address, a list — and joining those would run somebody's name
/// into their job title. 60 is comfortably under every common wrap width and
/// above almost every deliberate line.
const WRAP_WIDTH = 60;

function unwrap(text) {
  const lines = text.split('\n');
  const out = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const previous = out[out.length - 1];

    const isContinuation =
      previous !== undefined &&
      previous.trim().length >= WRAP_WIDTH &&
      line.trim().length > 0 &&
      // A label ending in a colon introduces what follows; it is not a
      // sentence that ran out of room.
      !previous.trim().endsWith(':') &&
      // Bullets, numbers and quotes start their own line by intent.
      !/^\s*([-*•–]|\d+[.)])\s/.test(line) &&
      // A line that is only a URL is its own object — the card treatment
      // downstream depends on it staying that way.
      !/^\s*(https?:\/\/|www\.)\S*\s*$/i.test(line) &&
      !/^\s*(https?:\/\/|www\.)\S*\s*$/i.test(previous);

    if (isContinuation) {
      out[out.length - 1] = previous.replace(/\s+$/, '') + ' ' + line.replace(/^\s+/, '');
    } else {
      out.push(line);
    }
  }

  return out.join('\n');
}

module.exports = { newText, stripHtml, unwrap };
