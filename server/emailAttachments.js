// The files an email actually carried.
//
// Gmail hands these back inside the same payload tree the body lives in, as
// parts with a `filename` and a `body.attachmentId`. Nothing in this product
// read them until now, so an email with a signed contract on it looked
// identical to one with nothing attached — and "did they send it?" is one of
// the few questions a mail client is genuinely for.
//
// Only metadata is extracted here. The bytes stay on Gmail until someone asks
// for them, which keeps a 20MB deck out of the interpretation path.

/// Parts that are structure rather than content. An inline logo has a
/// filename and an attachment id exactly like a real attachment does.
const INLINE_TYPES = new Set(['image/gif']);

/// Under this an "attachment" is a tracking image, a signature logo, or a
/// spacer that happens to have been given a name.
const MIN_BYTES = 8 * 1024;

function extension(filename) {
  const match = /\.([A-Za-z0-9]{1,6})$/.exec(filename ?? '');
  return match ? match[1].toLowerCase() : '';
}

/// Pages, when the format states them cheaply. A PDF's page count is in its
/// bytes, which we do not have here — so this is null rather than a guess, and
/// the tile renders the type alone.
function pageCount() {
  return null;
}

/**
 * Walks the payload for real attachments, newest-first order preserved.
 *
 * `Content-Disposition: inline` is the signal that separates a picture used in
 * the layout from a picture the sender meant to send you. Gmail does not
 * always set it, so size is the backstop.
 */
function extractAttachments(payload, { limit = 8, minimumBytes = MIN_BYTES, allowGIF = false, includeInlineImages = false } = {}) {
  const found = [];

  function walk(part) {
    if (!part) return;

    const filename = part.filename ?? '';
    const attachmentId = part.body?.attachmentId;
    const size = Number(part.body?.size ?? 0);

    if (filename && attachmentId) {
      const headers = part.headers ?? [];
      const disposition = headers
        .find(h => h.name?.toLowerCase() === 'content-disposition')?.value ?? '';
      const isInline = /^\s*inline/i.test(disposition);
      const mimeType = part.mimeType ?? 'application/octet-stream';

      // Personal photos pasted into a Gmail body are inline CID attachments.
      // Complete source galleries include these; feed previews keep their
      // existing compact attachment policy.
      if ((!isInline || (includeInlineImages && mimeType.startsWith('image/')))
          && size >= minimumBytes && (allowGIF || !INLINE_TYPES.has(mimeType))) {
        found.push({
          id: attachmentId,
          filename,
          mimeType,
          byteCount: size,
          extension: extension(filename),
          isImage: mimeType.startsWith('image/'),
          pages: pageCount(),
        });
      }
    }

    for (const child of part.parts ?? []) walk(child);
  }

  walk(payload);

  // Eight is already more than a card can show without becoming a file
  // browser, and the thread lists the rest.
  return found.slice(0, limit);
}

module.exports = { extractAttachments };
