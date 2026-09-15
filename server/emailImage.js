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
];

/// Declared dimensions below this are decoration at best and a beacon at worst.
const MIN_EDGE = 180;

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
 * The one image worth showing from this email, or null.
 *
 * Deliberately conservative: a wrong picture on a card is worse than none,
 * because the card is a claim about what the message is. When nothing clears
 * the bar the post falls back to the sender's generated hero, which is honest
 * about being a stand-in.
 */
function pickHeroImage(html) {
  if (!html) return null;

  const tags = html.match(/<img\b[^>]*>/gi) ?? [];
  const candidates = [];

  for (const tag of tags) {
    const src = attr(tag, 'src');
    if (!src || !/^https?:\/\//i.test(src)) continue;

    const url = src.replace(/&amp;/g, '&');
    const lower = url.toLowerCase();
    if (FURNITURE.some(word => lower.includes(word))) continue;

    const width = declaredEdge(tag, 'width');
    const height = declaredEdge(tag, 'height');
    // A stated size that is small is a real answer, and the answer is no.
    if ((width !== null && width < MIN_EDGE) || (height !== null && height < MIN_EDGE)) continue;

    candidates.push({ url, area: (width ?? 0) * (height ?? 0), stated: width !== null });
  }

  if (!candidates.length) return null;

  // Prefer the largest thing the email actually sized. Among unsized images,
  // document order wins: the first big picture in a marketing email is nearly
  // always the one the layout was built around.
  const sized = candidates.filter(c => c.stated && c.area > 0);
  if (sized.length) {
    return sized.reduce((best, c) => (c.area > best.area ? c : best)).url;
  }
  return candidates[0].url;
}

module.exports = { extractHtml, pickHeroImage };
