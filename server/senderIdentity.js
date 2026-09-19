const { getDomain, parse } = require('tldts');

const FREE_MAIL_DOMAINS = new Set([
  'gmail.com', 'googlemail.com', 'yahoo.com', 'outlook.com', 'hotmail.com',
  'icloud.com', 'live.com', 'msn.com', 'ymail.com', 'aol.com', 'protonmail.com', 'proton.me',
]);

// Public suffixes can contain several labels (amazon.co.uk, not co.uk).
// Use the URL parser for hostname validation before the suffix lookup.
function canonicalDomain(value) {
  if (typeof value !== 'string' || !value || /[\s/@?#:]/.test(value)) return '';
  try {
    const host = new URL(`https://${value}`).hostname.toLowerCase();
    const info = parse(host, { allowPrivateDomains: true, extractHostname: false });
    if (info.isIp || !info.domain || (!info.isIcann && !info.isPrivate)) return '';
    return getDomain(host, { allowPrivateDomains: true, extractHostname: false }) || '';
  } catch { return ''; }
}

function avatarURL(domain, token) {
  const root = canonicalDomain(domain);
  if (!root || FREE_MAIL_DOMAINS.has(root)) return null;
  return `https://img.logo.dev/${root}?token=${encodeURIComponent(token)}`;
}

function registerSenderIdentityRoute(app, { resolveUserId, heroImage, logoToken }) {
  app.get('/sender-identity', async (req, res) => {
    try {
      if (!await resolveUserId(req)) return res.status(401).json({ error: 'unauthorized' });
      const address = typeof req.query.address === 'string' ? req.query.address.trim().toLowerCase() : '';
      const parts = address.split('@');
      if (address.length > 320 || parts.length !== 2 || !parts[0] || /\s/.test(address)) {
        return res.status(400).json({ error: 'invalid sender address' });
      }
      const domain = canonicalDomain(parts[1]);
      if (!domain) return res.status(400).json({ error: 'invalid sender domain' });
      // Identity survives inbox membership. This endpoint only reads assets
      // already held for the domain; it never generates art or queries contacts.
      const asset = FREE_MAIL_DOMAINS.has(domain) ? null : await heroImage.getCachedAsset(domain);
      res.setHeader('Cache-Control', 'private, max-age=3600');
      return res.json({
        address,
        avatarUri: avatarURL(domain, logoToken),
        heroImageUrl: asset ? heroImage.buildHeroImageUrl(req, domain) : null,
        heroImageBgColor: asset?.bgColor ?? null,
        senderDescription: asset?.description ?? null,
      });
    } catch (error) {
      console.error('[sender-identity] lookup failed:', error.message);
      return res.status(500).json({ error: 'sender identity unavailable' });
    }
  });
}

module.exports = { canonicalDomain, avatarURL, FREE_MAIL_DOMAINS, registerSenderIdentityRoute };
