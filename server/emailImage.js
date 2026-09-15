// The picture the email already contains.
//
// A generated hero says what a sender is like. This says what *this* message
// is about — the apartment StreetEasy is showing you, the flight Delta is
// confirming — which is the difference between a feed that looks like a feed
// and one that looks like a list with decoration on it.
//
// Nothing here is fetched. Extraction reads the HTML the worker already has;
// the bytes are pulled later, by us, through the proxy — never by the reader's
// device. An <img> in a marketing email is very often a beacon, and rendering
// one straight from the feed would tell every sender in the list what time you
// scrolled past them. That is a worse leak than opening the mail.

/// Substrings that mean "this image is furniture, not content". Matched
/// against the lowercased URL.
const FURNITURE = [
  'track', 'pixel', 'beacon', 'open.', '/open', 'spacer', 'blank', 'clear.',
  'transparent', 'shim', '1x1', 'px.gif', 'logo', 'icon', 'badge', 'footer',
  'unsubscribe', 'social', 'facebook', 'twitter', 'instagram', 'linkedin',
  'youtube', 'tiktok', 'pinterest', 'app-store', 'appstore', 'google-play',
  'googleplay', 'playstore', 'divider', 'border', 'bullet', 'arrow', 'star',
  'sprite', 'emoji', 'avatar', 'signature',
  // Masthead strips. A "header" image is the brand's name set in type, which
  // is the one thing the generated hero already does better — and West Elm's
  // was picked as this email's picture until it was listed here.
  'banner', 'header', 'masthead', 'preheader', 'nav-', 'wordmark',
];

/// Declared dimensions below this are decoration at best and a beacon at worst.
const MIN_EDGE = 180;
/// Wider than this is a rule, a strip, or a masthead — not a photograph.
const MAX_ASPECT = 3;

