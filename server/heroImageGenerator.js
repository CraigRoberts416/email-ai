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

async function getCachedAsset(domain) {
  const root = rootDomain(domain);
  if (!root) return null;
  const { rows } = await query(
    'SELECT bg_color FROM sender_domain_assets WHERE domain = $1',
    [root]
  );
  return rows[0] ? { domain: root, bgColor: rows[0].bg_color } : null;
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

async function saveAsset(domain, imageBuffer, mime, bgColor) {
  const root = rootDomain(domain);
  await query(
    `INSERT INTO sender_domain_assets (domain, image_bytes, image_mime, bg_color)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (domain) DO NOTHING`,
    [root, imageBuffer, mime, bgColor]
  );
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

  inFlight.add(root);

  (async () => {
    try {
      const existing = await getCachedAsset(root);
      if (existing) return;

      const prompt = buildPrompt(senderName, root);
      const imageBuffer = await generateImage(openai, prompt);
      const bgColor = await extractBgColor(imageBuffer);
      await saveAsset(root, imageBuffer, 'image/png', bgColor);
      console.log(`[hero] generated asset for ${root} (bg ${bgColor})`);
    } catch (err) {
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
  const base = `${req.protocol}://${req.get('host')}`;
  return `${base}/hero-image/${encodeURIComponent(root)}`;
}

module.exports = {
  rootDomain,
  isGeneratable,
  getCachedAsset,
  getCachedImageBytes,
  ensureHeroAsset,
  buildHeroImageUrl,
};
