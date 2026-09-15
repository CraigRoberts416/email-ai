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