function decodeBody(data) {
  if (!data) return '';
  return Buffer.from(data.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8');
}

/// Depth-first, first match wins — the same shape the body endpoint uses.
function extractHtml(payload) {
  if (!payload) return '';
  if (payload.mimeType === 'text/html' && payload.body?.data) return decodeBody(payload.body.data);
  for (const part of payload.parts ?? []) {
    const found = extractHtml(part);
    if (found) return found;
  }
  return '';
}

/// Dimensions baked into a filename, as in `EM_Header_WE-Main_700x114.jpg`.
/// Bulk senders name their assets this way constantly, and it is often the
/// only size information in the document — the <img> itself carries none.
function edgesFromUrl(url) {
  const match = url.match(/(\d{2,4})\s*[x×]\s*(\d{2,4})(?=\D|$)/i);
  if (!match) return null;
  return { width: Number(match[1]), height: Number(match[2]) };
}

function attr(tag, name) {
  const match = tag.match(new RegExp(`${name}\\s*=\\s*["']?([^"'\\s>]+)`, 'i'));
  return match ? match[1] : null;
}

/// A declared edge, from the attribute or from an inline style. Returns null
/// when the email does not say — which is common and is not disqualifying.
function declaredEdge(tag, axis) {
  const direct = attr(tag, axis);
  if (direct && /^\d+$/.test(direct)) return Number(direct);
  const style = tag.match(new RegExp(`${axis}\\s*:\\s*(\\d+)\\s*px`, 'i'));
  return style ? Number(style[1]) : null;
}

/**
 * Every image in this email worth considering, best first.
 *
 * It used to return one. That was the bug behind "some emails don't show a
 * picture": the name-based tests here cannot tell a 1280x102 masthead strip
 * from a photograph, so the real check happens later against actual pixels —
 * and when the single committed pick failed that check, the post was left with
 * nothing, even though the email often carried a perfectly good photo three
 * images further down. Ranking and falling through costs one extra HEAD-sized
 * fetch and recovers most of those.
 *
 * Deliberately conservative about what enters the list at all: a wrong picture
 * on a card is worse than none, because the card is a claim about what the
 * message is.
 */
function pickCandidates(html) {
  if (!html) return null;

  const tags = html.match(/<img\b[^>]*>/gi) ?? [];
  const candidates = [];

  for (const tag of tags) {
    const src = attr(tag, 'src');
    if (!src || !/^https?:\/\//i.test(src)) continue;

    const url = src.replace(/&amp;/g, '&');
    const lower = url.toLowerCase();
    if (FURNITURE.some(word => lower.includes(word))) continue;

    // GIFs are the native format of the tracking pixel, and a real hero
    // photograph is never one. The Democratic Party's beacon —
    // `o.gif?akid=9158…` — cleared every other test here and was chosen as
    // that email's picture, which would have made the feed fire a read
    // receipt while rendering it.
    if (/\.gif(\?|$)/i.test(lower)) continue;

    const fromName = edgesFromUrl(lower);
    const width = declaredEdge(tag, 'width') ?? fromName?.width ?? null;
    const height = declaredEdge(tag, 'height') ?? fromName?.height ?? null;

    // A stated size that is small is a real answer, and the answer is no.
    if ((width !== null && width < MIN_EDGE) || (height !== null && height < MIN_EDGE)) continue;
    // A known shape that is a long thin strip is a masthead, not a picture.
    if (width && height && Math.max(width / height, height / width) > MAX_ASPECT) continue;

    candidates.push({ url, area: (width ?? 0) * (height ?? 0), stated: width !== null });
  }

  if (!candidates.length) return [];

  // Sized images first, largest to smallest — the email told us how big it
  // meant them to be, and that is the best signal available before fetching.
  // Unsized ones follow in document order: the first big picture in a
  // marketing email is nearly always the one the layout was built around.
  const sized = candidates.filter(c => c.stated && c.area > 0)
    .sort((a, b) => b.area - a.area);
  const unsized = candidates.filter(c => !(c.stated && c.area > 0));

  const ordered = [...sized, ...unsized].map(c => c.url);
  // Four is enough. Past that an email is a catalogue and the fifth image is
  // not what it is about.
  return Array.from(new Set(ordered)).slice(0, 4);
}

/// Back-compat for anything still asking for a single pick.
function pickHeroImage(html) {
  return pickCandidates(html)[0] ?? null;
}

/// Fetched and measured, because the name never says. Returns the first
/// candidate whose actual pixels are a photograph rather than a masthead
/// strip, or null when the email has nothing usable.
///
/// This runs server-side during interpretation, never on the reader's device
/// and never on their request path — which is also what keeps the sender from
/// learning when anyone looked.
async function resolveBest(candidates, { fetchImpl = fetch } = {}) {
  let sharp;
  try {
    sharp = require('sharp');
  } catch {
    // Without sharp there is no measurement, so trust the ranking rather than
    // dropping the picture entirely.
    return candidates[0] ?? null;
  }

  for (const url of candidates) {
    try {
      const res = await fetchImpl(url, {
        redirect: 'follow',
        signal: AbortSignal.timeout(8000),
        headers: { 'User-Agent': 'DecisionInbox/1.0 (+image-proxy)' },
      });
      if (!res.ok) continue;
      if (!(res.headers.get('content-type') ?? '').startsWith('image/')) continue;

      const raw = Buffer.from(await res.arrayBuffer());
      if (raw.length > 12 * 1024 * 1024) continue;

      const meta = await sharp(raw).metadata();
      const w = meta.width ?? 0;
      const h = meta.height ?? 0;
      if (!w || !h) continue;
      if (Math.min(w, h) < MIN_EDGE) continue;
      if (Math.max(w / h, h / w) > MAX_ASPECT) continue;

      return url;
    } catch {
      // One candidate failing is why there is a list.
    }
  }
  return null;
}

// ─── Signed URLs ──────────────────────────────────────────────────────────
//
// AsyncImage sends no Authorization header — it is a URL loader, not an API
// client — so a Bearer-gated image endpoint 401s on every card and the feed
// renders empty grey bands where the pictures should be. The URL has to carry
// its own proof.
//
// It is an HMAC over (user, message) and NOT the user id itself: an id in a
// query string ends up in logs, referrers and screenshots, and this one is
// stable for the life of the account. The server finds candidate rows by
// message id and accepts the one whose signature matches, so the URL proves
// possession without naming anybody.
//
// Keyed on OPENAI_API_KEY rather than a new secret so there is nothing to
// forget to set: it is already required for the app to work at all, it never
// leaves the server, and it is used here only as HMAC key material.
const crypto = require('crypto');

function signImage(userId, messageId) {
  const secret = process.env.IMAGE_URL_SECRET || process.env.OPENAI_API_KEY || '';
  return crypto.createHmac('sha256', secret)
    .update(`${userId}:${messageId}`)
    .digest('base64url')
    .slice(0, 22);
}

function buildImageUrl(host, userId, messageId) {
  const token = signImage(userId, messageId);
  return `https://${host}/messages/${encodeURIComponent(messageId)}/image?t=${token}`;
}

module.exports = {
  extractHtml, pickCandidates, pickHeroImage, resolveBest, signImage, buildImageUrl,
};
