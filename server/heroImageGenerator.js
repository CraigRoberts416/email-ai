const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const { query } = require('./db');

const DOP_PROMPT = fs.readFileSync(path.join(__dirname, 'prompts', 'hero-dop.txt'), 'utf8');

const FREE_MAIL_DOMAINS = new Set([
  'gmail.com', 'yahoo.com', 'outlook.com', 'hotmail.com',
  'icloud.com', 'live.com', 'msn.com', 'ymail.com', 'aol.com',
  'protonmail.com', 'proton.me',
]);

function rootDomain(domain) {
  if (!domain) return '';
  const parts = domain.toLowerCase().split('.');
  return parts.slice(-2).join('.');
}

function isGeneratable(domain) {
  const root = rootDomain(domain);
  return !!root && !FREE_MAIL_DOMAINS.has(root);
}

// Render-time gate: don't launch duplicate jobs for the same domain.
const inFlight = new Set();

// A feed names hundreds of senders at once, and the per-domain dedupe below
// was never a concurrency limit — distinct domains all started at the same
// time. That is how one request turned into 250 simultaneous image
// generations, exhausted the image quota, and took the instance with it.
const MAX_IN_FLIGHT = 3;

// Domains that failed recently. Some fail permanently — a brand name the
// safety system refuses to draw will refuse every time — and without this
// every feed request pays for the same rejection again.
const failedAt = new Map();
const FAILURE_BACKOFF_MS = 60 * 60 * 1000;

// ─── Color helpers ────────────────────────────────────────────────────────

function rgbToHex(r, g, b) {
  return '#' + [r, g, b].map(v => {
    const clamped = Math.max(0, Math.min(255, Math.round(v)));
    return clamped.toString(16).padStart(2, '0');
  }).join('').toUpperCase();
}

// Resize to a tiny thumbnail and average all RGB pixels.
// For stylized AI images this yields a pleasing "mood" color that's close
// to the dominant tone without needing a full palette algorithm.
async function extractBgColor(imageBuffer) {
  const { data, info } = await sharp(imageBuffer)
    .resize(40, 40, { fit: 'cover' })
    .removeAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });

  let r = 0, g = 0, b = 0, count = 0;
  for (let i = 0; i < data.length; i += info.channels) {
    r += data[i];
    g += data[i + 1];
    b += data[i + 2];
    count++;
  }
  if (!count) return '#0D1B3E';

  r /= count; g /= count; b /= count;

  // Darken the average by ~40% so the surface sits below the image tonally.
  r *= 0.6; g *= 0.6; b *= 0.6;
  return rgbToHex(r, g, b);
}

// ─── DB access ────────────────────────────────────────────────────────────

async function getDescription(domain) {
  const root = rootDomain(domain);
  if (!root) return null;
  const { rows } = await query(
    'SELECT description FROM sender_domain_assets WHERE domain = $1',
    [root]
  );
  return rows[0]?.description ?? null;
}

async function getCachedAsset(domain) {
  const root = rootDomain(domain);
  if (!root) return null;
  const { rows } = await query(
    'SELECT bg_color, description FROM sender_domain_assets WHERE domain = $1',
    [root]
  );
  return rows[0]
    ? { domain: root, bgColor: rows[0].bg_color, description: rows[0].description ?? null }
    : null;
}

async function getCachedImageBytes(domain) {
  const root = rootDomain(domain);
  if (!root) return null;
  const { rows } = await query(
    'SELECT image_bytes, image_mime FROM sender_domain_assets WHERE domain = $1',
    [root]
  );
  return rows[0] ? { bytes: rows[0].image_bytes, mime: rows[0].image_mime } : null;
}

async function saveAsset(domain, imageBuffer, mime, bgColor, description) {
  const root = rootDomain(domain);
  await query(
    `INSERT INTO sender_domain_assets (domain, image_bytes, image_mime, bg_color, description)
     VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (domain) DO NOTHING`,
    [root, imageBuffer, mime, bgColor, description ?? null]
  );
}

