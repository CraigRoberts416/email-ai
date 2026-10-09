'use strict';

const INLINE_IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/avif', 'image/heic']);

function extractBody(payload, mimeType) {
  if (!payload) return '';
  if (payload.mimeType === mimeType && payload.body?.data) {
    return Buffer.from(payload.body.data, 'base64url').toString('utf8');
  }
  for (const part of payload.parts ?? []) {
    const value = extractBody(part, mimeType);
    if (value) return value;
  }
  return '';
}

function contentID(value) {
  try { return decodeURIComponent(value).trim().replace(/^<|>$/g, ''); }
  catch { return value.trim().replace(/^<|>$/g, ''); }
}

// Gmail stores embedded images as separate MIME parts. WebKit cannot resolve
// cid: by itself. Resolve only parts in this message, using owner-signed URLs.
function prepareEmailBody(payload, attachmentURL) {
  const inline = new Map();
  function walk(part) {
    if (!part) return;
    const mime = (part.mimeType ?? '').toLowerCase();
    const header = (part.headers ?? []).find(item => item.name?.toLowerCase() === 'content-id');
    if (header?.value && INLINE_IMAGE_TYPES.has(mime)) {
      let source;
      if (part.body?.data) {
        source = `data:${mime};base64,${Buffer.from(part.body.data, 'base64url').toString('base64')}`;
      } else if (part.body?.attachmentId) {
        source = attachmentURL(part.body.attachmentId, mime);
      }
      if (source) inline.set(contentID(header.value), source);
    }
    for (const child of part.parts ?? []) walk(child);
  }
  walk(payload);
  const htmlRaw = extractBody(payload, 'text/html').replace(/cid:([^\s"'<>\)]+)/gi,
    (original, id) => inline.get(contentID(id)) ?? original);
  return { plainText: extractBody(payload, 'text/plain'), htmlRaw };
}

module.exports = { prepareEmailBody, INLINE_IMAGE_TYPES };