/// One line about who a sender is — the thing a profile's bio slot is for.
///
/// Deliberately not a summary of their mail: the counts under it already
/// report volume and demand, and saying the same thing in prose spends the one
/// line that could tell the reader something they did not already know.
///
/// Returns null rather than a guess. An empty bio is a missing sentence; a
/// wrong one is the product asserting something false about a real company,
/// on a screen whose entire job is identification.
async function generateDescription(openai, senderName, domain) {
  try {
    const response = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      temperature: 0.3,
      max_tokens: 60,
      messages: [{
        role: 'user',
        content: [
          'Write one line describing who this email sender is, for a profile page in a mail app.',
          '',
          `Sender: ${senderName || domain}`,
          `Domain: ${domain}`,
          '',
          'RULES',
          '- Under 90 characters. One sentence, or a short fragment plus a sentence.',
          '- Say what the organisation IS and what it sends. "The airline. Booking',
          '  confirmations, schedule changes, and SkyMiles."',
          '- Never describe the reader\'s relationship to them, their volume of mail,',
          '  or whether it needs attention. That is counted elsewhere.',
          '- No marketing language, no adjectives the company would choose for itself.',
          '- If you do not recognise the sender, reply with exactly: UNKNOWN',
        ].join('\n'),
      }],
    });

    const text = response.choices?.[0]?.message?.content?.trim();
    if (!text || text === 'UNKNOWN' || text.length > 140) return null;
    return text;
  } catch (err) {
    console.warn(`[hero] description failed for ${domain}: ${err?.message ?? err}`);
    return null;
  }
}

// ─── OpenAI image generation ──────────────────────────────────────────────

function buildPrompt(senderName, domain) {
  return DOP_PROMPT
    .replace(/\{\{senderName\}\}/g, senderName || domain)
    .replace(/\{\{domain\}\}/g, domain);
}

async function generateImage(openai, prompt) {
  // gpt-image-1.5 is the user-requested model; fall back to gpt-image-1 if
  // the account doesn't have access yet.
  const models = ['gpt-image-1.5', 'gpt-image-1'];
  let lastErr;
  for (const model of models) {
    try {
      const result = await openai.images.generate({
        model,
        prompt,
        size: '1536x1024',
        n: 1,
      });
      const b64 = result?.data?.[0]?.b64_json;
      if (!b64) throw new Error('empty image response');
      return Buffer.from(b64, 'base64');
    } catch (err) {
      lastErr = err;
      if (err?.status === 404 || /model/i.test(err?.message ?? '')) {
        continue;
      }
      throw err;
    }
  }
  throw lastErr ?? new Error('image generation failed');
}

// ─── Public API ───────────────────────────────────────────────────────────

// Ensure a hero asset exists for the domain.
// - If one exists: no-op
// - If not: kicks off async generation (fire-and-forget); returns immediately
function ensureHeroAsset(openai, domain, senderName) {
  const root = rootDomain(domain);
  if (!isGeneratable(root)) return;
  if (inFlight.has(root)) return;

  const failed = failedAt.get(root);
  if (failed && Date.now() - failed < FAILURE_BACKOFF_MS) return;

  // Opportunistic by definition: skipping one costs that sender its picture
  // until the next request, and costs the feed nothing at all.
  if (inFlight.size >= MAX_IN_FLIGHT) return;

  inFlight.add(root);

  (async () => {
    try {
      const existing = await getCachedAsset(root);
      if (existing) return;

      const prompt = buildPrompt(senderName, root);
      // In parallel: the description is a cheap text call and has no reason to
      // wait on an image generation that takes an order of magnitude longer.
      const [imageBuffer, description] = await Promise.all([
        generateImage(openai, prompt),
        generateDescription(openai, senderName, root),
      ]);
      const bgColor = await extractBgColor(imageBuffer);
      await saveAsset(root, imageBuffer, 'image/png', bgColor, description);
      console.log(`[hero] generated asset for ${root} (bg ${bgColor}${description ? ', described' : ''})`);
    } catch (err) {
      failedAt.set(root, Date.now());
      console.warn(`[hero] generation failed for ${root}:`, err?.message ?? err);
    } finally {
      inFlight.delete(root);
    }
  })();
}

// Build the URL the client should hit to load the image.
function buildHeroImageUrl(req, domain) {
  const root = rootDomain(domain);
  if (!isGeneratable(root)) return null;

  // `trust proxy` makes req.protocol honour X-Forwarded-Proto, but a URL that
  // silently degrades to http:// costs the whole feature — iOS blocks the
  // request under App Transport Security and AsyncImage has nowhere to report
  // it, so the image just never appears. Anything that isn't localhost is
  // https, and that is not a guess: this server is only reachable over TLS.
  const host = req.get('host') || '';
  const isLocal = /^(localhost|127\.0\.0\.1|\[::1\])(:|$)/.test(host);
  const scheme = isLocal ? req.protocol : 'https';
  return `${scheme}://${host}/hero-image/${encodeURIComponent(root)}`;
}

module.exports = {
  rootDomain,
  isGeneratable,
  getCachedAsset,
  getCachedImageBytes,
  ensureHeroAsset, getDescription,
  buildHeroImageUrl,
};
